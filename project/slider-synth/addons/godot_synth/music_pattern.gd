class_name MusicPattern
extends Resource

# A looping sequence of PatternNotes used by a MusicTrack. Loops
# independently of MusicBlock duration — the pattern cycles every
# length_beats regardless of which chord/scale is currently active.

## How many beats before the pattern loops. Independent of block duration —
## a 2-beat pattern plays twice per 4-beat block; an 8-beat pattern plays
## across two blocks. The pattern never resets on block boundaries.
@export var length_beats: float = 4.0

## The notes in this pattern. Order doesn't matter — notes fire when their
## [member PatternNote.beat] position is reached within the loop.
@export var notes: Array[PatternNote] = []

## Chainable helper for building patterns in code.
func add(p_beat: float, p_dur: float, p_index: int, p_oct: int = 0, p_acc: float = 0.0, p_vel: float = 0.8) -> MusicPattern:
	notes.append(PatternNote.create(p_beat, p_dur, p_index, p_oct, p_acc, p_vel))
	return self
