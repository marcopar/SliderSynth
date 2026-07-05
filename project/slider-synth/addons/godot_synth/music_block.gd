class_name MusicBlock
extends Resource

# One slot in a MusicData progression. Defines the chord and scale that are
# active for the block's duration. Tracks read from the block to resolve
# chord tones / scale degrees into MIDI notes.

## Chord root as a semitone offset from C (0=C, 1=C#, ..., 11=B).
## Use [MusicData] constants like [code]MusicData.G[/code] for readability.
@export_range(0, 11) var chord_root: int = 0

## Chord tones as semitone offsets from [member chord_root]. CHORD tracks
## index into this array. Common: [0,4,7] maj, [0,3,7] min, [0,4,7,11] maj7.
## See [MusicData] for CHORD_* presets.
@export var chord_intervals: PackedInt32Array = PackedInt32Array([0, 4, 7])

## Scale root as a semitone offset from C. Usually matches [member chord_root]
## but can differ for modal mixture or slash chords.
@export_range(0, 11) var scale_root: int = 0

## Scale degrees as semitone offsets from [member scale_root]. MELODY tracks
## index into this array. See [MusicData] for MAJOR, MINOR, DORIAN, etc.
@export var scale_intervals: PackedInt32Array = PackedInt32Array([0, 2, 4, 5, 7, 9, 11])

## How long this block lasts before the director advances to the next one.
## Typical: 4 (one measure of 4/4).
@export var duration_beats: int = 4

static func create(
	p_chord_root: int,
	p_chord: PackedInt32Array,
	p_scale_root: int,
	p_scale: PackedInt32Array,
	p_beats: int = 4
) -> MusicBlock:
	var b := MusicBlock.new()
	b.chord_root = p_chord_root
	b.chord_intervals = p_chord
	b.scale_root = p_scale_root
	b.scale_intervals = p_scale
	b.duration_beats = p_beats
	return b
