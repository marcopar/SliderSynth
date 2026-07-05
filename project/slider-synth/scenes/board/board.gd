extends Control

class_name Board

@onready var border: ColorRect = $Border
@onready var main_area: ColorRect = $Border/MarginContainer/MainArea

var synth: SynthEngine
@export
var patch: SynthPatch
var current_i_note: int

@export
var border_color: Color
@export
var main_area_color: Color
@export
var first_octave: int = 4
@export
var number_of_octaves: int = 2

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	border.color = border_color
	main_area.color = main_area_color
	
	synth = SynthEngine.new()
	synth.set_patch(0, patch)
	add_child(synth)
	

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func calculate_f_note(x: float) -> float:
	var semi: float = x / main_area.size.x * number_of_octaves * 12
	return minf(12 * (first_octave + 1) + semi, 127)

func _on_main_area_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touchEvent: InputEventScreenTouch = event
		if touchEvent.pressed:
			var note: float = calculate_f_note(touchEvent.position.x)
			current_i_note = roundi(note)
			synth.note_on(0, note)
		else:
			synth.note_off(0, current_i_note)
	if event is InputEventScreenDrag:
		var dragEvent: InputEventScreenDrag = event
		var new_note: float = calculate_f_note(dragEvent.position.x)
		var target_freq: float = 440.0 * pow(2.0, (new_note - 69.0) / 12.0)
		synth.bend_to(0, current_i_note, target_freq, 0.01)
