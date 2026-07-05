class_name MidiPlayer
extends Node

# Drives a SynthEngine from a parsed MidiFile. The scheduler advances a
# wall-clock time and dispatches every event whose timestamp has passed.
# Channels 0..15 each address one slot in SynthEngine's patch table.

## Path to a Standard MIDI File (.mid). Loaded in [method _ready] if set.
@export_file("*.mid") var midi_path: String = ""

## Target SynthEngine for note events. Required — the player does nothing
## without one.
@export var synth: SynthEngine

## Begin playback automatically when the node enters the scene tree.
@export var autoplay: bool = false

## Restart the file from the beginning when it finishes, releasing any
## sustaining notes first.
@export var loop: bool = false

## Per-channel patch assignments (0..15). Array index = MIDI channel.
## Null entries leave the synth's default patch in place. For a drum kit
## on channel 10 (index 9), assign kick/snare/hihat patches on adjacent
## channels and map MIDI drum notes in your source file accordingly.
@export var channel_patches: Array[SynthPatch] = []

var midi: MidiFile
var _time: float = 0.0
var _index: int = 0
var _playing: bool = false

func _ready() -> void:
	for i in channel_patches.size():
		if channel_patches[i] != null and synth != null:
			synth.set_patch(i, channel_patches[i])
	if midi_path != "":
		load_midi(midi_path)
	if autoplay:
		play()

func load_midi(path: String) -> bool:
	var mf := MidiFile.new()
	if not mf.load_from_path(path):
		return false
	midi = mf
	_time = 0.0
	_index = 0
	return true

func set_patch(channel: int, patch: SynthPatch) -> void:
	if synth:
		synth.set_patch(channel, patch)

func play() -> void:
	if midi == null:
		return
	_time = 0.0
	_index = 0
	_playing = true

func stop() -> void:
	_playing = false
	if synth:
		synth.all_notes_off()

func is_playing() -> bool:
	return _playing

func _process(delta: float) -> void:
	if not _playing or midi == null or synth == null:
		return
	_time += delta
	var evs := midi.events
	while _index < evs.size():
		var ev: MidiFile.Event = evs[_index]
		if ev.time > _time:
			break
		_dispatch(ev)
		_index += 1
	if _index >= evs.size():
		if loop:
			synth.all_notes_off()
			_time = 0.0
			_index = 0
		else:
			_playing = false

func _dispatch(ev: MidiFile.Event) -> void:
	match ev.type:
		MidiFile.NOTE_ON:
			if ev.data2 == 0:
				synth.note_off(ev.channel, ev.data1)
			else:
				synth.note_on(ev.channel, ev.data1, float(ev.data2) / 127.0)
		MidiFile.NOTE_OFF:
			synth.note_off(ev.channel, ev.data1)
