class_name PianoRoll
extends Control

# Piano-roll view/editor for a MusicPattern. Draws a beat grid + notes,
# handles click-to-create, drag-to-move, drag-right-edge to resize, and
# Delete to remove. The owning PatternEditor provides toolbar chrome and
# a note-property footer.
#
# Coordinate system:
#   X: GUTTER_WIDTH + beat * beat_width
#   Y: (max_row - row) * row_height     (higher rows toward top)
#
# Row semantics depend on track_type (see _row_label).

signal selection_changed(selected: Array)
## Emitted when a PatternBend is selected (or selection cleared). `bend`
## and `parent_note` are null when cleared. Bend selection is exclusive
## with note selection — picking a bend clears the note selection and
## vice-versa.
signal bend_selection_changed(bend: PatternBend, parent_note: PatternNote)
signal pattern_changed

enum DragState { IDLE, CREATING, MOVING, RESIZING, MARQUEE, SEEKING, BEND_TIP }

const GUTTER_WIDTH: float = 64.0
const RULER_HEIGHT: float = 20.0
const RESIZE_MARGIN: float = 6.0

const BG_COLOR := Color(0.10, 0.10, 0.12)
const GUTTER_COLOR := Color(0.06, 0.06, 0.08)
const ROW_ROOT := Color(0.35, 0.70, 0.45, 0.12)
const ROW_OCTAVE := Color(1.0, 1.0, 1.0, 0.04)
const GRID_SUB := Color(1.0, 1.0, 1.0, 0.04)
const GRID_BEAT := Color(1.0, 1.0, 1.0, 0.12)
const GRID_BAR := Color(1.0, 1.0, 1.0, 0.25)
const ACCIDENTAL_SHIFT: float = 0.25  # fraction of row_height per semitone
const MARQUEE_FILL := Color(0.97, 0.73, 0.33, 0.15)
const MARQUEE_BORDER := Color(0.97, 0.73, 0.33, 0.75)
const NOTE_FILL := Color(0.42, 0.65, 0.92)
const NOTE_BORDER := Color(0.90, 0.95, 1.0)
const NOTE_SELECTED := Color(0.97, 0.73, 0.33)
const BEND_LINE := Color(0.40, 0.90, 0.75, 0.95)
const BEND_LINE_SELECTED := Color(0.97, 0.73, 0.33, 0.95)
const BEND_TIP := Color(0.85, 1.0, 0.95)
const BEND_TIP_RADIUS: float = 5.0
const BEND_SEGMENT_HIT_TOL: float = 4.0
const LABEL_COLOR := Color(0.70, 0.72, 0.78)
const ACCIDENTAL_COLOR := Color(1.0, 1.0, 0.5)
const RULER_BG := Color(0.04, 0.04, 0.06)
const RULER_LABEL := Color(0.85, 0.88, 0.95)
const PLAYHEAD_COLOR := Color(1.0, 0.95, 0.4, 0.95)
const PLAYHEAD_HANDLE := Color(1.0, 0.75, 0.25)

@export var pattern: MusicPattern:
	set(value):
		pattern = value
		_selected.clear()
		_drag_state = DragState.IDLE
		selection_changed.emit(_selected)
		_update_min_size()
		queue_redraw()

@export var track_type: MusicTrack.TrackType = MusicTrack.TrackType.CHORD:
	set(value):
		track_type = value
		queue_redraw()

@export var beat_width: float = 60.0:
	set(value):
		beat_width = maxf(10.0, value)
		_update_min_size()
		queue_redraw()

@export var row_height: float = 16.0:
	set(value):
		row_height = maxf(8.0, value)
		_update_min_size()
		queue_redraw()

## Snap grid: 1=whole, 2=half, 4=quarter, 8=8th, 16=16th.
@export var grid_subdivisions: int = 4:
	set(value):
		grid_subdivisions = maxi(1, value)
		queue_redraw()

@export var min_row: int = -8
@export var max_row: int = 24

## Optional MusicDirector reference. When set, draws a movable playback
## indicator at the current beat within the pattern. Click+drag in the
## ruler strip (top of the control) to seek.
@export var director: MusicDirector:
	set(value):
		director = value
		set_process(value != null)
		queue_redraw()

