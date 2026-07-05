class_name MusicDirector
extends Node

# Beat clock and block progression manager. Drives MusicTrack nodes by
# advancing a monotonic beat counter and cycling through MusicBlocks in the
# active MusicData. Exposes helpers so any game code (SFX, etc.) can query
# the current harmonic context.
#
# IMPORTANT: This node must appear BEFORE any MusicTrack siblings in the
# scene tree so that _process updates beat state before tracks read it.

signal beat_tick(beat_number: int)
signal block_changed(block: MusicBlock, index: int)
signal seeked

## When a transition takes effect — used by [method swap_data], by
## MusicDataPlayer.swap_mode, and by MusicTrack.swap_mode.
##   IMMEDIATE   — apply right now
##   NEXT_BEAT   — defer to the next integer beat boundary
##   NEXT_BLOCK  — defer to the next block boundary in the progression
enum SwapMode { IMMEDIATE, NEXT_BEAT, NEXT_BLOCK }

## The progression to play. Holds BPM and the list of MusicBlocks that
## cycle in order. May be null until [method swap_data] or [method play]
## is called with data assigned.
@export var data: MusicData

## Shuffle/swing feel. 0 = straight 8ths. Higher values delay every
## offbeat 8th note (0.5, 1.5, 2.5, ...) — 0.33 ≈ triplet swing.
@export_range(0.0, 1.0) var swing_amount: float = 0.0

## Start playback when the node enters the tree (deferred one frame so
## MusicTrack siblings can connect to signals first).
@export var autoplay: bool = false

var playing: bool = false
var current_block_index: int = 0

var _beat_in_block: float = 0.0
var _total_beats: float = 0.0
var _last_beat_int: int = -1
var _pending_data: MusicData = null
var _pending_mode: int = -1

# ---------------------------------------------------------------------------
# Playback control
# ---------------------------------------------------------------------------

func _ready() -> void:
	if autoplay and data != null and not data.blocks.is_empty():
		call_deferred("play")

func play() -> void:
	if data == null or data.blocks.is_empty():
		push_warning("[MusicDirector] No data or empty blocks.")
		return
	_beat_in_block = 0.0
	_total_beats = 0.0
	_last_beat_int = -1
	current_block_index = 0
	playing = true
	block_changed.emit(data.blocks[0], 0)

func stop() -> void:
	playing = false

func swap_data(new_data: MusicData, mode: SwapMode = SwapMode.IMMEDIATE) -> void:
	if mode == SwapMode.IMMEDIATE:
		_apply_swap(new_data)
	else:
		_pending_data = new_data
		_pending_mode = mode

## Jump the beat clock to [param new_total_beats]. Re-derives the block
## index + beat-in-block from the progression. Emits [signal seeked] so
## tracks can release their sustaining notes, then [signal block_changed]
## if the block actually changed.
func seek(new_total_beats: float) -> void:
	_total_beats = new_total_beats
	_last_beat_int = int(floorf(new_total_beats)) - 1
	if data == null or data.blocks.is_empty():
		seeked.emit()
		return
	var total_len: float = 0.0
	for block in data.blocks:
		total_len += float(block.duration_beats)
	if total_len <= 0.0:
		seeked.emit()
		return
	var prog_beat: float = fposmod(new_total_beats, total_len)
	var acc: float = 0.0
	var new_index: int = 0
	var new_in_block: float = prog_beat
	for i in data.blocks.size():
		var blen: float = float(data.blocks[i].duration_beats)
		if prog_beat < acc + blen:
			new_index = i
			new_in_block = prog_beat - acc
			break
		acc += blen
	_beat_in_block = new_in_block
	var block_changed_flag: bool = new_index != current_block_index
	current_block_index = new_index
	seeked.emit()
	if block_changed_flag:
		block_changed.emit(data.blocks[current_block_index], current_block_index)

# ---------------------------------------------------------------------------
# Query API — usable by SFX, game code, anything that needs current harmony
# ---------------------------------------------------------------------------

func get_current_block() -> MusicBlock:
	if data == null or data.blocks.is_empty():
		return null
	return data.blocks[current_block_index]

func get_beat_in_block() -> float:
	return _beat_in_block

func get_total_beats() -> float:
	return _total_beats

func get_chord_tone(index: int, octave: int) -> int:
	var block := get_current_block()
	if block == null:
		return 60
	var intervals := block.chord_intervals
	var size: int = intervals.size()
	if size == 0:
		return 60
	var idx: int = posmod(index, size)
	var extra_oct: int = int(floorf(float(index) / float(size)))
	return 12 * (octave + 1 + extra_oct) + block.chord_root + intervals[idx]

func get_scale_note(degree: int, octave: int, accidental: float = 0.0) -> float:
	var block := get_current_block()
	if block == null:
		return 60.0
	var intervals := block.scale_intervals
	var size: int = intervals.size()
	if size == 0:
		return 60.0
	var idx: int = posmod(degree, size)
	var extra_oct: int = int(floorf(float(degree) / float(size)))
	return float(12 * (octave + 1 + extra_oct) + block.scale_root + intervals[idx]) + accidental

## Apply swing to a beat position. Offbeat 8th notes (0.5, 1.5, 2.5, ...)
## are shifted forward by up to half an 8th note's duration.
func get_swung_beat(beat: float) -> float:
	if swing_amount <= 0.0:
		return beat
	var eighth: float = beat * 2.0
	var eighth_int: int = int(floorf(eighth))
	if eighth_int % 2 == 1:
		return beat + swing_amount * 0.25
	return beat

# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not playing or data == null or data.blocks.is_empty():
		return
	var beats_per_sec: float = data.bpm / 60.0
	var delta_beats: float = delta * beats_per_sec
	_beat_in_block += delta_beats
	_total_beats += delta_beats

	# Beat tick
	var current_beat_int: int = int(floorf(_total_beats))
	if current_beat_int > _last_beat_int:
		_last_beat_int = current_beat_int
		beat_tick.emit(current_beat_int)
		if _pending_data != null and _pending_mode == SwapMode.NEXT_BEAT:
			_apply_swap(_pending_data)
			return

	# Block boundary
	var block: MusicBlock = data.blocks[current_block_index]
	var dur: float = float(block.duration_beats)
	if _beat_in_block >= dur:
		_beat_in_block -= dur
		current_block_index = (current_block_index + 1) % data.blocks.size()
		var new_block: MusicBlock = data.blocks[current_block_index]
		block_changed.emit(new_block, current_block_index)
		if _pending_data != null and _pending_mode == SwapMode.NEXT_BLOCK:
			_apply_swap(_pending_data)

func _apply_swap(new_data: MusicData) -> void:
	data = new_data
	current_block_index = 0
	_beat_in_block = 0.0
	_pending_data = null
	_pending_mode = -1
	if data != null and not data.blocks.is_empty():
		block_changed.emit(data.blocks[0], 0)
