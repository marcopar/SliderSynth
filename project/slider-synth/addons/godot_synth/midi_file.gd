class_name MidiFile
extends RefCounted

# Standard MIDI File parser. Supports format 0 and format 1, integer-tick
# division (SMPTE division is rejected), running status, meta tempo events,
# and the channel events the synth actually uses (note on/off, pitch bend,
# CC, program change). All other meta and sysex events are skipped past
# correctly so the parse stays in sync with the byte stream.
#
# Output is a single time-sorted Array[Event] of channel events with
# absolute times in seconds, with tempo changes baked in during parse.

# Channel event status nibbles
const NOTE_OFF := 0x80
const NOTE_ON := 0x90
const POLY_AFTERTOUCH := 0xA0
const CONTROL_CHANGE := 0xB0
const PROGRAM_CHANGE := 0xC0
const CHANNEL_AFTERTOUCH := 0xD0
const PITCH_BEND := 0xE0

const META := 0xFF
const SYSEX_F0 := 0xF0
const SYSEX_F7 := 0xF7

const META_TEMPO := 0x51
const META_END_OF_TRACK := 0x2F

class Event:
	var time: float = 0.0   # absolute seconds
	var type: int = 0       # status nibble (NOTE_ON, ...) or META
	var channel: int = 0    # channel for channel events; meta_type for META
	var data1: int = 0
	var data2: int = 0

var format: int = 0
var ticks_per_quarter: int = 480
var events: Array[Event] = []
var duration: float = 0.0

func load_from_path(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("MidiFile: cannot open " + path)
		return false
	var bytes := f.get_buffer(f.get_length())
	f.close()
	return parse(bytes)

func parse(bytes: PackedByteArray) -> bool:
	events.clear()
	if bytes.size() < 14:
		push_error("MidiFile: file too small")
		return false
	if bytes[0] != 0x4D or bytes[1] != 0x54 or bytes[2] != 0x68 or bytes[3] != 0x64:
		push_error("MidiFile: missing MThd header")
		return false

	var pos := 4
	var header_len := _read_u32(bytes, pos); pos += 4
	format = _read_u16(bytes, pos); pos += 2
	var ntrks := _read_u16(bytes, pos); pos += 2
	var division := _read_u16(bytes, pos); pos += 2
	pos = 8 + header_len

	if division & 0x8000:
		push_error("MidiFile: SMPTE division not supported")
		return false
	ticks_per_quarter = division
	if ticks_per_quarter <= 0:
		ticks_per_quarter = 480

	# Each entry: [tick: int, ev: Event]
	var merged: Array = []
	for t in ntrks:
		if pos + 8 > bytes.size():
			break
		if bytes[pos] != 0x4D or bytes[pos + 1] != 0x54 or bytes[pos + 2] != 0x72 or bytes[pos + 3] != 0x6B:
			push_error("MidiFile: missing MTrk header at track %d" % t)
			return false
		pos += 4
		var tlen := _read_u32(bytes, pos); pos += 4
		var track_end := pos + tlen
		_parse_track(bytes, pos, track_end, merged)
		pos = track_end

	# Stable-ish sort by tick. Ties between tracks are not perceptually
	# significant for note/tempo events.
	merged.sort_custom(func(a, b): return a[0] < b[0])

	# Walk merged list, applying tempo to compute absolute seconds.
	var us_per_quarter: int = 500000  # default 120 BPM
	var current_tick: int = 0
	var current_time: float = 0.0
	for entry in merged:
		var tick: int = entry[0]
		var ev: Event = entry[1]
		var delta_ticks := tick - current_tick
		if delta_ticks > 0:
			var sec_per_tick: float = (float(us_per_quarter) / 1_000_000.0) / float(ticks_per_quarter)
			current_time += float(delta_ticks) * sec_per_tick
			current_tick = tick
		ev.time = current_time
		if ev.type == META:
			if ev.channel == META_TEMPO:
				us_per_quarter = ev.data1
			# Drop all meta from the playable stream.
			continue
		events.append(ev)

	duration = current_time
	return true

func _parse_track(bytes: PackedByteArray, start: int, end: int, out: Array) -> void:
	var pos := start
	var tick: int = 0
	var running_status: int = 0
	while pos < end:
		var dr := _read_vlq(bytes, pos)
		var delta: int = dr[0]
		pos = dr[1]
		tick += delta
		if pos >= end:
			break

		var status: int = bytes[pos]
		if status < 0x80:
			# Running status: reuse last channel-event status, byte is data.
			status = running_status
		else:
			pos += 1
			if status < 0xF0:
				running_status = status

		if status == META:
			if pos >= end:
				break
			var meta_type: int = bytes[pos]; pos += 1
			var lr := _read_vlq(bytes, pos)
			var mlen: int = lr[0]
			pos = lr[1]
			var ev := Event.new()
			ev.type = META
			ev.channel = meta_type
			if meta_type == META_TEMPO and mlen == 3 and pos + 3 <= end:
				ev.data1 = (int(bytes[pos]) << 16) | (int(bytes[pos + 1]) << 8) | int(bytes[pos + 2])
			out.append([tick, ev])
			pos += mlen
		elif status == SYSEX_F0 or status == SYSEX_F7:
			var lr := _read_vlq(bytes, pos)
			var slen: int = lr[0]
			pos = lr[1]
			pos += slen
		else:
			var hi: int = status & 0xF0
			var ch: int = status & 0x0F
			var ev := Event.new()
			ev.type = hi
			ev.channel = ch
			if hi == PROGRAM_CHANGE or hi == CHANNEL_AFTERTOUCH:
				if pos >= end:
					break
				ev.data1 = bytes[pos]; pos += 1
			else:
				if pos + 1 >= end:
					break
				ev.data1 = bytes[pos]; pos += 1
				ev.data2 = bytes[pos]; pos += 1
			out.append([tick, ev])

func _read_u16(bytes: PackedByteArray, pos: int) -> int:
	return (int(bytes[pos]) << 8) | int(bytes[pos + 1])

func _read_u32(bytes: PackedByteArray, pos: int) -> int:
	return (int(bytes[pos]) << 24) | (int(bytes[pos + 1]) << 16) | (int(bytes[pos + 2]) << 8) | int(bytes[pos + 3])

func _read_vlq(bytes: PackedByteArray, pos: int) -> Array:
	var value: int = 0
	while pos < bytes.size():
		var b: int = bytes[pos]
		pos += 1
		value = (value << 7) | (b & 0x7F)
		if (b & 0x80) == 0:
			break
	return [value, pos]