var _selected: Array = []
var _clipboard: Array = []  # Array of PatternNote (deep copies)
var _last_mouse_pos: Vector2 = Vector2.ZERO
var _drag_state: int = DragState.IDLE
var _drag_note: PatternNote
var _drag_bend: PatternBend
# The Array that holds _drag_bend (either a note's `bends` or another
# bend's `bends`). Kept alongside _drag_bend so deletion can erase from
# the right collection.
var _drag_bend_parent_array: Array
var _drag_bend_note: PatternNote
# Beat coordinate where the dragged bend "starts" (= parent_start_beat +
# bend.offset_beats). Used during tip drag to recompute glide_beats from
# the cursor position without re-walking the bend chain.
var _drag_bend_start_beat: float = 0.0
var _selected_bend: PatternBend
var _selected_bend_parent_array: Array
var _selected_bend_note: PatternNote
var _drag_start_pos: Vector2
var _drag_origin: Dictionary = {}
var _marquee_anchor: Vector2
var _marquee_add: bool = false
var _font: Font

func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = ThemeDB.fallback_font
	set_process(director != null)
	_update_min_size()

func _process(_delta: float) -> void:
	# Repaint continuously while previewing so the playhead tracks smoothly.
	if director != null and director.playing:
		queue_redraw()

func refresh() -> void:
	_update_min_size()
	queue_redraw()

func get_selected() -> Array:
	return _selected.duplicate()

func clear_selection() -> void:
	_selected.clear()
	selection_changed.emit(_selected)
	queue_redraw()

func _update_min_size() -> void:
	if pattern == null:
		custom_minimum_size = Vector2(GUTTER_WIDTH + 800.0, RULER_HEIGHT + 400.0)
		return
	var w: float = GUTTER_WIDTH + pattern.length_beats * beat_width
	var h: float = RULER_HEIGHT + float(max_row - min_row + 1) * row_height
	custom_minimum_size = Vector2(w, h)

# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG_COLOR)
	if pattern == null:
		return
	_draw_row_backgrounds()
	_draw_grid_lines()
	_draw_notes()
	_draw_bends()
	_draw_ruler()
	_draw_gutter()
	if _drag_state == DragState.MARQUEE:
		_draw_marquee()
	_draw_playhead()

func _draw_marquee() -> void:
	var rect: Rect2 = Rect2(_marquee_anchor, _last_mouse_pos - _marquee_anchor).abs()
	draw_rect(rect, MARQUEE_FILL)
	draw_rect(rect, MARQUEE_BORDER, false, 1.0)

func _draw_ruler() -> void:
	draw_rect(Rect2(GUTTER_WIDTH, 0.0, size.x - GUTTER_WIDTH, RULER_HEIGHT), RULER_BG)
	draw_line(Vector2(GUTTER_WIDTH, RULER_HEIGHT), Vector2(size.x, RULER_HEIGHT), GRID_BAR, 1.0)
	# Beat numbers at every whole beat.
	var total: float = pattern.length_beats
	var b: int = 0
	while float(b) <= total + 0.0001:
		var x: float = GUTTER_WIDTH + float(b) * beat_width
		var tick_h: float = RULER_HEIGHT * 0.4 if b % 4 != 0 else RULER_HEIGHT * 0.7
		draw_line(Vector2(x, RULER_HEIGHT - tick_h), Vector2(x, RULER_HEIGHT), GRID_BAR, 1.0)
		draw_string(_font, Vector2(x + 3.0, RULER_HEIGHT - 6.0), "%d" % b,
			HORIZONTAL_ALIGNMENT_LEFT, beat_width, 10, RULER_LABEL)
		b += 1

func _draw_playhead() -> void:
	if director == null or pattern == null or pattern.length_beats <= 0.0:
		return
	var cursor: float = fposmod(director.get_total_beats(), pattern.length_beats)
	var x: float = GUTTER_WIDTH + cursor * beat_width
	if x < GUTTER_WIDTH or x > size.x:
		return
	draw_line(Vector2(x, RULER_HEIGHT), Vector2(x, size.y), PLAYHEAD_COLOR, 2.0)
	# Handle on the ruler strip.
	var tri := PackedVector2Array([
		Vector2(x - 6.0, 0.0),
		Vector2(x + 6.0, 0.0),
		Vector2(x, RULER_HEIGHT - 2.0),
	])
	draw_colored_polygon(tri, PLAYHEAD_HANDLE)

