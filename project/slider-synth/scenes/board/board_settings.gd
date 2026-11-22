extends Control

class_name BoardSettings

@onready var first_octave: SliderControl = $MainMargin/InternalMargin/VBoxContainer/GridContainer/FirstOctave
@onready var number_of_octaves: SliderControl = $MainMargin/InternalMargin/VBoxContainer/GridContainer/NumberOfOctaves
@onready var attack: SliderControl = $MainMargin/InternalMargin/VBoxContainer/GridContainer/Attack
@onready var decay: SliderControl = $MainMargin/InternalMargin/VBoxContainer/GridContainer/Decay
@onready var sustain: SliderControl = $MainMargin/InternalMargin/VBoxContainer/GridContainer/Sustain
@onready var release: SliderControl = $MainMargin/InternalMargin/VBoxContainer/GridContainer/Release
@onready var sine_button: Button = $MainMargin/InternalMargin/VBoxContainer/HBoxContainer/SineButton
@onready var square_button: Button = $MainMargin/InternalMargin/VBoxContainer/HBoxContainer/SquareButton
@onready var triangle_button: Button = $MainMargin/InternalMargin/VBoxContainer/HBoxContainer/TriangleButton
@onready var sawtooth_button: Button = $MainMargin/InternalMargin/VBoxContainer/HBoxContainer/SawtoothButton
@onready var border_color_rect: ColorRect = $MainMargin/BorderColor


@export
var board: Board:
	set(new_board):
		board = new_board
	get:
		return board

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	border_color_rect.color = board.border_color
	set_settings_values()

func set_board_values() -> void:
	if sine_button.button_pressed:
		board.waveform = SynthVoice.Waveform.SINE
	if square_button.button_pressed:
		board.waveform = SynthVoice.Waveform.SQUARE
	if triangle_button.button_pressed:
		board.waveform = SynthVoice.Waveform.TRIANGLE
	if sawtooth_button.button_pressed:
		board.waveform = SynthVoice.Waveform.SAWTOOTH
			
	board.first_octave = int(first_octave.slider.value)
	board.number_of_octaves = int(number_of_octaves.slider.value)
	board.attack = attack.slider.value
	board.decay = decay.slider.value
	board.sustain = sustain.slider.value / 100.0
	board.release = release.slider.value
	board.build_voices()

func set_settings_values() -> void:
	match(board.waveform):
		SynthVoice.Waveform.SINE:
			sine_button.button_pressed = true
			pass
		SynthVoice.Waveform.SQUARE:
			square_button.button_pressed = true
			pass
		SynthVoice.Waveform.TRIANGLE:
			triangle_button.button_pressed = true
			pass
		SynthVoice.Waveform.SAWTOOTH:
			sawtooth_button.button_pressed = true
			pass
	first_octave.slider.value = board.first_octave
	number_of_octaves.slider.value = board.number_of_octaves
	attack.slider.value = board.attack
	decay.slider.value = board.decay
	sustain.slider.value = board.sustain * 100.0
	release.slider.value = board.release

func _on_close_button_pressed() -> void:
	set_board_values()
	queue_free()
