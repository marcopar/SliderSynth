## Captures a stationary source spectrum without monitoring it through the speakers.
class_name SynthAnalyzer
extends Node

const _FFT_BINS := 4096
const _SILENCE_POWER := 1.0e-10
const _RELATIVE_POWER_FLOOR := 1.0e-5
const _PEAK_PROMINENCE := 16.0

# The job owns completion independently of this node, so freeing the node cannot strand an await.
class _Capture extends RefCounted:
	signal completed(partials: PackedVector2Array)

	var done := false
	var bus_name := ""
	var player: AudioStreamPlayer
	var spectrum: AudioEffectSpectrumAnalyzerInstance
	var effect: AudioEffectSpectrumAnalyzer
	var _keep_alive: RefCounted

	func _init() -> void:
		# Deferred calls and signals do not retain RefCounted emitters.
		_keep_alive = self

	func run(owner: Node, tree: SceneTree, stream: AudioStream, duration: float, budget: int) -> void:
		if done:
			return
		var sample_rate := AudioServer.get_mix_rate()
		var interval := 2.0 * SynthAnalyzer._FFT_BINS / sample_rate
		bus_name = "MiniSynthCapture_%d" % get_instance_id()
		var bus := AudioServer.get_bus_count()
		AudioServer.add_bus()
		AudioServer.set_bus_name(bus, bus_name)
		AudioServer.set_bus_send(bus, "Master")
		AudioServer.set_bus_mute(bus, true)
		effect = AudioEffectSpectrumAnalyzer.new()
		effect.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_4096
		effect.buffer_length = 0.1
		AudioServer.add_bus_effect(bus, effect)
		spectrum = AudioServer.get_bus_effect_instance(bus, 0) as AudioEffectSpectrumAnalyzerInstance
		if spectrum == null:
			fail("could not instantiate the spectrum effect.")
			return
		player = AudioStreamPlayer.new()
		player.bus = bus_name
		player.stream = stream
		owner.add_child(player)
		player.play()
		if not player.playing:
			fail("the source player could not start.")
			return
		var powers := PackedFloat64Array()
		powers.resize(SynthAnalyzer._FFT_BINS)
		var observations := 0
		var start := Time.get_ticks_usec()
		while not done:
			var remaining := duration - (Time.get_ticks_usec() - start) / 1000000.0
			if remaining <= 0.0:
				break
			await tree.create_timer(minf(interval, remaining), true, false, true).timeout
			if done:
				return
			if not is_instance_valid(player) or not player.is_inside_tree():
				fail("the source player was removed.")
				return
			bus = AudioServer.get_bus_index(bus_name)
			if bus < 0 or AudioServer.get_bus_effect_count(bus) < 1 \
					or AudioServer.get_bus_effect_instance(bus, 0) != spectrum:
				fail("the owned analysis bus/effect was removed or replaced.")
				return
			var bin_hz := sample_rate / (2.0 * SynthAnalyzer._FFT_BINS)
			for i in range(1, SynthAnalyzer._FFT_BINS):
				# Query inside one bin; exact boundaries can round into an adjacent bin.
				var hz := (i + 0.5) * bin_hz
				var magnitude := spectrum.get_magnitude_for_frequency_range(hz, hz)
				powers[i] += (magnitude.x * magnitude.x + magnitude.y * magnitude.y) * 0.5
			observations += 1
			if not player.playing:
				break
		if done:
			return
		if observations > 0:
			for i in range(powers.size()):
				powers[i] /= observations
		var result := SynthAnalyzer._extract_partials(
			powers, sample_rate / (2.0 * SynthAnalyzer._FFT_BINS), budget
		)
		finish(result)

	func fail(message: String) -> void:
		push_error("SynthAnalyzer.capture: " + message)
		finish(PackedVector2Array())

	func finish(result: PackedVector2Array) -> void:
		if done:
			return
		done = true
		if is_instance_valid(player):
			player.stop()
			player.stream = null
			player.queue_free()
		player = null
		var bus := AudioServer.get_bus_index(bus_name) if not bus_name.is_empty() else -1
		if bus >= 0 and AudioServer.get_bus_effect_count(bus) > 0 \
				and AudioServer.get_bus_effect(bus, 0) == effect:
			AudioServer.remove_bus(bus)
		spectrum = null
		effect = null
		bus_name = ""
		completed.emit(result)
		_keep_alive = null


var _active: _Capture


