class_name MusicData
extends Resource

# A song or theme for the dynamic music system. Holds a BPM and a
# progression of MusicBlocks. Save as .tres to reuse across scenes.
#
# Scale and chord interval presets live here as static vars for convenience
# when building blocks in code.

# --- Note name helpers (semitone offsets from C) ----------------------------

const C  := 0
const Cs := 1
const Db := 1
const D  := 2
const Ds := 3
const Eb := 3
const E  := 4
const F  := 5
const Fs := 6
const Gb := 6
const G  := 7
const Gs := 8
const Ab := 8
const A  := 9
const As := 10
const Bb := 10
const B  := 11

# --- Scale interval presets -------------------------------------------------

static var MAJOR: PackedInt32Array         = PackedInt32Array([0, 2, 4, 5, 7, 9, 11])
static var MINOR: PackedInt32Array         = PackedInt32Array([0, 2, 3, 5, 7, 8, 10])
static var DORIAN: PackedInt32Array        = PackedInt32Array([0, 2, 3, 5, 7, 9, 10])
static var PHRYGIAN: PackedInt32Array      = PackedInt32Array([0, 1, 3, 5, 7, 8, 10])
static var LYDIAN: PackedInt32Array        = PackedInt32Array([0, 2, 4, 6, 7, 9, 11])
static var MIXOLYDIAN: PackedInt32Array    = PackedInt32Array([0, 2, 4, 5, 7, 9, 10])
static var AEOLIAN: PackedInt32Array       = PackedInt32Array([0, 2, 3, 5, 7, 8, 10])
static var PENTA_MAJOR: PackedInt32Array   = PackedInt32Array([0, 2, 4, 7, 9])
static var PENTA_MINOR: PackedInt32Array   = PackedInt32Array([0, 3, 5, 7, 10])
static var BLUES: PackedInt32Array         = PackedInt32Array([0, 3, 5, 6, 7, 10])
static var CHROMATIC: PackedInt32Array     = PackedInt32Array([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11])

# --- Chord interval presets -------------------------------------------------

static var CHORD_MAJ: PackedInt32Array  = PackedInt32Array([0, 4, 7])
static var CHORD_MIN: PackedInt32Array  = PackedInt32Array([0, 3, 7])
static var CHORD_DIM: PackedInt32Array  = PackedInt32Array([0, 3, 6])
static var CHORD_AUG: PackedInt32Array  = PackedInt32Array([0, 4, 8])
static var CHORD_MAJ7: PackedInt32Array = PackedInt32Array([0, 4, 7, 11])
static var CHORD_MIN7: PackedInt32Array = PackedInt32Array([0, 3, 7, 10])
static var CHORD_DOM7: PackedInt32Array = PackedInt32Array([0, 4, 7, 10])
static var CHORD_SUS2: PackedInt32Array = PackedInt32Array([0, 2, 7])
static var CHORD_SUS4: PackedInt32Array = PackedInt32Array([0, 5, 7])

# --- Fields -----------------------------------------------------------------

## Tempo in beats per minute. Drives [MusicDirector]'s beat clock — all
## MusicPattern timings (beat positions, durations) scale with this.
@export var bpm: float = 120.0

## The chord progression. Blocks cycle in order, looping back to index 0
## after the last block ends. Each block sets the active chord + scale
## for its [member MusicBlock.duration_beats].
@export var blocks: Array[MusicBlock] = []
