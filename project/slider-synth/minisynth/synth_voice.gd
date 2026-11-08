## One reusable note, obtained through MiniSynth's builtin/custom voice factories.
class_name SynthVoice
extends RefCounted

enum Waveform { SINE, TRIANGLE, SQUARE, SAWTOOTH, REVERSE_SAWTOOTH, CUSTOM }
enum _Stage { OFF, ATTACK, DECAY, SUSTAIN, RELEASE }

const _TABLE_SIZE := 2048
static var _tables: Array[PackedFloat32Array] = []

var waveform: Waveform = Waveform.SINE:
	set(value):
		if not _valid_handle("waveform"):
			return
		if value < Waveform.SINE or value > Waveform.CUSTOM:
			push_error("SynthVoice.waveform: unknown waveform.")
			return
		if value == Waveform.CUSTOM and _custom_table.is_empty():
			push_error("SynthVoice.waveform: CUSTOM requires create_custom_voice().")
			return
		var next_table := _custom_table if value == Waveform.CUSTOM else _tables[value]
		if not _table.is_empty():
			_phase = _phase / _table.size() * next_table.size()
		_table = next_table
		_phase_scale = 1.0 / _custom_reference_hz if value == Waveform.CUSTOM else _TABLE_SIZE / _sample_rate
		waveform = value
var attack_seconds: float = 0.01:
	set(value):
		if _valid_time(value, "attack_seconds"):
			attack_seconds = value
var decay_seconds: float = 0.1:
	set(value):
		if _valid_time(value, "decay_seconds"):
			decay_seconds = value
var sustain_level: float = 0.7:
	set(value):
		if _valid_handle("sustain_level") and _valid_level(value, "SynthVoice.sustain_level"):
			sustain_level = value
var release_seconds: float = 0.15:
	set(value):
		if _valid_time(value, "release_seconds"):
			release_seconds = value
var volume: float = 0.25:
	set(value):
		if _valid_handle("volume") and _valid_level(value, "SynthVoice.volume"):
			volume = value

var _sample_rate: float
var _phase_scale: float
var _table := PackedFloat32Array()
var _custom_table := PackedFloat32Array()
var _custom_reference_hz := 440.0
var _attached := true
var _phase := 0.0
var _frequency := 0.0
var _sweep_remaining := 0
var _sweep_step := 0.0
var _sweep_target := 0.0
var _stage: _Stage = _Stage.OFF
var _level := 0.0
var _ramp_remaining := 0
var _ramp_step := 0.0
var _ramp_target := 0.0


func _init(sample_rate: float) -> void:
	_bake_tables()
	_sample_rate = sample_rate
	_phase_scale = _TABLE_SIZE / sample_rate
	_table = _tables[Waveform.SINE]


## Retriggers attack from the current level without resetting phase; false on rejection.
func note_on(frequency_hz: float) -> bool:
	if not _valid_frequency(frequency_hz, "note_on"):
		return false
	_frequency = frequency_hz
	_sweep_remaining = 0
	_start_ramp(_Stage.ATTACK, 1.0, attack_seconds)
	return true


## Releases from the current level, holding pitch. Repeated calls do not restart release.
func note_off() -> bool:
	if not _valid_handle("note_off"):
		return false
	if _stage != _Stage.OFF and _stage != _Stage.RELEASE:
		_sweep_remaining = 0
		_start_ramp(_Stage.RELEASE, 0.0, release_seconds)
	return true


## Linear glide for a held note; zero seconds changes pitch immediately. False on rejection.
func sweep_to(frequency_hz: float, duration_seconds: float) -> bool:
	if not _valid_frequency(frequency_hz, "sweep_to") or not _valid_time(duration_seconds, "sweep_to"):
		return false
	if _stage == _Stage.OFF or _stage == _Stage.RELEASE:
		push_error("SynthVoice.sweep_to: a held note is required.")
		return false
	_sweep_target = frequency_hz
	_sweep_remaining = roundi(duration_seconds * _sample_rate)
	if _sweep_remaining == 0:
		_frequency = frequency_hz
	else:
		_sweep_step = (frequency_hz - _frequency) / _sweep_remaining
	return true


