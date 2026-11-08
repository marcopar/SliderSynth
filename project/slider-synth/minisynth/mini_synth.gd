## Wavetable voice mixer. Add to the scene tree to start audio output.
class_name MiniSynth
extends Node

const _BLOCK_SIZE := 128
const _MAX_PARTIALS := 256
const _MAX_CUSTOM_SAMPLES := 768000

## Linear master gain in [0, 1], applied after voice mixing and effects.
var volume: float = 0.8:
	set(value):
		if SynthVoice._valid_level(value, "MiniSynth.volume"):
			volume = value
## Requested generator buffer in seconds; set only while outside the scene tree.
var buffer_seconds: float = 0.03:
	set(value):
		if is_inside_tree():
			push_error("MiniSynth.buffer_seconds: set before adding the synth to the tree.")
		elif not is_finite(value) or value < 0.005 or value > 0.5:
			push_error("MiniSynth.buffer_seconds: expected 0.005 to 0.5 seconds.")
		else:
			buffer_seconds = value

var _sample_rate := AudioServer.get_mix_rate()
var _voices: Array[SynthVoice] = []
var _effects: Array[SynthEffect] = []
var _mono := PackedFloat32Array()
var _stereo := PackedVector2Array()
var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _render_failed := false


func _init() -> void:
	SynthVoice._bake_tables()
	process_priority = -100


## Creates a reusable monophonic voice owned by this synth; null on invalid waveform.
func create_voice(waveform: SynthVoice.Waveform = SynthVoice.Waveform.SINE) -> SynthVoice:
	if waveform == SynthVoice.Waveform.CUSTOM:
		push_error("MiniSynth.create_voice: CUSTOM requires create_custom_voice().")
		return null
	if waveform < SynthVoice.Waveform.SINE or waveform > SynthVoice.Waveform.REVERSE_SAWTOOTH:
		push_error("MiniSynth.create_voice: unknown waveform.")
		return null
	var voice := SynthVoice.new(_sample_rate)
	voice.waveform = waveform
	_voices.append(voice)
	return voice


## Bakes frequency/amplitude pairs once. note_on(reference_frequency_hz) plays at original speed.
func create_custom_voice(
	partials: PackedVector2Array, reference_frequency_hz: float = 440.0,
	loop_seconds: float = 2.0
) -> SynthVoice:
	if not is_finite(reference_frequency_hz) or reference_frequency_hz <= 0.0 \
			or reference_frequency_hz >= _sample_rate * 0.5:
		push_error("MiniSynth.create_custom_voice: reference frequency must be positive and below Nyquist.")
		return null
	if not is_finite((_sample_rate * 0.5) * (1.0 / reference_frequency_hz)):
		push_error("MiniSynth.create_custom_voice: reference frequency is too small for finite playback increments.")
		return null
	var table := _bake_custom(partials, _sample_rate, loop_seconds)
	if table.is_empty():
		return null
	var voice := SynthVoice.new(_sample_rate)
	voice._install_custom(table, reference_frequency_hz)
	_voices.append(voice)
	return voice


static func _bake_custom(
	partials: PackedVector2Array, sample_rate: float, loop_seconds: float
) -> PackedFloat32Array:
	if partials.is_empty() or partials.size() > _MAX_PARTIALS:
		push_error("MiniSynth.create_custom_voice: expected 1 to %d partials." % _MAX_PARTIALS)
		return PackedFloat32Array()
	if not is_finite(loop_seconds) or loop_seconds < 0.25 or loop_seconds > 4.0:
		push_error("MiniSynth.create_custom_voice: loop_seconds must be 0.25 to 4.0.")
		return PackedFloat32Array()
	var frames := roundi(sample_rate * loop_seconds)
	if frames < 1 or frames > _MAX_CUSTOM_SAMPLES:
		push_error("MiniSynth.create_custom_voice: the loop exceeds the supported sample-count bounds.")
		return PackedFloat32Array()
	var period := frames / sample_rate
	var powers: Dictionary[int, float] = {}
	for partial in partials:
		if not is_finite(partial.x) or partial.x <= 0.0 or partial.x >= sample_rate * 0.5:
			push_error("MiniSynth.create_custom_voice: partial frequencies must be positive and below Nyquist.")
			return PackedFloat32Array()
		if not is_finite(partial.y) or partial.y < 0.0:
			push_error("MiniSynth.create_custom_voice: partial amplitudes must be finite and nonnegative.")
			return PackedFloat32Array()
		var harmonic := roundi(partial.x * period)
		if harmonic == 0 or harmonic * 2 >= frames:
			push_error("MiniSynth.create_custom_voice: a partial rounds to DC/Nyquist; use a longer loop.")
			return PackedFloat32Array()
		if partial.y > 0.0:
			powers[harmonic] = powers.get(harmonic, 0.0) + partial.y * partial.y
	if powers.is_empty():
		push_error("MiniSynth.create_custom_voice: at least one nonzero amplitude is required.")
		return PackedFloat32Array()
	var harmonics := powers.keys()
	harmonics.sort()
	var random := RandomNumberGenerator.new()
	random.seed = 0x4d494e49
	var samples := PackedFloat64Array()
	samples.resize(frames)
	for harmonic: int in harmonics:
		var amplitude := sqrt(powers[harmonic])
		var phase := random.randf() * TAU
		var step := TAU * harmonic / frames
		var coefficient := 2.0 * cos(step)
		var previous := sin(phase - step)
		var current := sin(phase)
		# Oscillator recurrence avoids millions of trigonometric calls during baking.
		for i in range(frames):
			samples[i] += amplitude * current
			var next := coefficient * current - previous
			previous = current
			current = next
	var peak := 0.0
	for sample in samples:
		peak = maxf(peak, absf(sample))
	if not is_finite(peak) or peak == 0.0:
		push_error("MiniSynth.create_custom_voice: could not bake a finite, nonzero waveform.")
		return PackedFloat32Array()
	var table := PackedFloat32Array()
	table.resize(frames)
	for i in range(frames):
		table[i] = samples[i] / peak
	return table


