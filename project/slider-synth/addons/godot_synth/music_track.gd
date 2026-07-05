class_name MusicTrack
extends Node

# Independent instrument track. Self-wires to the global SynthEngine
# (/root/Synth) and MusicDirector (/root/Music) on entering the tree;
# owns its own activation lifecycle via activate() / deactivate().
#
# A track has up to two things it contributes to its synth channel:
#   - patch  (timbre — applies to the channel on activate / swap_patch)
#   - pattern (melody — plays note events through the channel)
# Either or both may be null. A patch-only track swaps the channel's
# timbre without playing anything; a pattern-only track uses whatever
# patch is already on the channel. Both together = a traditional track.
#
# Track types (how each PatternNote's `index` field is interpreted):
#   CHORD  — chord tone index (0 = root, 1 = third, ...)
#   MELODY — 0-based scale degree (accidental adds ± semitones)
#   DRUM   — absolute MIDI note number (no transposition)
#
# SFX overrides:
#   bpm_override > 0         — use own local clock at that BPM (ignore director)
#   key_override != null     — resolve pitches against this block (ignore director)

enum TrackType { CHORD, MELODY, DRUM }

@export var track_type: TrackType = TrackType.CHORD

## The looping pattern this track plays. May be null (patch-only track).
@export var pattern: MusicPattern

## Synth patch (timbre) applied to the target channel on [method activate]
## and [method swap_patch]. May be null — track then uses whatever patch
## already occupies the channel.
@export var patch: SynthPatch

## SynthEngine channel (0..15) this track targets. Multiple tracks may
## share a channel — they cooperate on patch/pattern but the last one to
## activate wins the effect chain.
@export_range(0, 15) var synth_channel: int = 0

## Octave offset for CHORD/MELODY tracks. Ignored for DRUM.
@export var base_octave: int = 4

@export_group("Playback")

## Activate the track automatically when it enters the tree. Disable for
## tracks you want to trigger via [method activate] in code.
@export var autoplay: bool = true

## When activations and pattern swaps take effect. See
## [enum MusicDirector.SwapMode]. Used by [method activate] and (by
## default) [method swap_pattern].
@export var swap_mode: MusicDirector.SwapMode = MusicDirector.SwapMode.NEXT_BEAT

## Where in the pattern to start playing.
## [br]• [code]false[/code] (default) — start from pattern beat 0
## [br]• [code]true[/code]  — align pattern beat 0 to director beat 0
##   (mid-song activation picks up at the director's current cursor
##   position; a track always plays "in sync" with director's clock)
@export var sync_to_director: bool = false

## Stereo pan applied to every note this track fires (-1 = full left,
## 0 = center, +1 = full right).
@export_range(-1.0, 1.0) var pan: float = 0.0

## Multiplier applied to every note's velocity when triggered. Useful
## for transient SFX attenuation (e.g. distance-based volume) without
## rewriting the pattern. Caller sets before play_once / activate.
var velocity_scale: float = 1.0

@export_group("Bus Routing")

## Send target for this channel's auto-bus (see [SynthEngine.ensure_channel_bus]).
## Default [&"Master"] sends direct to master. Use a shared bus to group
## multiple channels through a submix (e.g. compressor on "Drums").
@export var output_bus: StringName = &"Master"

## Effects installed on this channel's auto-bus, in order. Installed by
## reference — editing an AudioEffect resource at runtime affects live
## audio. Last activated track on a channel owns the effect chain.
@export var effects: Array[AudioEffect] = []

@export_group("Overrides (SFX)")

## When > 0, track uses its own local clock at this BPM instead of the
## director's beat counter. The track plays independent of director
## play/stop and of [method MusicDirector.seek]. Safe to change at
## runtime — the setter rescales the local clock so the pattern cursor
## stays continuous (no note stampede on tempo changes).
@export var bpm_override: float = 0.0:
	set(value):
		var prev_effective: float = _effective_beats()
		bpm_override = maxf(0.0, value)
		if bpm_override > 0.0 and prev_effective > 0.0:
			_local_time = prev_effective * 60.0 / bpm_override
		elif bpm_override <= 0.0:
			_local_time = 0.0

## When set, pitches resolve against this block instead of the director's
## current block. Track is unaffected by [signal MusicDirector.block_changed].
@export var key_override: MusicBlock

# --- Runtime refs (auto-wired in _ready) ------------------------------------

var director: MusicDirector
var synth: SynthEngine

# --- Internal state ---------------------------------------------------------

