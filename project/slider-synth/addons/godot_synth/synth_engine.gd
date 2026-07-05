class_name SynthEngine
extends Node

# Polyphonic wavetable synth feeding an AudioStreamGenerator.
#
# Voice rendering is per-sample in GDScript, so cost is roughly:
#   mix_rate * active_voices * (~1 wavetable read + ADSR + lowpass)
# 22050 Hz with up to ~16 voices fits comfortably; raise mix_rate for quality
# at the cost of CPU. Each voice uses a precomputed wavetable from its patch
# (see SynthPatch) so there are no per-sample sin() calls in the hot path.

## Audio sample rate (Hz). 22050 is plenty for game music and costs half the
## CPU of 44100. Higher rates reduce aliasing on bright/saw timbres. Set the
## initial value here; change it at runtime via [method configure] (which
## rebuilds the players, since a live AudioStreamGenerator can't be re-rated).
@export var mix_rate: float = 22050.0

## AudioStreamGenerator buffer length in seconds. Shorter = lower latency but
## higher risk of underruns if a frame stalls. 0.05 is a good default.
@export var buffer_length: float = 0.05

## Voice pool size. When all voices are active, [method note_on] steals the
## oldest voice. Raise for dense polyphony (chords + arpeggios + drums);
## lower to cap CPU on slower machines.
@export var max_voices: int = 24

## Final output level applied after summing all voices. Use for fade in/out
## via tween. Voices are clipped to [-1, 1] after this multiplication.
@export_range(0.0, 1.0) var master_gain: float = 0.6

## Equal-loudness compensation strength. Applies a -3 dB/octave tilt
## (relative to A4 = 440 Hz) so low notes aren't perceptually quieter
## than highs at the same velocity. 0 = off, 1 = full compensation.
@export_range(0.0, 1.0) var loudness_compensation: float = 1.0

const ENV_ATTACK := 0
const ENV_DECAY := 1
const ENV_SUSTAIN := 2
const ENV_RELEASE := 3

class Voice:
	var active: bool = false
	var released: bool = false
	var channel: int = 0
	var note: int = 0
	var freq: float = 440.0
	var velocity: float = 1.0
	var patch: SynthPatch
	var phase: float = 0.0
	var detune_phase: PackedFloat32Array = PackedFloat32Array()
	var env_state: int = 0
	var env_value: float = 0.0
	var release_start: float = 1.0
	var pitch_time: float = 0.0
	var age: int = 0
	# FM modulator state
	var mod_phase: float = 0.0
	# Filter envelope (ADSR mirror)
	var fenv_state: int = 0
	var fenv_value: float = 0.0
	var fenv_release_start: float = 0.0
	# State-variable filter state (trapezoidal integrator values)
	var svf_ic1: float = 0.0
	var svf_ic2: float = 0.0
	# Per-frame cached SVF coefficients
	var svf_a1: float = 0.0
	var svf_a2: float = 0.0
	var svf_a3: float = 0.0
	var svf_k: float = 2.0
	# Noise state
	var noise_env: float = 1.0
	var noise_lp_state: float = 0.0
	var noise_hp_state: float = 0.0
	# Stereo pan (-1 = full left, 0 = center, +1 = full right)
	var pan: float = 0.0
	# Pitch glide (bend) state. samples_left > 0 means an active glide:
	# multiply freq by glide_factor each sample until samples_left hits 0,
	# then snap to glide_target_freq to absorb FP drift. Cheap by design —
	# one mul + one decrement per active voice per sample.
	var glide_samples_left: int = 0
	var glide_factor: float = 1.0
	var glide_target_freq: float = 0.0
	# Equal-loudness gain factor, computed once at note-on from the voice's
	# initial frequency. sqrt(440 / freq) gives -3 dB/octave relative to A4.
	var loudness_comp: float = 1.0