func _draw_row_backgrounds() -> void:
	var octave_size: int = _rows_per_octave()
	for row in range(min_row, max_row + 1):
		var y: float = _row_y(row)
		if row == 0:
			draw_rect(Rect2(GUTTER_WIDTH, y, size.x - GUTTER_WIDTH, row_height), ROW_ROOT)
		elif octave_size > 0 and posmod(row, octave_size) == 0:
			draw_rect(Rect2(GUTTER_WIDTH, y, size.x - GUTTER_WIDTH, row_height), ROW_OCTAVE)

func _draw_grid_lines() -> void:
	for row in range(min_row, max_row + 1):
		var y: float = _row_y(row)
		draw_line(Vector2(GUTTER_WIDTH, y), Vector2(size.x, y), GRID_SUB, 1.0)
	var total: float = pattern.length_beats
	var sub_step: float = 1.0 / float(grid_subdivisions)
	var b: float = 0.0
	while b <= total + 0.0001:
		var x: float = GUTTER_WIDTH + b * beat_width
		var col: Color
		if is_equal_approx(fmod(b, 4.0), 0.0) or is_zero_approx(b):
			col = GRID_BAR
		elif is_equal_approx(fmod(b, 1.0), 0.0):
			col = GRID_BEAT
		else:
			col = GRID_SUB
		draw_line(Vector2(x, RULER_HEIGHT), Vector2(x, size.y), col, 1.0)
		b += sub_step
	# Pattern end marker
	var end_x: float = GUTTER_WIDTH + total * beat_width
	draw_line(Vector2(end_x, RULER_HEIGHT), Vector2(end_x, size.y), GRID_BAR, 2.0)

func _draw_notes() -> void:
	for note in pattern.notes:
		var rect: Rect2 = _note_rect(note)
		var fill: Color = NOTE_SELECTED if _selected.has(note) else NOTE_FILL
		fill.a = lerpf(0.45, 1.0, note.velocity)
		draw_rect(rect, fill)
		draw_rect(rect, NOTE_BORDER, false, 1.0)
		if track_type != MusicTrack.TrackType.DRUM and note.accidental != 0:
			var sym: String = "#" if note.accidental > 0 else "b"
			draw_string(_font, Vector2(rect.position.x + 3.0, rect.end.y - 3.0), sym,
				HORIZONTAL_ALIGNMENT_LEFT, rect.size.x, 10, ACCIDENTAL_COLOR)

func _draw_bends() -> void:
	for note in pattern.notes:
		for bend in note.bends:
			_draw_bend_recursive(note.beat, note.index, note.accidental, note, bend)

## Draw [param bend] as a line from (parent_start_beat, parent_pitch_y)
## sloping to (parent_start_beat + offset + glide, target_pitch_y). Then
## recurse: child bends draw with this bend's tip as their visual
## anchor. Time-anchor for the child is this bend's start beat (matches
## runtime — child.offset is relative to parent bend's start, not its end).
func _draw_bend_recursive(parent_start_beat: float, parent_index: int, parent_acc: float,
		note: PatternNote, bend: PatternBend) -> void:
	var start_beat: float = parent_start_beat + bend.offset_beats
	var end_beat: float = start_beat + bend.glide_beats
	var start: Vector2 = _bend_anchor(start_beat, parent_index, parent_acc)
	var tip: Vector2 = _bend_anchor(end_beat, bend.index, bend.accidental)
	var is_sel: bool = bend == _selected_bend
	var col: Color = BEND_LINE_SELECTED if is_sel else BEND_LINE
	draw_line(start, tip, col, 2.0)
	# Tip handle — grabbable point for retarget / resize-glide.
	draw_circle(tip, BEND_TIP_RADIUS, BEND_TIP if is_sel else col)
	if is_sel:
		draw_circle(tip, BEND_TIP_RADIUS, BEND_LINE_SELECTED, false, 1.5)
	# Recurse — child's "parent pitch" visually equals this bend's target.
	for child in bend.bends:
		_draw_bend_recursive(start_beat, bend.index, bend.accidental, note, child)

