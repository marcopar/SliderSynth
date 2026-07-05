extends Node

# Standalone playground for the synth + MIDI player.
#
# Keyboard layout (FL Studio / typing-keyboard style — two rows of piano keys):
#   White: A S D F G H J K L ;
#   Black:  W E   T Y U   O P
# Z / X shift octave down/up. 1..5 select preset patches. Space toggles MIDI
# playback (if midi_path is set). Esc stops MIDI.
#
# The active patch is exported so you can edit harmonics, ADSR, lowpass,
# detune, and vibrato live in the inspector — call rebuild_patch() (or just
# re-press a preset key) after changing harmonics so the wavetable refreshes.

@export var patch: SynthPatch
@export_range(0, 8) var octave: int = 4
@export_range(0.0, 1.0) var velocity: float = 0.85
@export_file("*.mid") var midi_path: String = ""
@export var loop_midi: bool = true

@onready var synth: SynthEngine = $SynthEngine
@onready var midi_player: MidiPlayer = $MidiPlayer
@onready var editor: PanelContainer = $EditorLayer/EditorScroll/PatchEditor

var _director: MusicDirector

const KEY_TO_SEMITONE := {
	KEY_A:  0,   # C
	KEY_W:  1,   # C#
	KEY_S:  2,   # D
	KEY_E:  3,   # D#
	KEY_D:  4,   # E
	KEY_F:  5,   # F
	KEY_T:  6,   # F#
	KEY_G:  7,   # G
	KEY_Y:  8,   # G#
	KEY_H:  9,   # A
	KEY_U:  10,  # A#
	KEY_J:  11,  # B
	KEY_K:  12,  # C+1
	KEY_O:  13,  # C#+1
	KEY_L:  14,  # D+1
	KEY_P:  15,  # D#+1
	KEY_SEMICOLON: 16,  # E+1
}

var _held: Dictionary = {}

func _ready() -> void:
	if patch == null:
		patch = SynthPatch.make_organ()

	midi_player.synth = synth
	midi_player.loop = loop_midi
	if midi_path != "":
		midi_player.load_midi(midi_path)

	editor.synth = synth
	editor.patch_changed.connect(_on_editor_patch_changed)
	editor.set_patch(patch)

	_setup_music_demo()

	print("[MusicTest] Ready. Octave=%d. Keys 1-8 presets, Z/X octave, F1 editor, F2 music demo." % octave)

func _on_editor_patch_changed(p: SynthPatch) -> void:
	patch = p

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		_handle_key(event)

func _handle_key(event: InputEventKey) -> void:
	if event.echo:
		return
	var key := event.keycode

	if KEY_TO_SEMITONE.has(key):
		var semis: int = KEY_TO_SEMITONE[key]
		var note: int = 12 * (octave + 1) + semis
		if event.pressed:
			if not _held.has(key):
				synth.note_on(0, note, velocity)
				_held[key] = note
		else:
			if _held.has(key):
				synth.note_off(0, _held[key])
				_held.erase(key)
		return

	if not event.pressed:
		return

	match key:
		KEY_Z:
			octave = max(0, octave - 1)
			print("[MusicTest] Octave: %d" % octave)
		KEY_X:
			octave = min(8, octave + 1)
			print("[MusicTest] Octave: %d" % octave)
		KEY_1:
			editor.set_patch(SynthPatch.make_organ())
		KEY_2:
			editor.set_patch(SynthPatch.make_clarinet())
		KEY_3:
			editor.set_patch(SynthPatch.make_bell())
		KEY_4:
			editor.set_patch(SynthPatch.make_pad())
		KEY_5:
			editor.set_patch(SynthPatch.make_bass())
		KEY_6:
			editor.set_patch(SynthPatch.make_kick())
		KEY_7:
			editor.set_patch(SynthPatch.make_snare())
		KEY_8:
			editor.set_patch(SynthPatch.make_hihat())
		KEY_F1:
			var scroll := editor.get_parent()
			scroll.visible = not scroll.visible
		KEY_F2:
			_toggle_music_demo()
		KEY_SPACE:
			if midi_player.midi == null:
				print("[MusicTest] No MIDI loaded (set midi_path).")
			elif midi_player.is_playing():
				midi_player.stop()
				print("[MusicTest] MIDI stopped.")
			else:
				midi_player.play()
				print("[MusicTest] MIDI playing.")
		KEY_ESCAPE:
			midi_player.stop()
			if _director:
				_director.stop()
			synth.all_notes_off()
			_held.clear()
			get_viewport().gui_release_focus()

# ---------------------------------------------------------------------------
# Dynamic music demo — F2 to toggle
# ---------------------------------------------------------------------------