# One AudioStreamPlayer per channel (0..15), each routable to its own
# audio bus so users can attach Godot's built-in effects (reverb, delay,
# EQ, distortion, compressor, etc.) via the editor's Audio dock.
var _channel_players: Array[AudioStreamPlayer] = []
var _channel_playbacks: Array[AudioStreamGeneratorPlayback] = []
# Name of the auto-created AudioServer bus per channel (empty if none).
# Managed by ensure_channel_bus / release_channel_bus. Cleaned up on
# _exit_tree.
var _channel_buses: Array[StringName] = []
var _voices: Array[Voice] = []
var _patches: Array[SynthPatch] = []
var _default_patch: SynthPatch
var _age_counter: int = 0
var _lfo_time: float = 0.0

# Private RNG so the render thread never touches the global randf() state shared
# with main-thread game code (pitch/velocity randomize, noise gen all use it).
var _rng := RandomNumberGenerator.new()

# --- Audio thread + command queue ------------------------------------------
# Voice/patch state is owned exclusively by the render thread. The public
# note_on/note_off/bend_to/all_notes_off/set_patch methods run on the main
# (game) thread and only enqueue commands under a short-held mutex; the thread
# drains and applies them at the top of each render iteration. Critical
# sections stay tiny (list append/swap) so the game thread never blocks on a
# full render block.
enum { CMD_NOTE_ON, CMD_NOTE_OFF, CMD_BEND, CMD_ALL_OFF, CMD_SET_PATCH }
var _thread := Thread.new()
var _running: bool = false
# When false, the render thread is stopped (zero synth CPU) and incoming note
# commands are dropped. Toggled via set_enabled() — lets a host kill the engine
# entirely (e.g. a "disable synth" setting on weak hardware).
var _enabled: bool = true
var _cmd_mutex := Mutex.new()
var _cmds: Array = []
# Frames rendered per loop iteration. ~256 @ 22050 Hz ≈ 12 ms, so queued note
# commands are applied at least this often — bounds scheduling jitter well
# below buffer_length (0.05 s).
const _MAX_CHUNK := 256

# Flat mixdown buffers, split L/R: index = channel * frames + sample_index.
# Two PackedFloat32Arrays instead of one PackedVector2Array so the per-sample
# accumulate is a plain float += with no Variant/Vector2 boxing. Stored as
# members to avoid copy-on-write (direct member access stays at refcount=1 so
# writes are in-place).
var _mix_l: PackedFloat32Array = PackedFloat32Array()
var _mix_r: PackedFloat32Array = PackedFloat32Array()
var _push_buf: PackedVector2Array = PackedVector2Array()
# Scratch for per-buffer unison detune ratios (constant within a buffer). Reused
# across voices on the render thread to avoid per-buffer allocation (GC churn in
# the audio loop risks underruns).
var _detune_ratios: PackedFloat32Array = PackedFloat32Array()

const CHANNEL_COUNT := 16

func _ready() -> void:
	_channel_players.resize(CHANNEL_COUNT)
	_channel_playbacks.resize(CHANNEL_COUNT)
	_channel_buses.resize(CHANNEL_COUNT)
	for ch in CHANNEL_COUNT:
		_channel_buses[ch] = &""

	# First build: all channels route straight to Master.
	var routes: Array = []
	routes.resize(CHANNEL_COUNT)
	routes.fill(&"Master")
	_create_channel_players(routes)
	_create_voice_pool()

	_default_patch = SynthPatch.new()
	_patches.resize(CHANNEL_COUNT)
	for i in CHANNEL_COUNT:
		_patches[i] = _default_patch

	_rng.randomize()
	_start_thread()

# Build the 16 per-channel AudioStreamPlayers at the current mix_rate /
# buffer_length, routing each to bus_routes[ch]. Populates _channel_players and
# _channel_playbacks. Render thread must be stopped when this runs.
func _create_channel_players(bus_routes: Array) -> void:
	for ch in CHANNEL_COUNT:
		var stream := AudioStreamGenerator.new()
		stream.mix_rate = mix_rate
		stream.buffer_length = buffer_length
		var player := AudioStreamPlayer.new()
		player.name = "Ch%dPlayer" % ch
		player.stream = stream
		player.bus = bus_routes[ch]
		add_child(player)
		player.play()
		_channel_players[ch] = player
		_channel_playbacks[ch] = player.get_stream_playback()