## Await the returned signal for sorted Vector2(frequency_hz, relative_amplitude) pairs.
func capture(
	stream: AudioStream, duration_seconds: float = 2.0, max_partials: int = 128
) -> Signal:
	if not is_inside_tree():
		return _reject("add the analyzer to the scene tree before capturing.")
	if _active != null:
		return _reject("another capture is already running.")
	if stream == null:
		return _reject("a non-null AudioStream is required.")
	if not is_finite(duration_seconds) or duration_seconds < 0.5 or duration_seconds > 30.0 \
			or duration_seconds < 2.0 * _FFT_BINS / AudioServer.get_mix_rate():
		return _reject("duration_seconds must be 0.5 to 30.0 and cover an FFT window.")
	if max_partials < 1 or max_partials > MiniSynth._MAX_PARTIALS:
		return _reject("max_partials must be 1 to %d." % MiniSynth._MAX_PARTIALS)
	var source_length := stream.get_length()
	if source_length > 0.0 and source_length < 2.0 * _FFT_BINS / AudioServer.get_mix_rate():
		return _reject("the source is shorter than a complete FFT window.")
	if stream is AudioStreamMicrophone:
		if not ProjectSettings.get_setting("audio/driver/enable_input", false):
			return _reject("microphone input requires audio/driver/enable_input.")
		if AudioServer.get_driver_name() == "Dummy" or AudioServer.get_input_device_list().is_empty():
			return _reject("microphone input requires an available input device and real audio driver.")
	_active = _Capture.new()
	_active.completed.connect(_on_completed, CONNECT_ONE_SHOT)
	_active.run.call_deferred(self, get_tree(), stream, duration_seconds, max_partials)
	return _active.completed


## Cancels the pending capture, logging an error and resolving it with an empty list.
func cancel_capture() -> void:
	if _active != null:
		_active.fail("capture was cancelled.")


func _on_completed(_partials: PackedVector2Array) -> void:
	_active = null


func _exit_tree() -> void:
	cancel_capture()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		cancel_capture()


static func _reject(message: String) -> Signal:
	push_error("SynthAnalyzer.capture: " + message)
	var rejected := _Capture.new()
	rejected.finish.call_deferred(PackedVector2Array())
	return rejected.completed


static func _extract_partials(powers: PackedFloat64Array, bin_hz: float, budget: int) -> PackedVector2Array:
	var total := 0.0
	for power in powers:
		total += power
	if not is_finite(total) or total <= _SILENCE_POWER:
		push_error("SynthAnalyzer.capture: no usable audio; check the source, microphone permissions and input level.")
		return PackedVector2Array()
	var peaks: Array[Vector3] = []
	for i in range(1, powers.size()):
		var right := powers[i + 1] if i + 1 < powers.size() else 0.0
		if powers[i] <= powers[i - 1] or powers[i] < right:
			continue
		var neighbors := PackedFloat64Array()
		for j in range(maxi(1, i - 8), mini(powers.size(), i + 9)):
			if absi(j - i) > 2:
				neighbors.append(powers[j])
		neighbors.sort()
		var background := neighbors[neighbors.size() / 2]
		if powers[i] < maxf(background * _PEAK_PROMINENCE, total * _RELATIVE_POWER_FLOOR):
			continue
		var power := 0.0
		var weighted_bin := 0.0
		for j in range(maxi(1, i - 2), mini(powers.size(), i + 3)):
			power += powers[j]
			weighted_bin += j * powers[j]
		peaks.append(Vector3(weighted_bin / power * bin_hz, power / total, i))
	peaks.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		return a.y > b.y if a.y != b.y else a.x < b.x)
	var used := PackedByteArray()
	used.resize(powers.size())
	var components: Array[Vector2] = []
	for peak in peaks:
		if components.size() >= maxi(1, budget / 2):
			break
		var center := int(peak.z)
		var overlaps := false
		for j in range(maxi(1, center - 2), mini(powers.size(), center + 3)):
			overlaps = overlaps or used[j] != 0
		if overlaps:
			continue
		for j in range(maxi(1, center - 2), mini(powers.size(), center + 3)):
			used[j] = 1
		components.append(Vector2(peak.x, peak.y))
	var bands := budget - components.size()
	var begin := 1
	for band in range(bands):
		var end := ceili(pow(float(powers.size()), float(band + 1) / bands))
		end = mini(end, powers.size())
		var power := 0.0
		var weighted_bin := 0.0
		for i in range(begin, end):
			if used[i] == 0:
				power += powers[i]
				weighted_bin += i * powers[i]
		if power >= total * _RELATIVE_POWER_FLOOR:
			components.append(Vector2(weighted_bin / power * bin_hz, power / total))
		begin = end
	components.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var result := PackedVector2Array()
	var retained := 0.0
	for component in components:
		if not result.is_empty() and is_equal_approx(result[-1].x, component.x):
			result[-1] = Vector2(result[-1].x, result[-1].y + component.y)
		else:
			result.append(component)
		retained += component.y
	if retained <= 0.0:
		push_error("SynthAnalyzer.capture: no components survived spectrum filtering.")
		return PackedVector2Array()
	for i in range(result.size()):
		result[i] = Vector2(result[i].x, sqrt(result[i].y / retained))
	return result
