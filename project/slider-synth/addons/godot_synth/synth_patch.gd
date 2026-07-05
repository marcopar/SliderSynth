class_name SynthPatch
extends Resource

# Designer-facing instrument definition. Builds a single-cycle wavetable from
# additive harmonics on init so the engine's per-sample work is just a table
# lookup instead of N sin() calls.

enum Waveform { ADDITIVE, SINE, SQUARE, SAW, TRIANGLE }
enum FilterType { OFF, LOWPASS, HIGHPASS, BANDPASS }

## Human-readable label for this patch. Shown in the patch editor UI and
## used as the default filename when saving.
@export var patch_name: String = "Patch"

@export_group("Oscillator")

## Base waveform. ADDITIVE uses the [member harmonics] array; the others
## are fixed analytic shapes (sine, square, saw, triangle). Changing this
## at runtime rebuilds the wavetable automatically.
@export var waveform: Waveform = Waveform.ADDITIVE:
	set(value):
		waveform = value
		if _table.size() == TABLE_SIZE:
			rebuild()

## Amplitudes per harmonic partial when [member waveform] is ADDITIVE.
## Index 0 = fundamental, 1 = 2nd partial, etc. Values are summed as sine
## waves at integer multiples of the fundamental (or [member harmonic_ratios]
## if provided) and normalized to peak 1.0. Setter rebuilds the wavetable.
@export var harmonics: PackedFloat32Array = PackedFloat32Array([1.0, 0.5, 0.25, 0.125]):
	set(value):
		harmonics = value
		if _table.size() == TABLE_SIZE:
			rebuild()

## Optional inharmonic frequency ratios per partial (parallel to [member harmonics]).
## Zero or missing entries fall back to integer multiples (1, 2, 3, ...).
## Use e.g. [1.0, 2.76, 5.4, 8.93] for bell-like FM ratios.
@export var harmonic_ratios: PackedFloat32Array = PackedFloat32Array():
	set(value):
		harmonic_ratios = value
		if _table.size() == TABLE_SIZE:
			rebuild()

@export_group("Envelope (ADSR)")

## Seconds to ramp from silence to peak amplitude after note-on.
@export var attack: float = 0.01

## Seconds to decay from peak to [member sustain] level.
@export var decay: float = 0.10

## Held amplitude level (0..1) while the note is active. Reached after decay.
@export_range(0.0, 1.0) var sustain: float = 0.7

## Seconds to fade to silence after note-off.
@export var release: float = 0.20

@export_group("Filter & Gain")

## Per-patch output level. Stacks with [SynthEngine.master_gain].
@export var gain: float = 0.5

@export_group("Unison / Detune")

## Stack N detuned copies of the oscillator per note for chorus / fatness.
## 1 = single voice (cheapest). Higher values cost proportionally more CPU.
@export_range(1, 4) var detune_voices: int = 1

## Maximum spread between stacked voices, in cents (1 cent = 1/100 semitone).
## Voices are distributed linearly from -detune_cents to +detune_cents.
@export var detune_cents: float = 6.0

@export_group("Vibrato")

## Vibrato LFO rate in Hz. 0 disables vibrato.
@export var vibrato_rate: float = 0.0

## Vibrato pitch-modulation depth in cents. 100 cents = one semitone.
@export var vibrato_depth_cents: float = 0.0

@export_group("Humanization")

## Maximum random pitch deviation applied on every note_on, in cents.
## 0 disables. Good for repeated SFX so successive plays don't sound
## identical. ~10-20 cents is subtle; 50+ is obvious detuning.
@export var pitch_randomize_cents: float = 0.0

## Maximum velocity reduction applied on every note_on, 0..1. 0 disables;
## 0.2 = velocity varies down to 80% of requested.
@export_range(0.0, 1.0) var velocity_randomize: float = 0.0

@export_group("FM")

## Modulator frequency as a ratio of the carrier (1.0 = same freq,
## 2.0 = octave above, 0.5 = octave below). Non-integer ratios give
## inharmonic / bell-like timbres.
@export var fm_ratio: float = 1.0

## Modulation index — how much the modulator bends the carrier's phase.
## 0 disables FM entirely (zero CPU cost). 0.1-0.3 = subtle warmth,
## 0.5-2.0 = clear FM character, 3.0+ = noisy/metallic.
@export var fm_index: float = 0.0

@export_group("Resonant Filter")