func _create_voice_pool() -> void:
	_voices.clear()
	_voices.resize(max_voices)
	for i in max_voices:
		_voices[i] = Voice.new()

func _start_thread() -> void:
	_running = true
	_thread = Thread.new()
	_thread.start(_audio_loop)

func _stop_thread() -> void:
	if _running:
		_running = false
		if _thread.is_started():
			_thread.wait_to_finish()

## Rebuild the audio pipeline with new quality settings. Safe to call at runtime
## (e.g. when the game switches graphics/quality tiers): the render thread is
## stopped during the rebuild. A live AudioStreamGenerator's mix_rate can't be
## changed, so the per-channel players are recreated; bus routing and per-channel
## patches are preserved, but any currently-sounding notes are dropped.
func configure(p_mix_rate: float, p_buffer_length: float, p_max_voices: int) -> void:
	if is_equal_approx(p_mix_rate, mix_rate) and is_equal_approx(p_buffer_length, buffer_length) \
			and p_max_voices == max_voices:
		return
	_stop_thread()
	# Snapshot current bus routing so rebuilt players keep their effect chains.
	var routes: Array = []
	routes.resize(CHANNEL_COUNT)
	for ch in CHANNEL_COUNT:
		var p: AudioStreamPlayer = _channel_players[ch]
		routes[ch] = p.bus if p != null else &"Master"
		if p != null:
			remove_child(p)
			p.free()
	mix_rate = p_mix_rate
	buffer_length = p_buffer_length
	max_voices = maxi(1, p_max_voices)
	_create_channel_players(routes)
	_create_voice_pool()
	# Frame count per buffer changed; force the mix/push buffers to re-alloc.
	_mix_l = PackedFloat32Array()
	_mix_r = PackedFloat32Array()
	_push_buf = PackedVector2Array()
	# Stay silent if disabled — don't resurrect the render thread.
	if _enabled:
		_start_thread()

## Enable or disable the whole engine. Disabling stops the render thread (so the
## synth costs zero CPU) and drops queued/incoming notes; enabling restarts it.
## Useful as a user setting to bail out of audio on hardware that can't keep up.
func set_enabled(p_enabled: bool) -> void:
	if p_enabled == _enabled:
		return
	_enabled = p_enabled
	if _enabled:
		_start_thread()
	else:
		_stop_thread()
		# Drop pending commands and silence held voices so a later enable is clean.
		_cmd_mutex.lock()
		_cmds.clear()
		_cmd_mutex.unlock()
		for v in _voices:
			v.active = false

func is_enabled() -> bool:
	return _enabled

## Route a channel's output to a named audio bus. Users can create buses
## in Godot's Audio dock and attach AudioEffect* nodes (reverb, delay,
## EQ, chorus, distortion, etc.) — those effects then process this
## channel's output before it reaches the master.
func set_channel_bus(channel: int, bus: StringName) -> void:
	if channel < 0 or channel >= CHANNEL_COUNT:
		return
	var p := _channel_players[channel]
	if p != null:
		p.bus = bus

func get_channel_bus(channel: int) -> StringName:
	if channel < 0 or channel >= CHANNEL_COUNT:
		return &"Master"
	var p := _channel_players[channel]
	return p.bus if p != null else &"Master"

## Ensure an auto-bus exists for [param channel], has exactly the given
## [param effects] in order, and sends to [param send_target]. Routes
## the channel's output to this bus. Subsequent calls for the same
## channel replace the effect chain (old effects removed, new ones
## added). Effects are installed by reference — editing an AudioEffect
## resource at runtime affects the live audio.
func ensure_channel_bus(channel: int, effects: Array, send_target: StringName = &"Master") -> StringName:
	if channel < 0 or channel >= CHANNEL_COUNT:
		return &"Master"
	var name: StringName = _channel_buses[channel]
	var idx: int = -1
	if name != &"":
		idx = AudioServer.get_bus_index(name)
	if idx == -1:
		var base := StringName("Ch%d" % channel)
		name = _unique_bus_name(base)
		idx = AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, name)
		_channel_buses[channel] = name
	# Clear + install fresh effect chain.
	while AudioServer.get_bus_effect_count(idx) > 0:
		AudioServer.remove_bus_effect(idx, 0)
	for eff in effects:
		if eff != null:
			AudioServer.add_bus_effect(idx, eff)
	AudioServer.set_bus_send(idx, send_target)
	set_channel_bus(channel, name)
	return name

