# Menu pause en course (type osu! : Continuer / Redémarrer / Quitter, sans
# dialogue de confirmation). Instancié caché par main.gd, jamais sa propre
# scène — la simulation doit rester en mémoire pour "Continuer".
class_name PauseMenu
extends CanvasLayer

signal resumed
signal restarted
signal quit_requested

var _continue_button: Button

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.75)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(200.0, 0.0)
	vbox.add_theme_constant_override("separation", 12)
	center.add_child(vbox)

	var title := Label.new()
	title.text = "Pause"
	title.add_theme_font_size_override("font_size", 32)
	vbox.add_child(title)

	_continue_button = Button.new()
	_continue_button.text = "Continuer"
	_continue_button.pressed.connect(func() -> void: resumed.emit())
	vbox.add_child(_continue_button)

	var restart_button := Button.new()
	restart_button.text = "Redémarrer"
	restart_button.pressed.connect(func() -> void: restarted.emit())
	vbox.add_child(restart_button)

	var quit_button := Button.new()
	quit_button.text = "Quitter"
	quit_button.pressed.connect(func() -> void: quit_requested.emit())
	vbox.add_child(quit_button)

func focus_first() -> void:
	_continue_button.grab_focus()
