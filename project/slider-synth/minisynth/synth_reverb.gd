## Small damped comb/all-pass reverb, obtained through MiniSynth.create_reverb().
class_name SynthReverb
extends SynthEffect

const _COMB_SECONDS := [0.0297, 0.0371, 0.0411, 0.0437]
const _ALLPASS_SECONDS := [0.005, 0.0017]

var room_size: float = 0.5:
	set(value):
		if _valid_range(value, 0.0, 1.0, "room_size"):
			room_size = value
var damping_level: float = 0.5:
	set(value):
		if _valid_range(value, 0.0, 1.0, "damping_level"):
			damping_level = value

var _combs: Array[PackedFloat32Array] = []
var _allpasses: Array[PackedFloat32Array] = []
var _comb_positions := PackedInt32Array()
var _allpass_positions := PackedInt32Array()
var _filtered := PackedFloat64Array()


func _init(sample_rate: float) -> void:
	super(sample_rate, "SynthReverb")
	for seconds: float in _COMB_SECONDS:
		var delay := PackedFloat32Array()
		delay.resize(maxi(1, roundi(seconds * sample_rate)))
		_combs.append(delay)
	for seconds: float in _ALLPASS_SECONDS:
		var delay := PackedFloat32Array()
		delay.resize(maxi(1, roundi(seconds * sample_rate)))
		_allpasses.append(delay)
	_comb_positions.resize(_combs.size())
	_allpass_positions.resize(_allpasses.size())
	_filtered.resize(_combs.size())


func _process_block(buffer: PackedFloat32Array) -> void:
	if not _attached or not enabled:
		return
	var wet := wet_level
	var dry := 1.0 - wet
	var feedback := 0.2 + 0.7 * room_size
	var damping := 0.95 * damping_level
	var comb_count := _combs.size()
	var allpass_count := _allpasses.size()
	var comb_gain := 1.0 / comb_count
	for i in range(buffer.size()):
		var input := buffer[i]
		var output := 0.0
		for comb in range(comb_count):
			var delay := _combs[comb]
			var cursor := _comb_positions[comb]
			var delayed := delay[cursor]
			var filtered := (1.0 - damping) * delayed + damping * _filtered[comb]
			_filtered[comb] = filtered
			delay[cursor] = input + feedback * filtered
			_comb_positions[comb] = 0 if cursor + 1 == delay.size() else cursor + 1
			output += delayed
		output *= comb_gain
		for allpass in range(allpass_count):
			var delay := _allpasses[allpass]
			var cursor := _allpass_positions[allpass]
			var next := delay[cursor] - 0.5 * output
			delay[cursor] = output + 0.5 * next
			_allpass_positions[allpass] = 0 if cursor + 1 == delay.size() else cursor + 1
			output = next
		buffer[i] = dry * input + wet * output


func _reset() -> void:
	for delay in _combs:
		delay.fill(0.0)
	for delay in _allpasses:
		delay.fill(0.0)
	_comb_positions.fill(0)
	_allpass_positions.fill(0)
	_filtered.fill(0.0)


func _detach() -> void:
	super._detach()
	_combs.clear()
	_allpasses.clear()
	_comb_positions.clear()
	_allpass_positions.clear()
	_filtered.clear()
