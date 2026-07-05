class_name PatternNote
extends Resource

# One note within a MusicPattern. Interpretation of `index` depends on the
# owning MusicTrack's type:
#   CHORD  — chord tone index (0 = root, 1 = third, 2 = fifth, ...)
#   MELODY — scale degree (0-based)
#   DRUM   — absolute MIDI note number

## When this note triggers within the pattern, in beats from the start.
## 0 = downbeat, 0.5 = and-of-1, 0.25 = 16th-note "e", etc.
@export var beat: float = 0.0

## How long the note sustains, in beats. Note-off fires after this elapses
## (regardless of pattern wraparound or block changes).
@export var duration: float = 1.0

## Meaning depends on the owning MusicTrack's type:
## [br]• CHORD — chord tone index (0 = root, 1 = third, 2 = fifth, ...)
## [br]• MELODY — 0-based scale degree
## [br]• DRUM — absolute MIDI note number (36 = C2 kick, 38 = snare, 42 = hi-hat)
@export var index: int = 0

## Octave offset added to the resolved MIDI note. Stacks with the track's
## [member MusicTrack.base_octave]. Ignored for DRUM tracks.
@export var octave: int = 0

## Chromatic alteration in semitones (melody only). +1 raises, -1 lowers.
## Float so microtonal targets are expressible (e.g. 0.5 = quarter-tone).
## Enables chromatic passing tones without switching scales.
@export var accidental: float = 0.0

## Note velocity (0..1), forwarded to SynthEngine as the attack amplitude.
@export_range(0.0, 1.0) var velocity: float = 0.8

## Pitch glides chained off this note. Each fires at its own scheduled
## time and commands the live voice to slide to a new pitch. See
## [PatternBend].
@export var bends: Array[PatternBend] = []

static func create(p_beat: float, p_dur: float, p_index: int, p_oct: int = 0, p_acc: float = 0.0, p_vel: float = 0.8) -> PatternNote:
	var n := PatternNote.new()
	n.beat = p_beat
	n.duration = p_dur
	n.index = p_index
	n.octave = p_oct
	n.accidental = p_acc
	n.velocity = p_vel
	return n
