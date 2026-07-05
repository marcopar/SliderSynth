class_name MusicDataPlayer
extends Node

# Thin wrapper that pushes a MusicData resource into the global
# MusicDirector (at /root/Music). Useful as a scene-authored source of
# music data per level / area.
#
# This node does NOT manage MusicTracks — tracks are independent and
# wire themselves to the global synth + director directly. Drop a
# MusicDataPlayer in a level scene to set that level's progression /
# bpm, and drop MusicTracks anywhere (they can live as children of this
# node for organization, or elsewhere in the scene tree).

## The MusicData to push into the director (progression + bpm).
@export var music_data: MusicData

## Push and start playback when this node enters the tree.
@export var autoplay: bool = false

## Hot-swap mode used when [method play] is called while the director
## is already playing. IMMEDIATE snaps to the new progression;
## NEXT_BEAT / NEXT_BLOCK defer the swap to a musical boundary.
@export var swap_mode: MusicDirector.SwapMode = MusicDirector.SwapMode.NEXT_BLOCK

## Runtime reference to the global director. Auto-wired from /root/Music
## in [method _ready]; override via [method bind] if your project uses a
## different autoload name.
var director: MusicDirector

func _ready() -> void:
	if director == null:
		director = get_node_or_null("/root/Music") as MusicDirector
	if autoplay:
		play()

## Explicit director assignment for projects that don't use the default
## `/root/Music` autoload name.
func bind(p_director: MusicDirector) -> void:
	director = p_director

## Push [member music_data] to the director. Hot-swaps if already playing;
## starts fresh playback if not.
func play() -> void:
	if director == null or music_data == null:
		push_warning("[MusicDataPlayer] director or music_data missing.")
		return
	if director.playing:
		director.swap_data(music_data, swap_mode)
	else:
		director.data = music_data
		director.play()

## Stop the global director (affects all MusicTracks).
func stop() -> void:
	if director:
		director.stop()

## Swap to a new MusicData using this node's [member swap_mode].
func swap(new_data: MusicData) -> void:
	if director == null:
		return
	music_data = new_data
	if director.playing:
		director.swap_data(new_data, swap_mode)
	else:
		director.data = new_data

func is_playing() -> bool:
	return director != null and director.playing