func _setup_music_demo() -> void:
	# Director (must be added before tracks for processing order).
	_director = MusicDirector.new()
	_director.name = "MusicDirector"
	_director.swing_amount = 0.15
	add_child(_director)

	# Progression: I - V - vi - IV in C major
	var music := MusicData.new()
	music.bpm = 110.0
	music.blocks = [
		MusicBlock.create(MusicData.C, MusicData.CHORD_MAJ, MusicData.C, MusicData.MAJOR, 4),
		MusicBlock.create(MusicData.G, MusicData.CHORD_MAJ, MusicData.C, MusicData.MAJOR, 4),
		MusicBlock.create(MusicData.A, MusicData.CHORD_MIN, MusicData.C, MusicData.MAJOR, 4),
		MusicBlock.create(MusicData.F, MusicData.CHORD_MAJ, MusicData.C, MusicData.MAJOR, 4),
	]
	_director.data = music

	# --- Chord arpeggio (ch 1) ------------------------------------------
	var arp_pat := MusicPattern.new()
	arp_pat.length_beats = 2.0
	arp_pat.add(0.0, 0.45, 0).add(0.5, 0.45, 1).add(1.0, 0.45, 2).add(1.5, 0.45, 1)
	_add_track("ChordArp", MusicTrack.TrackType.CHORD, 1, SynthPatch.make_organ(), arp_pat, 4)

	# --- Bass (ch 2) — root notes, low octave ---------------------------
	var bass_pat := MusicPattern.new()
	bass_pat.length_beats = 4.0
	bass_pat.add(0.0, 0.9, 0).add(2.0, 0.9, 0)
	_add_track("Bass", MusicTrack.TrackType.CHORD, 2, SynthPatch.make_bass(), bass_pat, 2)

	# --- Melody (ch 3) — scale degrees ----------------------------------
	var mel_pat := MusicPattern.new()
	mel_pat.length_beats = 8.0
	mel_pat.add(0.0, 0.5, 4, 0, 0, 0.7)
	mel_pat.add(0.5, 0.5, 3, 0, 0, 0.6)
	mel_pat.add(1.0, 1.0, 2, 0, 0, 0.7)
	mel_pat.add(2.0, 0.5, 0, 0, 0, 0.65)
	mel_pat.add(2.5, 0.5, 1, 0, 0, 0.6)
	mel_pat.add(3.0, 1.0, 2, 0, 0, 0.7)
	mel_pat.add(4.0, 0.5, 4, 0, 0, 0.7)
	mel_pat.add(4.5, 0.75, 5, 0, 0, 0.65)
	mel_pat.add(5.5, 0.5, 4, 0, 0, 0.6)
	mel_pat.add(6.0, 2.0, 2, 0, 0, 0.7)
	_add_track("Melody", MusicTrack.TrackType.MELODY, 3, SynthPatch.make_clarinet(), mel_pat, 5)

	# --- Kick (ch 9) ----------------------------------------------------
	var kick_pat := MusicPattern.new()
	kick_pat.length_beats = 2.0
	kick_pat.add(0.0, 0.1, 36, 0, 0, 0.9)
	kick_pat.add(1.0, 0.1, 36, 0, 0, 0.85)
	_add_track("Kick", MusicTrack.TrackType.DRUM, 9, SynthPatch.make_kick(), kick_pat, 4)

	# --- Snare (ch 10) — backbeats --------------------------------------
	var snare_pat := MusicPattern.new()
	snare_pat.length_beats = 2.0
	snare_pat.add(1.0, 0.1, 38, 0, 0, 0.75)
	_add_track("Snare", MusicTrack.TrackType.DRUM, 10, SynthPatch.make_snare(), snare_pat, 4)

	# --- Hi-hat (ch 11) — 8th notes ------------------------------------
	var hh_pat := MusicPattern.new()
	hh_pat.length_beats = 1.0
	hh_pat.add(0.0, 0.05, 42, 0, 0, 0.5)
	hh_pat.add(0.5, 0.05, 42, 0, 0, 0.35)
	_add_track("HiHat", MusicTrack.TrackType.DRUM, 11, SynthPatch.make_hihat(), hh_pat, 4)

func _add_track(p_name: String, type: MusicTrack.TrackType, channel: int, p_patch: SynthPatch, pattern: MusicPattern, oct: int) -> void:
	var t := MusicTrack.new()
	t.name = p_name
	t.track_type = type
	t.synth_channel = channel
	t.patch = p_patch
	t.pattern = pattern
	t.base_octave = oct
	t.director = _director
	t.synth = synth
	add_child(t)

func _toggle_music_demo() -> void:
	if _director.playing:
		_director.stop()
		synth.all_notes_off()
		print("[MusicTest] Music demo stopped.")
	else:
		_director.play()
		print("[MusicTest] Music demo playing (I-V-vi-IV in C, 110 BPM, swing %.0f%%)." % (_director.swing_amount * 100))