func _bend_anchor(beat: float, row_index: int, accidental: float) -> Vector2:
	var x: float = GUTTER_WIDTH + beat * beat_width
	# Center vertically on the row; lift by accidental shift (only MELODY
	# tracks visualize accidental — for CHORD/DRUM the shift is zero so
	# this is harmless).
	var y: float = _row_y(row_index) + row_height * 0.5
	if track_type != MusicTrack.TrackType.DRUM:
		y -= accidental * row_height * ACCIDENTAL_SHIFT
	return Vector2(x, y)

func _draw_gutter() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(GUTTER_WIDTH, size.y)), GUTTER_COLOR)
	draw_line(Vector2(GUTTER_WIDTH, 0.0), Vector2(GUTTER_WIDTH, size.y), GRID_BAR, 1.0)
	for row in range(min_row, max_row + 1):
		var y: float = _row_y(row)
		var label: String = _row_label(row)
		if label != "":
			draw_string(_font, Vector2(4.0, y + row_height - 4.0), label,
				HORIZONTAL_ALIGNMENT_LEFT, GUTTER_WIDTH - 8.0, 10, LABEL_COLOR)

# ---------------------------------------------------------------------------
# Row semantics
# ---------------------------------------------------------------------------

func _rows_per_octave() -> int:
	match track_type:
		MusicTrack.TrackType.CHORD:
			return 3
		MusicTrack.TrackType.MELODY:
			return 7
		_:
			return 12

func _row_label(row: int) -> String:
	match track_type:
		MusicTrack.TrackType.CHORD:
			return "t%d" % row
		MusicTrack.TrackType.MELODY:
			var degrees := ["I", "II", "III", "IV", "V", "VI", "VII"]
			var idx: int = posmod(row, 7)
			var oct: int = int(floorf(float(row) / 7.0))
			var suffix: String = ""
			if oct != 0:
				suffix = "+%d" % oct if oct > 0 else "%d" % oct
			return degrees[idx] + suffix
		_:
			return _midi_note_name(row)

func _midi_note_name(midi: int) -> String:
	var names := ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
	var n: int = posmod(midi, 12)
	var oct: int = int(floorf(float(midi) / 12.0)) - 1
	return "%s%d" % [names[n], oct]

# ---------------------------------------------------------------------------
# Pixel/beat/row math
# ---------------------------------------------------------------------------

func _row_y(row: int) -> float:
	return RULER_HEIGHT + float(max_row - row) * row_height

func _y_to_row(y: float) -> int:
	return max_row - int(floorf((y - RULER_HEIGHT) / row_height))

func _x_to_beat(x: float) -> float:
	return (x - GUTTER_WIDTH) / beat_width

func _snap_beat(b: float) -> float:
	var q: float = 1.0 / float(grid_subdivisions)
	return roundf(b / q) * q

# ---------------------------------------------------------------------------
# Hit testing
# ---------------------------------------------------------------------------

## Visible rect for a note, including the MELODY accidental offset (shifts
## notes up/down by ACCIDENTAL_SHIFT * row_height per semitone).
func _note_rect(note: PatternNote) -> Rect2:
	var y: float = _row_y(note.index)
	var x: float = GUTTER_WIDTH + note.beat * beat_width
	var w: float = maxf(2.0, note.duration * beat_width)
	var shift: float = 0.0
	if track_type != MusicTrack.TrackType.DRUM:
		shift = -float(note.accidental) * row_height * ACCIDENTAL_SHIFT
	return Rect2(x, y + shift + 1.0, w, row_height - 2.0)

## Find a bend whose tip handle or segment is under [param pos]. Returns
## a dict {bend, parent_array, note, start_beat} for a hit, or {} for miss.
## Tips are preferred over segments (smaller hit area, higher priority).
## Children are walked first so nested bends layered on top of their
## parents are pickable.
func _bend_at(pos: Vector2) -> Dictionary:
	if pattern == null:
		return {}
	# Two passes: tips first (preferred), then segments. Within each
	# pass, iterate notes/bends in reverse so later-drawn = topmost.
	var tip_hit: Dictionary = {}
	var seg_hit: Dictionary = {}
	for ni in range(pattern.notes.size() - 1, -1, -1):
		var note: PatternNote = pattern.notes[ni]
		var found: Dictionary = _bend_at_recursive(pos, note.beat, note.index, note.accidental,
			note, note.bends)
		if not found.is_empty():
			if found.get("tip", false):
				tip_hit = found
				break
			elif seg_hit.is_empty():
				seg_hit = found
	if not tip_hit.is_empty():
		return tip_hit
	return seg_hit