## Unregisters a voice, cutting its release tail. Returns false for a foreign/removed handle.
func remove_voice(voice: SynthVoice) -> bool:
	var index := _voices.find(voice)
	if index == -1:
		push_error("MiniSynth.remove_voice: voice does not belong to this synth.")
		return false
	_voices.remove_at(index)
	voice._detach()
	return true


## Appends a feedback echo to the shared post-mixer chain.
func create_echo() -> SynthEcho:
	var effect := SynthEcho.new(_sample_rate)
	_effects.append(effect)
	return effect


## Appends a mono reverb to the shared post-mixer chain.
func create_reverb() -> SynthReverb:
	var effect := SynthReverb.new(_sample_rate)
	_effects.append(effect)
	return effect


## Removes and invalidates an owned effect, cutting its own tail.
func remove_effect(effect: SynthEffect) -> bool:
	var index := _effects.find(effect)
	if index == -1:
		push_error("MiniSynth.remove_effect: effect does not belong to this synth.")
		return false
	_effects.remove_at(index)
	effect._detach()
	return true


## Moves an owned effect to a zero-based chain index, preserving its history.
func move_effect(effect: SynthEffect, index: int) -> bool:
	var previous := _effects.find(effect)
	if previous == -1:
		push_error("MiniSynth.move_effect: effect does not belong to this synth.")
		return false
	if index < 0 or index >= _effects.size():
		push_error("MiniSynth.move_effect: index must identify an existing chain position.")
		return false
	if previous != index:
		_effects.remove_at(previous)
		_effects.insert(index, effect)
	return true


## Invalidates every effect and releases its buffers. Does nothing for an empty chain.
func clear_effects() -> void:
	for effect in _effects:
		effect._detach()
	_effects.clear()


func _ready() -> void:
	_render_failed = false
	if _player == null:
		_player = AudioStreamPlayer.new()
		add_child(_player)
	var stream := AudioStreamGenerator.new()
	stream.mix_rate_mode = AudioStreamGenerator.MIX_RATE_CUSTOM
	stream.mix_rate = _sample_rate
	stream.buffer_length = buffer_seconds
	_player.stream = stream
	_player.play()
	_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback
	if _playback == null:
		push_error("MiniSynth: could not start audio generator playback.")
		set_process(false)
		return
	set_process(true)
	_fill_buffer()


func _process(_delta: float) -> void:
	_fill_buffer()


func _fill_buffer() -> void:
	if _render_failed:
		return
	var remaining := _playback.get_frames_available()
	while remaining > 0:
		var frames := mini(_BLOCK_SIZE, remaining)
		var block := _render_block(frames)
		if block.is_empty():
			return
		if not _playback.push_buffer(block):
			push_error("MiniSynth: audio generator rejected an available block.")
			set_process(false)
			return
		remaining -= frames


func _render_block(frames: int) -> PackedVector2Array:
	if _render_failed:
		return PackedVector2Array()
	if _mono.size() != frames:
		_mono.resize(frames)
		_stereo.resize(frames)
	_mono.fill(0.0)
	for voice in _voices:
		if voice.is_active():
			voice._mix_into(_mono)
	for effect in _effects:
		effect._process_block(_mono)
	for i in range(frames):
		if not is_finite(_mono[i]):
			_render_failed = true
			_stop_output()
			for effect in _effects:
				effect._reset()
			_mono.fill(0.0)
			_stereo.fill(Vector2.ZERO)
			push_error("MiniSynth: non-finite audio; output stopped. Reduce effect gain and reenter the scene tree.")
			return PackedVector2Array()
		var sample := clampf(_mono[i] * volume, -1.0, 1.0)
		_stereo[i] = Vector2(sample, sample)
	return _stereo


func _stop_output() -> void:
	set_process(false)
	if is_instance_valid(_player):
		_player.stop()
		_player.stream = null
	_playback = null


func _exit_tree() -> void:
	_stop_output()
	_clear_voices()
	clear_effects()
	request_ready()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_clear_voices()
		clear_effects()


func _clear_voices() -> void:
	for voice in _voices:
		voice._detach()
	_voices.clear()
