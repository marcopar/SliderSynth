class_name PatternBend
extends Resource

# A pitch-glide command attached to a PatternNote (or another PatternBend).
# Authored as a chain: a note can carry an Array[PatternBend], and each bend
# can carry its own children to compose multi-segment slides.
#
# Runtime semantics:
#   - A bend does NOT trigger a new voice. It commands the parent's existing
#     voice to glide its pitch from wherever it is NOW to a target frequency
#     over [member glide_beats]. The glide is exponential (log-frequency
#     linear), so it sounds musical regardless of interval size.
#   - [member offset_beats] is relative to the *parent's start beat* (the
#     parent note's `beat`, or the parent bend's fire time). Nested bends
#     fire on their own schedule — they don't wait for the parent's glide
#     to complete.
#   - When the parent note releases, any still-pending bends for that voice
#     are cancelled.
#
# Target pitch is fully resolved against the track's current block (chord /
# scale), exactly like a PatternNote. Use [member accidental] (float) for
# microtonal targets — fractional values are honored end-to-end.

## When this bend fires, in beats from the parent's start beat. 0 = bend
## starts at the same instant as the parent's note-on.
@export var offset_beats: float = 0.0

## How long the glide takes, in beats. 0 = instant snap to target.
@export var glide_beats: float = 0.25

## Target pitch index. Interpretation matches the owning MusicTrack:
## CHORD = chord tone index, MELODY = scale degree, DRUM = absolute MIDI.
@export var index: int = 0

## Octave offset added to the resolved target. Stacks with the track's
## [member MusicTrack.base_octave]. Ignored for DRUM tracks.
@export var octave: int = 0

## Chromatic alteration in semitones (MELODY only). Float — fractional
## values give microtonal targets (e.g. 0.5 = quarter-tone above the
## scale degree).
@export var accidental: float = 0.0

## Further bends chained off this one. Each child's [member offset_beats]
## is relative to *this* bend's start, not the parent note's start —
## so chaining is additive.
@export var bends: Array[PatternBend] = []

static func create(p_offset: float, p_glide: float, p_index: int, p_oct: int = 0, p_acc: float = 0.0) -> PatternBend:
	var b := PatternBend.new()
	b.offset_beats = p_offset
	b.glide_beats = p_glide
	b.index = p_index
	b.octave = p_oct
	b.accidental = p_acc
	return b