## Remove the auto-bus for [param channel] and reset the channel's
## output to Master. Called internally on _exit_tree; game code rarely
## needs this directly.
func release_channel_bus(channel: int) -> void:
	if channel < 0 or channel >= CHANNEL_COUNT:
		return
	var name: StringName = _channel_buses[channel]
	if name == &"":
		return
	var idx: int = AudioServer.get_bus_index(name)
	if idx != -1:
		AudioServer.remove_bus(idx)
	_channel_buses[channel] = &""
	set_channel_bus(channel, &"Master")

func _unique_bus_name(base: StringName) -> StringName:
	if AudioServer.get_bus_index(base) == -1:
		return base
	var i: int = 2
	while AudioServer.get_bus_index(StringName("%s_%d" % [base, i])) != -1:
		i += 1
	return StringName("%s_%d" % [base, i])

func _exit_tree() -> void:
	# Stop the render thread before tearing down buses/playbacks it reads.
	_stop_thread()
	for ch in CHANNEL_COUNT:
		release_channel_bus(ch)

func set_patch(channel: int, patch: SynthPatch) -> void:
	if not _enabled:
		return
	_cmd_mutex.lock()
	_cmds.push_back([CMD_SET_PATCH, channel, patch])
	_cmd_mutex.unlock()

func _apply_set_patch(channel: int, patch: SynthPatch) -> void:
	if channel < 0 or channel >= 16 or patch == null:
		return
	_patches[channel] = patch

## Trigger a note on [param channel]. [param note] is a MIDI number,
## accepted as float so microtonal pitches (e.g. 60.5) work end-to-end.
## The integer part (rounded) is used as the lookup key for [method note_off]
## and [method bend_to]; the fractional part feeds frequency.
func note_on(channel: int, note: float, velocity: float = 1.0, pan: float = 0.0) -> void:
	if not _enabled:
		return
	_cmd_mutex.lock()
	_cmds.push_back([CMD_NOTE_ON, channel, note, velocity, pan])
	_cmd_mutex.unlock()

func _apply_note_on(channel: int, note: float, velocity: float, pan: float) -> void:
	var v := _allocate_voice()
	var patch: SynthPatch = _patches[channel]
	_age_counter += 1
	v.active = true
	v.released = false
	v.channel = channel
	v.note = roundi(note)
	var effective_freq: float = 440.0 * pow(2.0, (note - 69.0) / 12.0)
	if patch.pitch_randomize_cents > 0.0:
		var cents: float = (_rng.randf() * 2.0 - 1.0) * patch.pitch_randomize_cents
		effective_freq *= pow(2.0, cents / 1200.0)
	v.freq = effective_freq
	v.glide_samples_left = 0
	v.glide_factor = 1.0
	v.glide_target_freq = effective_freq
	var eff_vel: float = clamp(velocity, 0.0, 1.0)
	if patch.velocity_randomize > 0.0:
		eff_vel *= lerpf(1.0 - patch.velocity_randomize, 1.0, _rng.randf())
	v.velocity = eff_vel
	v.pan = clampf(pan, -1.0, 1.0)
	v.patch = patch
	v.phase = 0.0
	v.env_state = ENV_ATTACK
	v.env_value = 0.0
	v.pitch_time = 0.0
	v.age = _age_counter
	v.mod_phase = 0.0
	v.fenv_state = ENV_ATTACK
	v.fenv_value = 0.0
	v.fenv_release_start = 0.0
	v.svf_ic1 = 0.0
	v.svf_ic2 = 0.0
	v.noise_env = 1.0
	v.noise_lp_state = 0.0
	v.noise_hp_state = 0.0
	if loudness_compensation > 0.0 and effective_freq > 0.0:
		v.loudness_comp = lerpf(1.0, clampf(sqrt(440.0 / effective_freq), 0.25, 3.0), loudness_compensation)
	else:
		v.loudness_comp = 1.0
	var dv := patch.detune_voices
	if dv > 1:
		v.detune_phase = PackedFloat32Array()
		v.detune_phase.resize(dv)
		for i in dv:
			v.detune_phase[i] = _rng.randf()