func _bend_at_recursive(pos: Vector2, parent_start_beat: float, parent_index: int,
		parent_acc: float, note: PatternNote, bends: Array[PatternBend]) -> Dictionary:
	# Walk children first (topmost), then siblings in reverse insertion
	# order so visually-on-top bends win the hit test.
	for i in range(bends.size() - 1, -1, -1):
		var bend: PatternBend = bends[i]
		var start_beat: float = parent_start_beat + bend.offset_beats
		var end_beat: float = start_beat + bend.glide_beats
		var start: Vector2 = _bend_anchor(start_beat, parent_index, parent_acc)
		var tip: Vector2 = _bend_anchor(end_beat, bend.index, bend.accidental)
		# Recurse into this bend's children first — they're drawn over.
		var nested: Dictionary = _bend_at_recursive(pos, start_beat, bend.index,
			bend.accidental, note, bend.bends)
		if not nested.is_empty():
			return nested
		if pos.distance_to(tip) <= BEND_TIP_RADIUS + 1.0:
			return {"bend": bend, "parent_array": bends, "note": note,
					"start_beat": start_beat, "tip": true}
		if _point_near_segment(pos, start, tip, BEND_SEGMENT_HIT_TOL):
			return {"bend": bend, "parent_array": bends, "note": note,
					"start_beat": start_beat, "tip": false}
	return {}

func _point_near_segment(p: Vector2, a: Vector2, b: Vector2, tol: float) -> bool:
	var ab: Vector2 = b - a
	var len_sq: float = ab.length_squared()
	if len_sq < 0.0001:
		return p.distance_to(a) <= tol
	var t: float = clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	var closest: Vector2 = a + ab * t
	return p.distance_to(closest) <= tol

func _note_at(pos: Vector2) -> PatternNote:
	if pattern == null:
		return null
	# Iterate in reverse so topmost notes are picked first.
	for i in range(pattern.notes.size() - 1, -1, -1):
		var note: PatternNote = pattern.notes[i]
		if _note_rect(note).has_point(pos):
			return note
	return null

func _near_right_edge(note: PatternNote, pos: Vector2) -> bool:
	var rect: Rect2 = _note_rect(note)
	return absf(pos.x - rect.end.x) < RESIZE_MARGIN

# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_handle_motion(event as InputEventMouseMotion)
	elif event is InputEventKey:
		_handle_key(event as InputEventKey)

func _handle_button(event: InputEventMouseButton) -> void:
	var pos: Vector2 = event.position
	_last_mouse_pos = pos
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			grab_focus()
			# Ruler click = seek.
			if pos.y < RULER_HEIGHT and pos.x >= GUTTER_WIDTH:
				_start_seek(pos)
				return
			if pos.x < GUTTER_WIDTH:
				return
			# Bend hits take priority over notes — their tips/segments
			# can overlap a note's rect and we'd miss them otherwise.
			var bend_hit: Dictionary = _bend_at(pos)
			if not bend_hit.is_empty():
				_select_bend(bend_hit["bend"], bend_hit["parent_array"], bend_hit["note"])
				if bend_hit.get("tip", false):
					_start_bend_tip_drag(bend_hit["start_beat"])
				return
			# Any other click clears the bend selection (note selection
			# updates below as usual).
			if _selected_bend != null:
				_clear_bend_selection()
				queue_redraw()
			var hit: PatternNote = _note_at(pos)
			if hit != null:
				if event.shift_pressed:
					_toggle_selection(hit)
					return
				if _near_right_edge(hit, pos):
					_start_resize(hit, pos)
				else:
					_start_move(hit, pos)
			else:
				if event.alt_pressed:
					_start_marquee(pos, event.shift_pressed)
					return
				if event.shift_pressed:
					# Shift+empty click: clear selection without creating a note.
					_selected.clear()
					selection_changed.emit(_selected)
					queue_redraw()
					return
				_start_create(pos)
		else:
			_end_drag()
	elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		# Bends first (overlay on top of notes).
		var bend_hit: Dictionary = _bend_at(pos)
		if not bend_hit.is_empty():
			_remove_bend(bend_hit["bend"], bend_hit["parent_array"])
			return
		var hit: PatternNote = _note_at(pos)
		if hit != null:
			_remove_note(hit)

