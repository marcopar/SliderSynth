extends Control

class_name SliderControl

@onready var value: Label = $PanelContainer/VBoxContainer/HBoxContainer/Value
@onready var slider: HSlider = $PanelContainer/VBoxContainer/Slider


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	update_label(slider.value)

func update_label(v: float) -> void:
	if step_decimals(v) == 0:
		value.text = "%d" % v
	else:
		value.text = "%.2f" % v
	
func _on_slider_value_changed(v: float) -> void:
	update_label(v)