var _active: bool = false
# True once we've actually started rendering frames. Distinct from _active:
# a non-override track stays inactive (but _active=true) while the director
# is stopped; _was_playing flips when playback actually begins.
var _was_playing: bool = false
# Effective-beat at which playback should start. Determined by swap_mode
# (IMMEDIATE = current effective, NEXT_BEAT = ceil, NEXT_BLOCK = next block
# boundary). While effective < _start_at_beat, the track is "pending" and
# doesn't trigger notes (note-offs still process).
var _start_at_beat: float = 0.0
# Offset in "effective beats" subtracted from current effective beat to
# yield the pattern's cursor. With sync_to_director=false this equals
# _start_at_beat (cursor begins at 0 when playback starts). With
# sync_to_director=true this equals 0.0 (cursor follows director's
# absolute beats — the pattern stays aligned to director beat 0).
var _activated_at_beat: float = 0.0
# Wall-clock seconds since the current activation, only used when
# bpm_override > 0.
var _local_time: float = 0.0
var _prev_cursor: float = -0.001
# Each entry: {"midi": int, "off_time": float} (off_time in effective beats)
var _active_notes: Array = []
# Each entry: {"midi": int, "fire_beat": float, "target_freq": float,
# "glide_beats": float}. Bends pulled from triggered notes' bend chains;
# fire when effective >= fire_beat, then dispatched to SynthEngine.bend_to.
# Cancelled on note-off, _release_all, and block changes.
var _pending_bends: Array = []
# Counter for play_once() to invalidate stale deferred deactivates when
# the same track is re-triggered rapidly.
var _play_once_token: int = 0

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	if director == null:
		director = get_node_or_null("/root/Music") as MusicDirector
	if synth == null:
		synth = get_node_or_null("/root/Synth") as SynthEngine
	_wire_signals()
	if autoplay:
		activate()

## Explicit ref assignment for projects that don't use the default
## `/root/Music` + `/root/Synth` autoload names.
func bind(p_director: MusicDirector, p_synth: SynthEngine) -> void:
	director = p_director
	synth = p_synth
	_wire_signals()

func _wire_signals() -> void:
	if director == null:
		return
	if not director.block_changed.is_connected(_on_block_changed):
		director.block_changed.connect(_on_block_changed)
	if not director.seeked.is_connected(_on_seeked):
		director.seeked.connect(_on_seeked)

## Apply this track's patch (if any), install its bus + effects, and
## begin pattern playback (if any). Activation timing follows
## [member swap_mode]; cursor starting position follows
## [member sync_to_director].
func activate() -> void:
	if synth == null:
		return
	if patch != null:
		synth.set_patch(synth_channel, patch)
	_configure_bus()
	_active = true
	# Force _process to re-initialize cursor + activation offset on the
	# next frame where playback can actually run.
	_was_playing = false

## Stop pattern playback, release sustaining notes. Leaves the patch in
## place on the channel (another track can take over without silence).
func deactivate() -> void:
	if not _active:
		return
	_release_all()
	_active = false
	_was_playing = false

## Whether this track is currently activated (playing or pending start).
func is_active() -> bool:
	return _active

## SFX-style one-shot: activate, await one full pattern length, then
## deactivate. Idempotent under rapid re-trigger — only the most recent
## call's deferred deactivate fires (older awaits no-op via token check).
func play_once() -> void:
	activate()
	if pattern == null or pattern.length_beats <= 0.0:
		return
	_play_once_token += 1
	var token: int = _play_once_token
	var bpm: float = bpm_override
	if bpm <= 0.0:
		if director != null and director.data != null:
			bpm = director.data.bpm
	if bpm <= 0.0:
		bpm = 120.0
	var seconds: float = pattern.length_beats * 60.0 / bpm
	await get_tree().create_timer(seconds).timeout
	if token == _play_once_token:
		deactivate()

## Swap the patch on this track's channel. No effect on pattern state.
func swap_patch(new_patch: SynthPatch) -> void:
	patch = new_patch
	if synth != null and new_patch != null:
		synth.set_patch(synth_channel, new_patch)

## Swap the pattern, optionally with a different transition mode.
## Default uses [member swap_mode]. Ongoing notes are released so the
## new pattern starts cleanly.
func swap_pattern(new_pattern: MusicPattern, mode: int = -1) -> void:
	var resolved_mode: int = mode if mode >= 0 else int(swap_mode)
	_release_all()
	pattern = new_pattern
	if _active and _was_playing:
		_resolve_start_state(resolved_mode)
		_sync_cursor_to_now()

## Re-apply effect chain + send target on this channel's auto-bus.
## Call after mutating [member effects] or [member output_bus] at
## runtime.
func refresh_bus() -> void:
	_configure_bus()

func _configure_bus() -> void:
	if synth == null:
		return
	synth.ensure_channel_bus(synth_channel, effects, output_bus)