func _handle_motion(event: InputEventMouseMotion) -> void:
	_last_mouse_pos = event.position
	if _drag_state == DragState.IDLE:
		var bend_hover: Dictionary = _bend_at(event.position)
		if not bend_hover.is_empty():
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if bend_hover.get("tip", false) else Control.CURSOR_ARROW
			return
		var hit: PatternNote = _note_at(event.position)
		if hit != null and _near_right_edge(hit, event.position):
			mouse_default_cursor_shape = Control.CURSOR_HSIZE
		else:
			mouse_default_cursor_shape = Control.CURSOR_ARROW
		return
	var pos: Vector2 = event.position
	if _drag_state == DragState.MARQUEE:
		queue_redraw()
		return
	if _drag_state == DragState.SEEKING:
		_update_seek(pos)
		return
	if _drag_state == DragState.BEND_TIP:
		_update_bend_tip_drag(pos)
		queue_redraw()
		return
	var min_dur: float = 1.0 / float(grid_subdivisions)
	match _drag_state:
		DragState.CREATING, DragState.RESIZING:
			var end_beat: float = _snap_beat(_x_to_beat(pos.x))
			end_beat = maxf(end_beat, _drag_note.beat + min_dur)
			_drag_note.duration = end_beat - _drag_note.beat
		DragState.MOVING:
			var dx: float = pos.x - _drag_start_pos.x
			var dy: float = pos.y - _drag_start_pos.y
			# Compute delta relative to the dragged note's origin, snapped,
			# then apply to every selected note.
			var anchor_origin: Dictionary = _drag_origin.get(_drag_note, {"beat": _drag_note.beat, "index": _drag_note.index})
			var anchor_new_beat: float = _snap_beat(float(anchor_origin["beat"]) + dx / beat_width)
			var beat_delta: float = anchor_new_beat - float(anchor_origin["beat"])
			var row_delta: int = int(roundf(-dy / row_height))
			for n in _selected:
				if _drag_origin.has(n):
					var o: Dictionary = _drag_origin[n]
					n.beat = maxf(0.0, float(o["beat"]) + beat_delta)
					n.index = clampi(int(o["index"]) + row_delta, min_row, max_row)
	pattern_changed.emit()
	queue_redraw()

func _handle_key(event: InputEventKey) -> void:
	if not event.pressed:
		return
	if event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE:
		if _selected_bend != null:
			_remove_bend(_selected_bend, _selected_bend_parent_array)
		else:
			_delete_selected()
		accept_event()
		return
	if event.ctrl_pressed or event.meta_pressed:
		match event.keycode:
			KEY_C:
				_copy_selected()
				accept_event()
			KEY_X:
				_copy_selected()
				_delete_selected()
				accept_event()
			KEY_V:
				_paste_at_mouse()
				accept_event()
			KEY_D:
				_duplicate_selected()
				accept_event()
			KEY_A:
				_select_all()
				accept_event()

func _start_create(pos: Vector2) -> void:
	var n := PatternNote.new()
	n.beat = _snap_beat(_x_to_beat(pos.x))
	n.duration = 1.0 / float(grid_subdivisions)
	n.index = _y_to_row(pos.y)
	n.velocity = 0.8
	pattern.notes.append(n)
	_selected = [n]
	_drag_state = DragState.CREATING
	_drag_note = n
	_drag_start_pos = pos
	selection_changed.emit(_selected)
	pattern_changed.emit()
	queue_redraw()

