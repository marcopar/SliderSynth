extends Control

class_name Board

@onready var border: ColorRect = $Border
@onready var main_area: ColorRect = $Border/MarginContainer/MainArea
@onready var label: Label = $Border/MarginContainer/MainArea/Label

var synth: MiniSynth
var voices: Array[SynthVoice] = []
@export
var board_name: String = "GenericBoard"
@export
var border_color: Color
@export
var main_area_color: Color
@export
var waveform: SynthVoice.Waveform = SynthVoice.Waveform.SINE
@export
var first_octave: int = 4
@export
var number_of_octaves: int = 2
@export
var attack: float = 0.1
@export
var decay: float = 0.1
@export
var sustain: float = 0.7
@export
var release: float = 0.1
@export
var echo_delay: float = 0.25
@export
var echo_feedback: float = 0.35
@export
var reverb_room_size: float = 0.5
@export
var reverb_damping: float = 0.5

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	border.color = border_color
	main_area.color = main_area_color
	load_config()
	synth = MiniSynth.new()
	add_child(synth)
	build_voices()
	build_effects()

func build_voices() -> void:
	for v in voices:
		synth.remove_voice(v)
	voices.clear()
	for i in range(10):
		var voice: SynthVoice = synth.create_voice(waveform)
		voice.attack_seconds = attack
		voice.decay_seconds = decay
		voice.sustain_level = sustain
		voice.release_seconds = release
		voices.append(voice)

func build_effects() -> void:
	synth.clear_effects()

	var echo: SynthEcho = synth.create_echo()
	var reverb: SynthReverb = synth.create_reverb()

	if echo_delay == 0:
		echo.enabled = false
	else:
		echo.enabled = true
		echo.delay_seconds = echo_delay
		echo.feedback_level = echo_feedback
		
	if reverb_room_size == 0:
		reverb.enabled = false
	else:
		reverb.enabled = true
		reverb.room_size = reverb_room_size
		reverb.damping_level = reverb_damping
	
	
func calculate_frequency(x: float) -> float:
	return 32.7032 * pow(2.0, first_octave - 1 + (x / main_area.size.x) * number_of_octaves)

func _on_main_area_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touchEvent: InputEventScreenTouch = event
		if touchEvent.pressed:
			var frequency: float = calculate_frequency(touchEvent.position.x)
			voices[touchEvent.index].note_on(frequency)
			label.text = "%.2f" % frequency
		else:
			voices[touchEvent.index].note_off()
	if event is InputEventScreenDrag:
		var dragEvent: InputEventScreenDrag = event
		var frequency: float = calculate_frequency(dragEvent.position.x)
		voices[dragEvent.index].sweep_to(frequency, 0)
		label.text = "%.2f" % frequency

func load_config() -> void:
	var filename: String = "user://%s.cfg" % board_name
	var config_file: ConfigFile = ConfigFile.new()	
	var error: Error = config_file.load(filename)
	
	if error != OK:
		print("Settings file error, creating default config")
		config_file.save(filename)
		error = config_file.load(filename)
		if error != OK:
			print("Settings file error")
			return
		
	waveform = SynthVoice.Waveform.values()[(config_file.get_value("Settings", "waveform", SynthVoice.Waveform.SINE))]
	first_octave = config_file.get_value("Settings", "first_octave", 4)
	number_of_octaves = config_file.get_value("Settings", "number_of_octaves", 2)
	attack = config_file.get_value("Settings", "attack", 0.1)
	decay = config_file.get_value("Settings", "decay", 0.1)
	sustain = config_file.get_value("Settings", "sustain", 0.7)
	release = config_file.get_value("Settings", "release", 0.1)
	echo_delay = config_file.get_value("Settings", "echo_delay", 0.25)
	echo_feedback = config_file.get_value("Settings", "echo_feedback", 0.35)
	reverb_room_size = config_file.get_value("Settings", "reverb_room_size", 0.5)
	reverb_damping = config_file.get_value("Settings", "reverb_damping", 0.5)
	
	
func save_config() -> void:
	var filename: String = "user://%s.cfg" % board_name
	var config_file: ConfigFile = ConfigFile.new()
	
	config_file.set_value("Settings", "waveform", waveform)
	config_file.set_value("Settings", "first_octave", first_octave)
	config_file.set_value("Settings", "number_of_octaves", number_of_octaves)
	config_file.set_value("Settings", "attack", attack)
	config_file.set_value("Settings", "decay", decay)
	config_file.set_value("Settings", "sustain", sustain)
	config_file.set_value("Settings", "release", release)
	config_file.set_value("Settings", "echo_delay", echo_delay)
	config_file.set_value("Settings", "echo_feedback", echo_feedback)
	config_file.set_value("Settings", "reverb_room_size", reverb_room_size)
	config_file.set_value("Settings", "reverb_damping", reverb_damping)
	config_file.save(filename)
