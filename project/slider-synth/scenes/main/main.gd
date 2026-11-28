extends Control

class_name Main
const BOARD_SETTINGS = preload("uid://cojcjbjlap7p0")

const DIALOGS_GROUP: String = "DIALOGS"

@onready var red_board: Board = $VBoxContainer/RedBoard
@onready var green_board: Board = $VBoxContainer/GreenBoard
@onready var cyan_board: Board = $VBoxContainer/CyanBoard
@onready var yellow_board: Board = $VBoxContainer/YellowBoard

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass

func open_settings_dialog(board: Board) -> void:
	if get_tree().get_nodes_in_group(DIALOGS_GROUP).size() > 0:
		return
	var board_settings_dialog: BoardSettings = BOARD_SETTINGS.instantiate()
	board_settings_dialog.add_to_group(DIALOGS_GROUP)
	board_settings_dialog.main_board = board
	add_child(board_settings_dialog)

func _on_red_settings_button_pressed() -> void:
	#stops the output
	red_board.build_voices()
	red_board.build_effects()
	
	open_settings_dialog(red_board)

func _on_green_settings_button_pressed() -> void:
	#stops the output
	green_board.build_voices()
	green_board.build_effects()
	
	open_settings_dialog(green_board)
	
func _on_cyan_settings_button_pressed() -> void:
	#stops the output
	cyan_board.build_voices()
	cyan_board.build_effects()
	
	open_settings_dialog(cyan_board)
	
func _on_yellow_settings_button_pressed() -> void:
	#stops the output
	yellow_board.build_voices()
	yellow_board.build_effects()
	
	open_settings_dialog(yellow_board)