func _start_move(note: PatternNote, pos: Vector2) -> void:
	# Preserve multi-selection if the clicked note is already part of it;
	# otherwise the click replaces selection.
	if not _selected.has(note):
		_selected = [note]
	_drag_state = DragState.MOVING
	_drag_note = note
	_drag_start_pos = pos
	_drag_origin = {}
	for n in _selected:
		_drag_origin[n] = {"beat": n.beat, "index": n.index}
	selection_changed.emit(_selected)
	queue_redraw()

func _start_resize(note: PatternNote, pos: Vector2) -> void:
	_selected = [note]
	_drag_state = DragState.RESIZING
	_drag_note = note
	_drag_start_pos = pos
	_drag_origin = {"beat": note.beat, "index": note.index, "duration": note.duration}
	selection_changed.emit(_selected)
	queue_redraw()

func _end_drag() -> void:
	match _drag_state:
		DragState.MARQUEE:
			_commit_marquee()
		DragState.CREATING, DragState.MOVING, DragState.RESIZING, DragState.BEND_TIP:
			pattern_changed.emit()
	_drag_state = DragState.IDLE
	_drag_note = null
	_drag_bend = null
	queue_redraw()

func _remove_note(note: PatternNote) -> void:
	pattern.notes.erase(note)
	_selected.erase(note)
	# If the deleted note owned the selected bend, clear bend selection too.
	if _selected_bend_note == note:
		_clear_bend_selection()
	selection_changed.emit(_selected)
	pattern_changed.emit()
	queue_redraw()

func _remove_bend(bend: PatternBend, parent_array: Array) -> void:
	parent_array.erase(bend)
	if _selected_bend == bend:
		_clear_bend_selection()
	pattern_changed.emit()
	queue_redraw()

## Programmatic API for the surrounding PatternEditor: append a new
## PatternBend onto [param parent_array] with sensible defaults, select
## it, and return it. The caller picks the parent (a PatternNote.bends
## or another PatternBend.bends array) and a default target row.
func add_bend(parent_array: Array, parent_note: PatternNote, default_target_index: int) -> PatternBend:
	var b := PatternBend.create(0.0, 1.0 / float(grid_subdivisions), default_target_index, 0, 0.0)
	parent_array.append(b)
	_select_bend(b, parent_array, parent_note)
	pattern_changed.emit()
	queue_redraw()
	return b

func _select_bend(bend: PatternBend, parent_array: Array, note: PatternNote) -> void:
	# Exclusive with note selection — picking a bend clears notes.
	_selected.clear()
	_selected_bend = bend
	_selected_bend_parent_array = parent_array
	_selected_bend_note = note
	selection_changed.emit(_selected)
	bend_selection_changed.emit(bend, note)
	queue_redraw()

func _clear_bend_selection() -> void:
	_selected_bend = null
	_selected_bend_parent_array = []
	_selected_bend_note = null
	bend_selection_changed.emit(null, null)

func _start_bend_tip_drag(start_beat: float) -> void:
	_drag_state = DragState.BEND_TIP
	_drag_bend = _selected_bend
	_drag_bend_parent_array = _selected_bend_parent_array
	_drag_bend_note = _selected_bend_note
	_drag_bend_start_beat = start_beat

## Tip drag: cursor X → bend.glide_beats (snap to grid), cursor Y → bend.index.
## Octave + accidental are NOT touched — those stay footer-only fine-grain
## edits. glide_beats is clamped non-negative so the tip can't precede the
## bend's start (offsets are edited in the footer or by dragging body —
## not implemented in this pass).
func _update_bend_tip_drag(pos: Vector2) -> void:
	if _drag_bend == null:
		return
	var snapped_beat: float = _snap_beat(_x_to_beat(pos.x))
	var new_glide: float = maxf(0.0, snapped_beat - _drag_bend_start_beat)
	_drag_bend.glide_beats = new_glide
	_drag_bend.index = clampi(_y_to_row(pos.y), min_row, max_row)
	pattern_changed.emit()

func _delete_selected() -> void:
	if _selected.is_empty():
		return
	for n in _selected:
		pattern.notes.erase(n)
	_selected.clear()
	selection_changed.emit(_selected)
	pattern_changed.emit()
	queue_redraw()

# ---------------------------------------------------------------------------
# Selection + clipboard
# ---------------------------------------------------------------------------