# ---------------------------------------------------------------------------
# Per-frame render
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if synth == null or director == null or not _active:
		return

	var using_override: bool = bpm_override > 0.0
	var director_playing: bool = director.playing

	# Non-override tracks pause when the global director isn't running.
	if not using_override and not director_playing:
		if _was_playing:
			_release_all()
			_was_playing = false
		return

	# First frame after (re)activation or director-resume: compute when
	# to start, where the cursor begins, and align _prev_cursor so we
	# don't stampede historical notes.
	if not _was_playing:
		_was_playing = true
		_local_time = 0.0
		_resolve_start_state(int(swap_mode))
		_sync_cursor_to_now()

	if using_override:
		_local_time += delta

	var effective: float = _effective_beats()

	# Release note-offs whose time has come.
	var i: int = _active_notes.size() - 1
	while i >= 0:
		var entry: Dictionary = _active_notes[i]
		if effective >= entry["off_time"]:
			synth.note_off(synth_channel, entry["midi"])
			_cancel_pending_bends(entry["midi"])
			_active_notes.remove_at(i)
		i -= 1

	# Fire bends whose scheduled beat has arrived.
	if not _pending_bends.is_empty():
		var bpm: float = _effective_bpm()
		var bi: int = _pending_bends.size() - 1
		while bi >= 0:
			var be: Dictionary = _pending_bends[bi]
			if effective >= float(be["fire_beat"]):
				var glide_seconds: float = 0.0
				if bpm > 0.0:
					glide_seconds = float(be["glide_beats"]) * 60.0 / bpm
				synth.bend_to(synth_channel, int(be["midi"]),
					float(be["target_freq"]), glide_seconds)
				_pending_bends.remove_at(bi)
			bi -= 1

	if pattern == null or pattern.notes.is_empty():
		return

	if effective < _start_at_beat - 0.001:
		return  # pending — waiting for the swap_mode-defined start point

	var relative: float = effective - _activated_at_beat
	var length: float = pattern.length_beats
	if length <= 0.0:
		return
	var cursor: float = fposmod(relative, length)
	var wrapped: bool = cursor < _prev_cursor - 0.001

	for note in pattern.notes:
		var note_beat: float = note.beat
		if not using_override and director != null:
			note_beat = director.get_swung_beat(note.beat)
		var swung: float = fposmod(note_beat, length)
		var should_trigger: bool = false
		if wrapped:
			should_trigger = (swung > _prev_cursor and swung <= length) or swung <= cursor
		else:
			should_trigger = swung > _prev_cursor and swung <= cursor
		if should_trigger:
			_trigger_note(note, effective)

	_prev_cursor = cursor

# ---------------------------------------------------------------------------
# Clock + context helpers
# ---------------------------------------------------------------------------

func _effective_beats() -> float:
	if bpm_override > 0.0:
		return _local_time * bpm_override / 60.0
	return director.get_total_beats() if director != null else 0.0

func _effective_block() -> MusicBlock:
	if key_override != null:
		return key_override
	if director == null:
		return null
	return director.get_current_block()

## Compute [_start_at_beat] (when playback begins) from the transition
## mode, and [_activated_at_beat] (cursor offset) from sync_to_director.
func _resolve_start_state(mode: int) -> void:
	var effective: float = _effective_beats()
	match mode:
		MusicDirector.SwapMode.IMMEDIATE:
			_start_at_beat = effective
		MusicDirector.SwapMode.NEXT_BEAT:
			_start_at_beat = ceilf(effective)
		MusicDirector.SwapMode.NEXT_BLOCK:
			_start_at_beat = _next_block_start_effective(effective)
		_:
			_start_at_beat = effective
	_activated_at_beat = 0.0 if sync_to_director else _start_at_beat

## Effective-beat at which the director's next block begins. Falls back
## to current effective beats when no director / no progression / on
## bpm_override (in which case NEXT_BLOCK degrades to IMMEDIATE).
func _next_block_start_effective(effective: float) -> float:
	if bpm_override > 0.0 or director == null:
		return effective
	var block := director.get_current_block()
	if block == null:
		return effective
	var beats_remaining: float = float(block.duration_beats) - director.get_beat_in_block()
	if beats_remaining <= 0.001:
		return effective
	return effective + beats_remaining

## Align [_prev_cursor] to the current cursor so the next _process frame
## doesn't trigger notes for the pattern region "before now".
##
## - Pending (effective < _start_at_beat): -0.001, so beat-0 fires when
##   playback actually begins.
## - Fresh start (relative ≈ 0, sync_to_director=false): -0.001, beat-0 fires.
## - Mid-pattern start (sync_to_director=true): cursor at director's
##   absolute position, so historical notes don't stampede.
func _sync_cursor_to_now() -> void:
	if pattern == null or pattern.length_beats <= 0.0:
		_prev_cursor = -0.001
		return
	var effective: float = _effective_beats()
	if effective < _start_at_beat - 0.001:
		_prev_cursor = -0.001
		return
	var relative: float = effective - _activated_at_beat
	if relative <= 0.001:
		_prev_cursor = -0.001
	else:
		_prev_cursor = fposmod(relative, pattern.length_beats)