func note_off(channel: int, note: int) -> void:
	if not _enabled:
		return
	_cmd_mutex.lock()
	_cmds.push_back([CMD_NOTE_OFF, channel, note])
	_cmd_mutex.unlock()

func _apply_note_off(channel: int, note: int) -> void:
	for v in _voices:
		if v.active and not v.released and v.channel == channel and v.note == note:
			v.released = true
			v.env_state = ENV_RELEASE
			v.release_start = v.env_value
			v.fenv_state = ENV_RELEASE
			v.fenv_release_start = v.fenv_value
			return

## Glide the live voice on (channel, source_midi) from its current pitch
## to [param target_freq] over [param glide_seconds]. Picks the newest
## unreleased matching voice. No-op if no voice matches. The glide
## composes naturally with vibrato + pitch_decay — they multiply against
## the gliding base freq each sample.
##
## glide_seconds <= 0 snaps immediately. Stacks: calling bend_to again
## mid-glide picks up from the current (mid-glide) pitch.
func bend_to(channel: int, source_midi: int, target_freq: float, glide_seconds: float) -> void:
	if not _enabled:
		return
	_cmd_mutex.lock()
	_cmds.push_back([CMD_BEND, channel, source_midi, target_freq, glide_seconds])
	_cmd_mutex.unlock()

func _apply_bend_to(channel: int, source_midi: int, target_freq: float, glide_seconds: float) -> void:
	var voice: Voice = null
	var newest_age: int = -1
	for v in _voices:
		if v.active and not v.released and v.channel == channel and v.note == source_midi:
			if v.age > newest_age:
				newest_age = v.age
				voice = v
	if voice == null:
		return
	var safe_target: float = maxf(target_freq, 0.0001)
	if glide_seconds <= 0.0 or voice.freq <= 0.0:
		voice.freq = safe_target
		voice.glide_target_freq = safe_target
		voice.glide_samples_left = 0
		return
	var samples: int = maxi(1, int(glide_seconds * mix_rate))
	voice.glide_samples_left = samples
	voice.glide_target_freq = safe_target
	# Per-sample multiplicative step in log-frequency space — one mul/sample.
	var ratio: float = safe_target / voice.freq
	voice.glide_factor = pow(ratio, 1.0 / float(samples))

func all_notes_off() -> void:
	if not _enabled:
		return
	_cmd_mutex.lock()
	_cmds.push_back([CMD_ALL_OFF])
	_cmd_mutex.unlock()

func _apply_all_notes_off() -> void:
	for v in _voices:
		v.active = false
		v.released = false

func _allocate_voice() -> Voice:
	var oldest: Voice = _voices[0]
	var oldest_age := 0x7fffffff
	for v in _voices:
		if not v.active:
			return v
		if v.age < oldest_age:
			oldest_age = v.age
			oldest = v
	return oldest

# Render thread entry point. Owns all voice/patch state: drains queued commands,
# fills whatever the generator can take (capped per iteration), then sleeps when
# the buffer is full to avoid busy-spinning.
func _audio_loop() -> void:
	while _running:
		_drain_commands()
		var filled := _render_block(_MAX_CHUNK)
		if filled <= 0:
			OS.delay_usec(2000)