func _toggle_selection(note: PatternNote) -> void:
	if _selected.has(note):
		_selected.erase(note)
	else:
		_selected.append(note)
	selection_changed.emit(_selected)
	queue_redraw()

func _select_all() -> void:
	if pattern == null:
		return
	_selected = pattern.notes.duplicate()
	selection_changed.emit(_selected)
	queue_redraw()

func _copy_selected() -> void:
	if _selected.is_empty():
		return
	_clipboard.clear()
	for n in _selected:
		_clipboard.append(_clone_note(n))

func _paste_at_mouse() -> void:
	if _clipboard.is_empty() or pattern == null:
		return
	# Anchor: leftmost copied note aligns to snapped mouse beat (or beat 0
	# if mouse is in the gutter).
	var anchor_beat: float
	if _last_mouse_pos.x >= GUTTER_WIDTH:
		anchor_beat = _snap_beat(_x_to_beat(_last_mouse_pos.x))
	else:
		anchor_beat = 0.0
	var min_beat: float = _clipboard[0].beat
	for n in _clipboard:
		if n.beat < min_beat:
			min_beat = n.beat
	var new_notes: Array = []
	for n in _clipboard:
		var copy: PatternNote = _clone_note(n)
		copy.beat = anchor_beat + (n.beat - min_beat)
		pattern.notes.append(copy)
		new_notes.append(copy)
	_selected = new_notes
	selection_changed.emit(_selected)
	pattern_changed.emit()
	queue_redraw()

func _duplicate_selected() -> void:
	if _selected.is_empty():
		return
	var new_notes: Array = []
	for n in _selected:
		var copy: PatternNote = _clone_note(n)
		# Nudge the duplicate by one snap step so it's not stacked perfectly.
		copy.beat = n.beat + 1.0 / float(grid_subdivisions)
		pattern.notes.append(copy)
		new_notes.append(copy)
	_selected = new_notes
	selection_changed.emit(_selected)
	pattern_changed.emit()
	queue_redraw()

func _clone_note(n: PatternNote) -> PatternNote:
	var copy: PatternNote = PatternNote.create(n.beat, n.duration, n.index, n.octave, n.accidental, n.velocity)
	for b in n.bends:
		copy.bends.append(_clone_bend(b))
	return copy

func _clone_bend(b: PatternBend) -> PatternBend:
	var copy: PatternBend = PatternBend.create(b.offset_beats, b.glide_beats, b.index, b.octave, b.accidental)
	for child in b.bends:
		copy.bends.append(_clone_bend(child))
	return copy

func _start_seek(pos: Vector2) -> void:
	_drag_state = DragState.SEEKING
	_update_seek(pos)

func _update_seek(pos: Vector2) -> void:
	if director == null or pattern == null or pattern.length_beats <= 0.0:
		return
	var target_cursor: float = clampf(_x_to_beat(pos.x), 0.0, pattern.length_beats - 0.001)
	var cur_total: float = director.get_total_beats()
	var loop_index: float = floorf(cur_total / pattern.length_beats)
	var new_total: float = loop_index * pattern.length_beats + target_cursor
	director.seek(new_total)
	queue_redraw()

func _start_marquee(pos: Vector2, add_to_selection: bool) -> void:
	_drag_state = DragState.MARQUEE
	_marquee_anchor = pos
	_last_mouse_pos = pos
	_marquee_add = add_to_selection
	if not add_to_selection:
		_selected.clear()
		selection_changed.emit(_selected)
	queue_redraw()

func _commit_marquee() -> void:
	var rect: Rect2 = Rect2(_marquee_anchor, _last_mouse_pos - _marquee_anchor).abs()
	# Clip left edge to the grid area so marquee over the gutter is ignored.
	if rect.position.x < GUTTER_WIDTH:
		var dx: float = GUTTER_WIDTH - rect.position.x
		rect.position.x = GUTTER_WIDTH
		rect.size.x = maxf(0.0, rect.size.x - dx)
	var picked: Array = []
	if pattern != null:
		for n in pattern.notes:
			if _note_rect(n).intersects(rect):
				picked.append(n)
	if _marquee_add:
		for n in picked:
			if not _selected.has(n):
				_selected.append(n)
	else:
		_selected = picked
	selection_changed.emit(_selected)