# ---------------------------------------------------------------------------
# Note resolution
# ---------------------------------------------------------------------------

func _trigger_note(note: PatternNote, effective_beats: float) -> void:
	var midi_float: float = _resolve_midi_float(note.index, note.octave, note.accidental)
	var midi_handle: int = roundi(midi_float)
	synth.note_on(synth_channel, midi_float, clampf(note.velocity * velocity_scale, 0.0, 1.0), pan)
	_active_notes.append({"midi": midi_handle, "off_time": effective_beats + note.duration})
	if not note.bends.is_empty():
		_schedule_bends(midi_handle, effective_beats, note.bends, 0.0)

## Append every bend in [param bends] (and their nested children) to
## [_pending_bends] with absolute fire beats. [param parent_offset] is the
## accumulated offset of this bend's parent within the bend chain — child
## bends fire at parent_start_beat + parent_offset + bend.offset_beats,
## so each nested bend's offset_beats stays "relative to its own parent".
func _schedule_bends(midi_handle: int, parent_start_beat: float, bends: Array[PatternBend], parent_offset: float) -> void:
	for b in bends:
		var fire_beat: float = parent_start_beat + parent_offset + b.offset_beats
		var target_midi: float = _resolve_midi_float(b.index, b.octave, b.accidental)
		var target_freq: float = 440.0 * pow(2.0, (target_midi - 69.0) / 12.0)
		_pending_bends.append({
			"midi": midi_handle,
			"fire_beat": fire_beat,
			"target_freq": target_freq,
			"glide_beats": b.glide_beats,
		})
		if not b.bends.is_empty():
			_schedule_bends(midi_handle, parent_start_beat, b.bends, parent_offset + b.offset_beats)

func _cancel_pending_bends(midi_handle: int) -> void:
	var i: int = _pending_bends.size() - 1
	while i >= 0:
		if int(_pending_bends[i]["midi"]) == midi_handle:
			_pending_bends.remove_at(i)
		i -= 1

func _effective_bpm() -> float:
	if bpm_override > 0.0:
		return bpm_override
	if director != null and director.data != null:
		return director.data.bpm
	return 120.0

## Resolve a (index, octave, accidental) triple to a fractional MIDI number
## in the current block's harmonic context. Returns float so microtonal
## accidentals (e.g. 0.5) flow through unrounded.
func _resolve_midi_float(p_index: int, p_octave: int, p_accidental: float) -> float:
	match track_type:
		TrackType.CHORD:
			return _resolve_chord_float(p_index, p_octave, p_accidental)
		TrackType.MELODY:
			return _resolve_melody_float(p_index, p_octave, p_accidental)
		_: # DRUM — index is absolute MIDI
			return float(p_index)

func _resolve_chord_float(p_index: int, p_octave: int, p_accidental: float) -> float:
	var block := _effective_block()
	if block == null:
		return 60.0
	var intervals := block.chord_intervals
	var size: int = intervals.size()
	if size == 0:
		return 60.0
	var idx: int = posmod(p_index, size)
	var extra_oct: int = int(floorf(float(p_index) / float(size)))
	return float(12 * (base_octave + 1 + p_octave + extra_oct) + block.chord_root + intervals[idx]) + p_accidental

func _resolve_melody_float(p_index: int, p_octave: int, p_accidental: float) -> float:
	var block := _effective_block()
	if block == null:
		return 60.0
	var intervals := block.scale_intervals
	var size: int = intervals.size()
	if size == 0:
		return 60.0
	var idx: int = posmod(p_index, size)
	var extra_oct: int = int(floorf(float(p_index) / float(size)))
	return float(12 * (base_octave + 1 + p_octave + extra_oct) + block.scale_root + intervals[idx]) + p_accidental

# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

func _on_block_changed(_block: MusicBlock, _index: int) -> void:
	if track_type == TrackType.DRUM:
		return
	if key_override != null:
		return  # we don't care about the director's block
	_release_all()

func _on_seeked() -> void:
	if bpm_override > 0.0:
		return  # our clock is independent of the director
	_release_all()
	if _active and _was_playing:
		_sync_cursor_to_now()

func _release_all() -> void:
	if synth == null:
		return
	for entry in _active_notes:
		synth.note_off(synth_channel, entry["midi"])
	_active_notes.clear()
	_pending_bends.clear()
