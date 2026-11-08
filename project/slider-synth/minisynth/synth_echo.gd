## Feedback echo, obtained through MiniSynth.create_echo().
class_name SynthEcho
extends SynthEffect

var delay_seconds: float = 0.25:
	set(value):
		if not _valid_range(value, 0.001, 2.0, "delay_seconds"):
			return
		var frames := maxi(1, roundi(value * _sample_rate))
		if frames != _delay.size():
			_delay.resize(frames)
			_reset()
		delay_seconds = value
var feedback_level: float = 0.35:
	set(value):
		if _valid_range(value, 0.0, 0.95, "feedback_level"):
			feedback_level = value

var _delay := PackedFloat32Array()
var _cursor := 0


func _init(sample_rate: float) -> void:
	super(sample_rate, "SynthEcho")
	_delay.resize(maxi(1, roundi(delay_seconds * sample_rate)))


func _process_block(buffer: PackedFloat32Array) -> void:
	if not _attached or not enabled:
		return
	var wet := wet_level
	var dry := 1.0 - wet
	var feedback := feedback_level
	var frames := _delay.size()
	for i in range(buffer.size()):
		var input := buffer[i]
		var delayed := _delay[_cursor]
		_delay[_cursor] = input + feedback * delayed
		buffer[i] = dry * input + wet * delayed
		_cursor += 1
		if _cursor == frames:
			_cursor = 0


func _reset() -> void:
	_delay.fill(0.0)
	_cursor = 0


func _detach() -> void:
	super._detach()
	_delay = PackedFloat32Array()
	_cursor = 0