# Pop all queued commands under the mutex (cheap swap), then apply them in FIFO
# order on this (render) thread so voice/patch mutation never races the game thread.
func _drain_commands() -> void:
	_cmd_mutex.lock()
	var batch := _cmds
	_cmds = []
	_cmd_mutex.unlock()
	for c in batch:
		match c[0]:
			CMD_NOTE_ON:
				_apply_note_on(c[1], c[2], c[3], c[4])
			CMD_NOTE_OFF:
				_apply_note_off(c[1], c[2])
			CMD_BEND:
				_apply_bend_to(c[1], c[2], c[3], c[4])
			CMD_ALL_OFF:
				_apply_all_notes_off()
			CMD_SET_PATCH:
				_apply_set_patch(c[1], c[2])

# Render up to [param max_frames] of audio across all channels and push to the
# generators. Returns the number of frames actually filled (0 if the buffer is
# already full). Runs only on the audio thread.
func _render_block(max_frames: int) -> int:
	if _channel_playbacks.is_empty() or _channel_playbacks[0] == null:
		return 0
	# Use channel 0's playback to determine how many frames to fill; all
	# channels share the same mix_rate + buffer_length so they stay in sync.
	var frames: int = _channel_playbacks[0].get_frames_available()
	if frames <= 0:
		return 0
	if frames > max_frames:
		frames = max_frames
	var dt := 1.0 / mix_rate

	# Resize + zero the flat L/R mixdown buffers.
	var total_frames := CHANNEL_COUNT * frames
	if _mix_l.size() != total_frames:
		_mix_l.resize(total_frames)
		_mix_r.resize(total_frames)
	_mix_l.fill(0.0)
	_mix_r.fill(0.0)

	# Voice-major render: each active voice fills its whole channel slice in one
	# call. Per-patch branch decisions are hoisted out of the per-sample loop
	# inside _render_voice_block, and there's no per-sample function-call
	# boundary — the two big wins over the old sample-major loop. The vibrato
	# LFO advances from a captured base so all voices see the same clock as the
	# old loop did; advance the shared clock once after rendering.
	var lfo_base := _lfo_time
	for v in _voices:
		if v.active:
			_render_voice_block(v, frames, dt, lfo_base)
	_lfo_time = lfo_base + frames * dt

	# Per-channel: apply master gain, clip, interleave, push to the player.
	if _push_buf.size() != frames:
		_push_buf.resize(frames)
	for ch in CHANNEL_COUNT:
		var playback: AudioStreamGeneratorPlayback = _channel_playbacks[ch]
		if playback == null:
			continue
		var base := ch * frames
		for i in frames:
			var lx: float = _mix_l[base + i] * master_gain
			var rx: float = _mix_r[base + i] * master_gain
			if lx > 1.0: lx = 1.0
			elif lx < -1.0: lx = -1.0
			if rx > 1.0: rx = 1.0
			elif rx < -1.0: rx = -1.0
			_push_buf[i] = Vector2(lx, rx)
		playback.push_buffer(_push_buf)
	return frames

func _update_svf_coefs(v: Voice, p: SynthPatch) -> void:
	# Effective cutoff: base + envelope modulation, clamped to 0..1.
	var cutoff_norm: float = clampf(p.filter_cutoff + p.filter_env_amount * v.fenv_value, 0.0, 1.0)
	# Log-map 0..1 to ~20 Hz..~mix_rate/2.2.
	var freq: float = 20.0 * pow(1000.0, cutoff_norm)
	freq = minf(freq, mix_rate * 0.45)
	var g: float = tan(PI * freq / mix_rate)
	# Quadratic ramp on resonance for a more natural feel.
	var q_val: float = 0.5 + p.filter_resonance * p.filter_resonance * 19.5
	var k: float = 1.0 / q_val
	v.svf_a1 = 1.0 / (1.0 + g * (g + k))
	v.svf_a2 = g * v.svf_a1
	v.svf_a3 = g * v.svf_a2
	v.svf_k = k