## Filter type for the second-stage state-variable filter. OFF bypasses
## it entirely (no CPU cost). LOWPASS/HIGHPASS/BANDPASS enable it with
## resonance and optional envelope modulation.
@export var filter_type: FilterType = FilterType.OFF

## Base cutoff frequency, normalized 0..1 (log-mapped to ~20 Hz..~10 kHz).
## The effective cutoff is this plus [member filter_env_amount] * env.
@export_range(0.0, 1.0) var filter_cutoff: float = 0.7

## Filter resonance / Q. 0 = gentle slope, 1 = self-oscillating edge.
## High values can clip; reduce [member gain] accordingly.
@export_range(0.0, 1.0) var filter_resonance: float = 0.0

## Envelope-to-cutoff modulation amount. Positive values open the filter
## on note-on; negative values close it. Scaled so ±1 = full range.
@export_range(-1.0, 1.0) var filter_env_amount: float = 0.0

## Filter envelope attack time in seconds.
@export var filter_attack: float = 0.01

## Filter envelope decay time in seconds.
@export var filter_decay: float = 0.10

## Filter envelope sustain level (0..1).
@export_range(0.0, 1.0) var filter_sustain: float = 0.5

## Filter envelope release time in seconds.
@export var filter_release: float = 0.20

@export_group("Drum / Percussion")

## Blend between the oscillator (0) and white noise (1). Essential for
## snare, hi-hat, and cymbal patches. Set to 1 for pure noise.
@export_range(0.0, 1.0) var noise_mix: float = 0.0

## Independent noise decay in seconds. When > 0, noise fades out
## exponentially on its own clock (snappy drum transient over sustained
## body). When 0, noise follows the amp envelope (legacy behavior).
@export var noise_decay: float = 0.0

## One-pole lowpass applied only to the noise source before it's mixed
## with the oscillator. 1.0 = no filter; lower values muffle (dull hat).
@export_range(0.0, 1.0) var noise_lowpass: float = 1.0

## One-pole highpass applied only to the noise source. 0.0 = no filter;
## higher values remove rumble (crisp hi-hat, ride shimmer).
@export_range(0.0, 1.0) var noise_highpass: float = 0.0

## Pitch envelope amount in semitones. On note-on the pitch starts this
## many semitones above the MIDI note and falls to the note over
## [member pitch_decay_time]. Used for kick drums (~48 semi) and toms.
## 0 disables the pitch envelope.
@export var pitch_decay_semitones: float = 0.0

## Duration (seconds) for the pitch envelope to reach the target note.
## Short values (~0.05-0.1s) give the characteristic kick "thump."
@export var pitch_decay_time: float = 0.0

const TABLE_SIZE: int = 2048

var _table: PackedFloat32Array

func _init() -> void:
	rebuild()

func rebuild() -> void:
	_table = PackedFloat32Array()
	_table.resize(TABLE_SIZE)
	var peak := 0.0
	for i in TABLE_SIZE:
		var phase := float(i) / float(TABLE_SIZE)
		var s := 0.0
		match waveform:
			Waveform.SINE:
				s = sin(phase * TAU)
			Waveform.SQUARE:
				s = 1.0 if phase < 0.5 else -1.0
			Waveform.SAW:
				s = phase * 2.0 - 1.0
			Waveform.TRIANGLE:
				s = 4.0 * absf(phase - 0.5) - 1.0
			_: # ADDITIVE
				for h in harmonics.size():
					var amp: float = harmonics[h]
					if amp == 0.0:
						continue
					var ratio: float = float(h + 1)
					if h < harmonic_ratios.size() and harmonic_ratios[h] > 0.0:
						ratio = harmonic_ratios[h]
					s += sin(phase * TAU * ratio) * amp
		_table[i] = s
		var a := absf(s)
		if a > peak:
			peak = a
	if peak > 0.0:
		var inv := 1.0 / peak
		for i in TABLE_SIZE:
			_table[i] *= inv

func sample(phase: float) -> float:
	# Linear-interpolated wavetable read. Phase is 0..1.
	var x: float = phase * float(TABLE_SIZE)
	var ix: int = int(x)
	var i0: int = ix % TABLE_SIZE
	var i1: int = (i0 + 1) % TABLE_SIZE
	var frac: float = x - float(ix)
	return _table[i0] + (_table[i1] - _table[i0]) * frac

# --- Factory helpers for common timbres ---------------------------------

