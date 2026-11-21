extends Control

class_name SliderControl

@onready var label: Label = $PanelContainer/VBoxContainer/HBoxContainer/Label
@onready var value: Label = $PanelContainer/VBoxContainer/HBoxContainer/Value
@onready var slider: HSlider = $PanelContainer/VBoxContainer/Slider


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.
	
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _on_slider_value_changed(v: float) -> void:
	value.text = "%.1f" % v
