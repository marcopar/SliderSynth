extends Control

class_name Board

@onready var border: ColorRect = $Border
@onready var main_area: ColorRect = $Border/MarginContainer/MainArea
@onready var label: Label = $Border/MarginContainer/MainArea/Label

var synth: MiniSynth
var voice: SynthVoice

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
	synth = MiniSynth.new()
	add_child(synth)
	voice = synth.create_voice()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func calculate_frequency(x: float) -> float:
	return 32.7032 * pow(2.0, first_octave - 1 + (x / main_area.size.x) * number_of_octaves)

func _on_main_area_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touchEvent: InputEventScreenTouch = event
		if touchEvent.pressed:
			var frequency: float = calculate_frequency(touchEvent.position.x)
			voice.note_on(frequency)
			label.text = "%f" % frequency
		else:
			voice.note_off()
	if event is InputEventScreenDrag:
		var dragEvent: InputEventScreenDrag = event
		var frequency: float = calculate_frequency(dragEvent.position.x)
		voice.sweep_to(frequency, 0.01)
		label.text = "%f" % frequency