## True while held or releasing, even at zero volume. Describes generated, not queued audio.
func is_active() -> bool:
	return _stage != _Stage.OFF


static func _bake_tables() -> void:
	if not _tables.is_empty():
		return
	for shape in range(Waveform.REVERSE_SAWTOOTH + 1):
		var table := PackedFloat32Array()
		table.resize(_TABLE_SIZE)
		for i in range(_TABLE_SIZE):
			var phase := float(i) / _TABLE_SIZE
			match shape:
				Waveform.SINE:
					table[i] = sin(TAU * phase)
				Waveform.TRIANGLE:
					table[i] = 1.0 - 4.0 * absf(phase - 0.5)
				Waveform.SQUARE:
					table[i] = 1.0 if i < _TABLE_SIZE / 2 else -1.0
				Waveform.SAWTOOTH:
					table[i] = 2.0 * phase - 1.0
				Waveform.REVERSE_SAWTOOTH:
					table[i] = 1.0 - 2.0 * phase
		_tables.append(table)


func _mix_into(buffer: PackedFloat32Array) -> void:
	var table := _table
	var table_size := table.size()
	for i in range(buffer.size()):
		if _stage == _Stage.OFF:
			break
		if _ramp_remaining > 0:
			_level += _ramp_step
			_ramp_remaining -= 1
			if _ramp_remaining == 0:
				_level = _ramp_target
				_finish_ramp()
		elif _stage == _Stage.SUSTAIN:
			_level = sustain_level
		buffer[i] += table[int(_phase)] * _level * volume
		_phase += _frequency * _phase_scale
		if _phase >= table_size:
			_phase = fmod(_phase, table_size)
		if _sweep_remaining > 0:
			_frequency += _sweep_step
			_sweep_remaining -= 1
			if _sweep_remaining == 0:
				_frequency = _sweep_target


func _install_custom(table: PackedFloat32Array, reference_hz: float) -> void:
	_custom_table = table
	_custom_reference_hz = reference_hz
	waveform = Waveform.CUSTOM


func _start_ramp(stage: _Stage, target: float, seconds: float) -> void:
	_stage = stage
	_ramp_target = target
	_ramp_remaining = roundi(seconds * _sample_rate)
	if _ramp_remaining == 0:
		_level = target
		_finish_ramp()
	else:
		_ramp_step = (target - _level) / _ramp_remaining


func _finish_ramp() -> void:
	match _stage:
		_Stage.ATTACK:
			_start_ramp(_Stage.DECAY, sustain_level, decay_seconds)
		_Stage.DECAY:
			_stage = _Stage.SUSTAIN
		_Stage.RELEASE:
			_stage = _Stage.OFF


func _detach() -> void:
	_attached = false
	_stage = _Stage.OFF
	_level = 0.0
	_sweep_remaining = 0
	_table = PackedFloat32Array()
	_custom_table = PackedFloat32Array()


func _valid_handle(member: String) -> bool:
	if not _attached:
		push_error("SynthVoice.%s: this voice is no longer registered with a synth." % member)
		return false
	return true


func _valid_frequency(value: float, member: String) -> bool:
	if not _valid_handle(member):
		return false
	if not is_finite(value) or value <= 0.0 or value >= _sample_rate * 0.5:
		push_error("SynthVoice.%s: frequency must be finite, positive, and below Nyquist." % member)
		return false
	return true


func _valid_time(value: float, label: String) -> bool:
	if not _valid_handle(label):
		return false
	if not is_finite(value) or value < 0.0 or value * _sample_rate >= float(0x7fffffffffffffff):
		push_error("SynthVoice.%s: expected finite, nonnegative seconds fitting a sample count." % label)
		return false
	return true


static func _valid_level(value: float, property_name: String) -> bool:
	if not is_finite(value) or value < 0.0 or value > 1.0:
		push_error("%s: expected a finite level from 0 to 1." % property_name)
		return false
	return true