func _render_voice_block(v: Voice, frames: int, dt: float, lfo_base: float) -> void:
	var p: SynthPatch = v.patch
	if p == null:
		return
	var base: int = v.channel * frames

	# --- Per-buffer invariants (hoisted out of the per-sample loop) ------
	# Pan gains and the constant part of the amp scale never change within a
	# buffer; the only per-sample amp factor is env_value.
	var l_gain: float = 1.0 - maxf(v.pan, 0.0)
	var r_gain: float = 1.0 + minf(v.pan, 0.0)
	var amp_scale: float = v.velocity * p.gain * v.loudness_comp

	# Feature flags decided once per buffer so disabled features cost nothing
	# per sample.
	var has_filter: bool = p.filter_type != SynthPatch.FilterType.OFF
	var filter_type: int = p.filter_type
	var has_fm: bool = p.fm_index > 0.0
	var has_vibrato: bool = p.vibrato_depth_cents > 0.0 and p.vibrato_rate > 0.0
	var has_pitch_decay: bool = p.pitch_decay_semitones > 0.0 and p.pitch_decay_time > 0.0
	var has_noise: bool = p.noise_mix > 0.0
	var noise_full: bool = p.noise_mix >= 1.0
	var dv: int = p.detune_voices
	var inv_count: float = 1.0 / float(dv) if dv > 1 else 1.0
	# Unison detune ratios are constant across the buffer (depend only on dv and
	# detune_cents), so compute the pow() once here instead of per sample per
	# unison voice — a real saving on fat/detuned patches.
	if dv > 1:
		if _detune_ratios.size() != dv:
			_detune_ratios.resize(dv)
		for j in dv:
			var jt: float = float(j) / float(dv - 1)
			var jcents: float = lerpf(-p.detune_cents, p.detune_cents, jt)
			_detune_ratios[j] = pow(2.0, jcents / 1200.0)

	# SVF coefficients: once per buffer (uses fenv_value carried from the prior
	# buffer's end), matching the original cadence — the filter cutoff envelope
	# is already control-rate at the coefficient level.
	if has_filter:
		_update_svf_coefs(v, p)

	var lfo_t: float = lfo_base
	for i in frames:
		lfo_t += dt

		# --- Amp envelope -----------------------------------------------
		match v.env_state:
			ENV_ATTACK:
				if p.attack <= 0.0:
					v.env_value = 1.0
					v.env_state = ENV_DECAY
				else:
					v.env_value += dt / p.attack
					if v.env_value >= 1.0:
						v.env_value = 1.0
						v.env_state = ENV_DECAY
			ENV_DECAY:
				if p.decay <= 0.0:
					v.env_value = p.sustain
					v.env_state = ENV_SUSTAIN
				else:
					v.env_value -= dt * (1.0 - p.sustain) / p.decay
					if v.env_value <= p.sustain:
						v.env_value = p.sustain
						v.env_state = ENV_SUSTAIN
			ENV_SUSTAIN:
				pass
			ENV_RELEASE:
				if p.release <= 0.0:
					v.env_value = 0.0
				else:
					v.env_value -= dt * v.release_start / p.release
				if v.env_value <= 0.0:
					# Voice died mid-buffer; remaining samples stay zero.
					v.active = false
					return

		# --- Filter envelope (only when filter is enabled) --------------
		if has_filter:
			match v.fenv_state:
				ENV_ATTACK:
					if p.filter_attack <= 0.0:
						v.fenv_value = 1.0
						v.fenv_state = ENV_DECAY
					else:
						v.fenv_value += dt / p.filter_attack
						if v.fenv_value >= 1.0:
							v.fenv_value = 1.0
							v.fenv_state = ENV_DECAY
				ENV_DECAY:
					if p.filter_decay <= 0.0:
						v.fenv_value = p.filter_sustain
						v.fenv_state = ENV_SUSTAIN
					else:
						v.fenv_value -= dt * (1.0 - p.filter_sustain) / p.filter_decay
						if v.fenv_value <= p.filter_sustain:
							v.fenv_value = p.filter_sustain
							v.fenv_state = ENV_SUSTAIN
				ENV_SUSTAIN:
					pass
				ENV_RELEASE:
					if p.filter_release <= 0.0:
						v.fenv_value = 0.0
					else:
						v.fenv_value -= dt * v.fenv_release_start / p.filter_release
					if v.fenv_value < 0.0:
						v.fenv_value = 0.0

		# --- Pitch glide (bend) -----------------------------------------
		# Mutates the voice's base freq in place so subsequent vibrato +
		# pitch_decay modulators stack on top of the gliding pitch.
		if v.glide_samples_left > 0:
			v.freq *= v.glide_factor
			v.glide_samples_left -= 1
			if v.glide_samples_left == 0:
				v.freq = v.glide_target_freq

		# --- Pitch + vibrato + pitch envelope ----------------------------
		var freq := v.freq
		if has_vibrato:
			var lfo := sin(lfo_t * TAU * p.vibrato_rate)
			freq *= pow(2.0, (lfo * p.vibrato_depth_cents) / 1200.0)
		if has_pitch_decay:
			var t: float = clampf(v.pitch_time / p.pitch_decay_time, 0.0, 1.0)
			var semis: float = p.pitch_decay_semitones * (1.0 - t)
			freq *= pow(2.0, semis / 12.0)
			v.pitch_time += dt

		# --- FM modulator (single operator, sine modulator) -------------
		var fm_offset: float = 0.0
		if has_fm:
			var mod_freq: float = freq * p.fm_ratio
			v.mod_phase += mod_freq * dt
			if v.mod_phase >= 1.0:
				v.mod_phase -= floor(v.mod_phase)
			fm_offset = sin(v.mod_phase * TAU) * p.fm_index

		# --- Oscillator (mono or detuned unison) ------------------------
		var sample := 0.0
		if dv <= 1:
			sample = p.sample(fposmod(v.phase + fm_offset, 1.0))
			v.phase += freq * dt
			if v.phase >= 1.0:
				v.phase -= floor(v.phase)
		else:
			for j in dv:
				var f: float = freq * _detune_ratios[j]
				sample += p.sample(fposmod(v.detune_phase[j] + fm_offset, 1.0))
				var ph: float = v.detune_phase[j] + f * dt
				if ph >= 1.0:
					ph -= floor(ph)
				v.detune_phase[j] = ph
			sample *= inv_count

		# --- Noise (filtered, with independent decay envelope) ----------
		if has_noise:
			var noise: float = _rng.randf() * 2.0 - 1.0
			if p.noise_lowpass < 1.0:
				v.noise_lp_state += p.noise_lowpass * (noise - v.noise_lp_state)
				noise = v.noise_lp_state
			if p.noise_highpass > 0.0:
				v.noise_hp_state += p.noise_highpass * (noise - v.noise_hp_state)
				noise -= v.noise_hp_state
			if p.noise_decay > 0.0 and v.noise_env > 0.0:
				v.noise_env -= dt / p.noise_decay
				if v.noise_env < 0.0:
					v.noise_env = 0.0
			if noise_full:
				sample = noise * v.noise_env
			else:
				sample = sample * (1.0 - p.noise_mix) + noise * p.noise_mix * v.noise_env

		# --- Resonant SVF filter ----------------------------------------
		if has_filter:
			var v3: float = sample - v.svf_ic2
			var v1: float = v.svf_a1 * v.svf_ic1 + v.svf_a2 * v3
			var v2: float = v.svf_ic2 + v.svf_a2 * v.svf_ic1 + v.svf_a3 * v3
			v.svf_ic1 = 2.0 * v1 - v.svf_ic1
			v.svf_ic2 = 2.0 * v2 - v.svf_ic2
			match filter_type:
				SynthPatch.FilterType.LOWPASS:
					sample = v2
				SynthPatch.FilterType.HIGHPASS:
					sample = sample - v.svf_k * v1 - v2
				SynthPatch.FilterType.BANDPASS:
					sample = v1

		sample *= v.env_value * amp_scale

		_mix_l[base + i] += sample * l_gain
		_mix_r[base + i] += sample * r_gain