static func make_organ() -> SynthPatch:
	var p := SynthPatch.new()
	p.patch_name = "Organ"
	p.harmonics = PackedFloat32Array([1.0, 0.8, 0.6, 0.5, 0.4, 0.3, 0.2, 0.15])
	p.attack = 0.02
	p.decay = 0.05
	p.sustain = 0.9
	p.release = 0.15
	p.gain = 0.35
	p.rebuild()
	return p

static func make_clarinet() -> SynthPatch:
	var p := SynthPatch.new()
	p.patch_name = "Clarinet"
	# Odd harmonics only — square-ish but softened.
	p.harmonics = PackedFloat32Array([1.0, 0.0, 0.7, 0.0, 0.4, 0.0, 0.25, 0.0, 0.15])
	p.attack = 0.04
	p.decay = 0.1
	p.sustain = 0.85
	p.release = 0.2
	p.filter_type = FilterType.LOWPASS
	p.filter_cutoff = 0.7354
	p.gain = 0.4
	p.rebuild()
	return p

static func make_bell() -> SynthPatch:
	var p := SynthPatch.new()
	p.patch_name = "Bell"
	p.harmonics = PackedFloat32Array([1.0, 0.6, 0.4, 0.25, 0.18])
	# Inharmonic partials — classic FM-bell ratios.
	p.harmonic_ratios = PackedFloat32Array([1.0, 2.76, 5.40, 8.93, 13.34])
	p.attack = 0.001
	p.decay = 1.5
	p.sustain = 0.0
	p.release = 0.8
	p.gain = 0.45
	p.rebuild()
	return p

static func make_pad() -> SynthPatch:
	var p := SynthPatch.new()
	p.patch_name = "Pad"
	p.harmonics = PackedFloat32Array([1.0, 0.4, 0.5, 0.2, 0.3, 0.15, 0.2, 0.1])
	p.attack = 0.6
	p.decay = 0.4
	p.sustain = 0.8
	p.release = 1.2
	p.filter_type = FilterType.LOWPASS
	p.filter_cutoff = 0.6508
	p.detune_voices = 3
	p.detune_cents = 8.0
	p.vibrato_rate = 4.5
	p.vibrato_depth_cents = 6.0
	p.gain = 0.3
	p.rebuild()
	return p

static func make_bass() -> SynthPatch:
	var p := SynthPatch.new()
	p.patch_name = "Bass"
	p.harmonics = PackedFloat32Array([1.0, 0.5, 0.33, 0.25, 0.2, 0.16, 0.14, 0.12])
	p.attack = 0.005
	p.decay = 0.2
	p.sustain = 0.6
	p.release = 0.1
	p.filter_type = FilterType.LOWPASS
	p.filter_cutoff = 0.6262
	p.gain = 0.5
	p.rebuild()
	return p

# --- Drum presets -----------------------------------------------------------

static func make_kick() -> SynthPatch:
	var p := SynthPatch.new()
	p.patch_name = "Kick"
	p.waveform = Waveform.SINE
	p.attack = 0.001
	p.decay = 0.25
	p.sustain = 0.0
	p.release = 0.05
	p.pitch_decay_semitones = 48.0
	p.pitch_decay_time = 0.08
	p.gain = 0.6
	p.rebuild()
	return p

static func make_snare() -> SynthPatch:
	var p := SynthPatch.new()
	p.patch_name = "Snare"
	p.waveform = Waveform.TRIANGLE
	p.noise_mix = 0.7
	p.attack = 0.001
	p.decay = 0.15
	p.sustain = 0.0
	p.release = 0.05
	p.pitch_decay_semitones = 24.0
	p.pitch_decay_time = 0.04
	p.filter_type = FilterType.LOWPASS
	p.filter_cutoff = 0.695
	p.gain = 0.5
	p.rebuild()
	return p

static func make_hihat() -> SynthPatch:
	var p := SynthPatch.new()
	p.patch_name = "Hi-Hat"
	p.waveform = Waveform.SINE
	p.noise_mix = 1.0
	p.attack = 0.001
	p.decay = 0.06
	p.sustain = 0.0
	p.release = 0.03
	p.filter_type = FilterType.LOWPASS
	p.filter_cutoff = 0.7749
	p.gain = 0.35
	p.rebuild()
	return p

# --- FM presets -------------------------------------------------------------

static func make_fm_bell() -> SynthPatch:
	var p := SynthPatch.new()
	p.patch_name = "FM Bell"
	p.waveform = Waveform.SINE
	p.fm_ratio = 3.5
	p.fm_index = 1.4
	p.attack = 0.001
	p.decay = 1.8
	p.sustain = 0.0
	p.release = 0.8
	p.gain = 0.4
	p.rebuild()
	return p

