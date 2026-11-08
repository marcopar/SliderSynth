## Shared configuration for synth-owned effects; obtain concrete handles through MiniSynth.
@abstract
class_name SynthEffect
extends RefCounted

var enabled: bool = true:
	set(value):
		if not _valid_handle("enabled") or enabled == value:
			return
		enabled = value
		if not enabled:
			_reset()
var wet_level: float = 0.25:
	set(value):
		if _valid_range(value, 0.0, 1.0, "wet_level"):
			wet_level = value

var _sample_rate: float
var _effect_name: String
var _attached := true


func _init(sample_rate: float, effect_name: String) -> void:
	_sample_rate = sample_rate
	_effect_name = effect_name


@abstract
func _process_block(buffer: PackedFloat32Array) -> void


@abstract
func _reset() -> void


func _detach() -> void:
	_attached = false


func _valid_handle(member: String) -> bool:
	if not _attached:
		push_error("%s.%s: this effect is no longer registered with a synth." % [_effect_name, member])
		return false
	return true


func _valid_range(value: float, minimum: float, maximum: float, member: String) -> bool:
	if not _valid_handle(member):
		return false
	if not is_finite(value) or value < minimum or value > maximum:
		push_error("%s.%s: expected a finite value from %s to %s." %
			[_effect_name, member, minimum, maximum])
		return false
	return true
