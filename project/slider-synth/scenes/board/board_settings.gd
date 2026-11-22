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
@onready var echo_delay: SliderControl = $MainMargin/InternalMargin/VBoxContainer/GridContainer/EchoDelay
@onready var echo_feedback: SliderControl = $MainMargin/InternalMargin/VBoxContainer/GridContainer/EchoFeedback
@onready var reverb_room_size: SliderControl = $MainMargin/InternalMargin/VBoxContainer/GridContainer/ReverbRoomSize
@onready var reverb_damping_level: SliderControl = $MainMargin/InternalMargin/VBoxContainer/GridContainer/ReverbDampingLevel


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
	board.sustain = sustain.slider.value
	board.release = release.slider.value
	board.echo_delay = echo_delay.slider.value
	board.echo_feedback = echo_feedback.slider.value
	board.reverb_room_size = reverb_room_size.slider.value
	board.reverb_damping = reverb_damping_level.slider.value
	board.build_voices()
	board.build_effects()

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
	number_of_octaves.slider.max_value = 11 - board.first_octave
	number_of_octaves.slider.value = min(board.number_of_octaves, number_of_octaves.slider.max_value)
	attack.slider.value = board.attack
	decay.slider.value = board.decay
	sustain.slider.value = board.sustain
	release.slider.value = board.release
	echo_delay.slider.value = board.echo_delay
	echo_feedback.slider.value = board.echo_feedback
	reverb_room_size.slider.value = board.reverb_room_size
	reverb_damping_level.slider.value = board.reverb_damping

func _on_close_button_pressed() -> void:
	set_board_values()
	queue_free()


func _on_first_octave_slider_value_changed(value: float) -> void:
	number_of_octaves.slider.max_value = 11 - first_octave.slider.value
	number_of_octaves.slider.value = min(number_of_octaves.slider.value, number_of_octaves.slider.max_value)