static func make_fm_epiano() -> SynthPatch:
	var p := SynthPatch.new()
	p.patch_name = "FM EPiano"
	p.waveform = Waveform.SINE
	p.fm_ratio = 14.0
	p.fm_index = 0.35
	p.attack = 0.002
	p.decay = 0.6
	p.sustain = 0.35
	p.release = 0.4
	p.gain = 0.45
	p.rebuild()
	return p

static func make_fm_clang() -> SynthPatch:
	var p := SynthPatch.new()
	p.patch_name = "FM Clang"
	p.waveform = Waveform.SINE
	p.fm_ratio = 2.47
	p.fm_index = 3.0
	p.attack = 0.001
	p.decay = 0.5
	p.sustain = 0.0
	p.release = 0.2
	p.pitch_decay_semitones = 18.0
	p.pitch_decay_time = 0.06
	p.gain = 0.35
	p.rebuild()
	return p

# --- Resonant-filter presets -----------------------------------------------

static func make_acid_bass() -> SynthPatch:
	var p := SynthPatch.new()
	p.patch_name = "Acid Bass"
	p.waveform = Waveform.SAW
	p.attack = 0.002
	p.decay = 0.15
	p.sustain = 0.5
	p.release = 0.08
	p.filter_type = FilterType.LOWPASS
	p.filter_cutoff = 0.28
	p.filter_resonance = 0.82
	p.filter_env_amount = 0.55
	p.filter_attack = 0.005
	p.filter_decay = 0.25
	p.filter_sustain = 0.0
	p.filter_release = 0.15
	p.gain = 0.45
	p.rebuild()
	return p

static func make_filter_pluck() -> SynthPatch:
	var p := SynthPatch.new()
	p.patch_name = "Filter Pluck"
	p.waveform = Waveform.SQUARE
	p.attack = 0.001
	p.decay = 0.2
	p.sustain = 0.0
	p.release = 0.1
	p.filter_type = FilterType.LOWPASS
	p.filter_cutoff = 0.25
	p.filter_resonance = 0.5
	p.filter_env_amount = 0.6
	p.filter_attack = 0.001
	p.filter_decay = 0.15
	p.filter_sustain = 0.0
	p.gain = 0.4
	p.rebuild()
	return p

static func make_sweep_sfx() -> SynthPatch:
	var p := SynthPatch.new()
	p.patch_name = "Sweep SFX"
	p.waveform = Waveform.SAW
	p.attack = 0.001
	p.decay = 0.6
	p.sustain = 0.0
	p.release = 0.2
	p.filter_type = FilterType.LOWPASS
	p.filter_cutoff = 0.1
	p.filter_resonance = 0.7
	p.filter_env_amount = 0.85
	p.filter_attack = 0.4
	p.filter_decay = 0.5
	p.filter_sustain = 0.0
	p.gain = 0.35
	p.rebuild()
	return p

# --- Drum presets using the new noise features -----------------------------

static func make_snare_snappy() -> SynthPatch:
	var p := SynthPatch.new()
	p.patch_name = "Snare Snappy"
	p.waveform = Waveform.TRIANGLE
	p.noise_mix = 0.75
	p.noise_decay = 0.09
	p.noise_lowpass = 0.55
	p.noise_highpass = 0.35
	p.attack = 0.001
	p.decay = 0.2
	p.sustain = 0.0
	p.release = 0.05
	p.pitch_decay_semitones = 18.0
	p.pitch_decay_time = 0.03
	p.gain = 0.5
	p.rebuild()
	return p

static func make_hihat_open() -> SynthPatch:
	var p := SynthPatch.new()
	p.patch_name = "Hi-Hat Open"
	p.waveform = Waveform.SINE
	p.noise_mix = 1.0
	p.noise_decay = 0.35
	p.noise_highpass = 0.65
	p.attack = 0.001
	p.decay = 0.4
	p.sustain = 0.0
	p.release = 0.2
	p.gain = 0.3
	p.rebuild()
	return p

static func make_cymbal_crash() -> SynthPatch:
	var p := SynthPatch.new()
	p.patch_name = "Cymbal Crash"
	p.waveform = Waveform.SINE
	p.noise_mix = 1.0
	p.noise_decay = 1.5
	p.noise_highpass = 0.8
	p.attack = 0.001
	p.decay = 1.2
	p.sustain = 0.0
	p.release = 0.8
	p.gain = 0.28
	p.rebuild()
	return p
