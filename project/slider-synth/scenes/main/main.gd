extends Control

class_name Main
const BOARD_SETTINGS = preload("uid://cojcjbjlap7p0")

@onready var red_board: Board = $VBoxContainer/RedBoard
@onready var green_board: Board = $VBoxContainer/GreenBoard
@onready var cyan_board: Board = $VBoxContainer/CyanBoard
@onready var yellow_board: Board = $VBoxContainer/YellowBoard

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _on_red_settings_button_pressed() -> void:
	var board_settings_dialog: BoardSettings = BOARD_SETTINGS.instantiate()
	board_settings_dialog.board = red_board
	add_child(board_settings_dialog)
