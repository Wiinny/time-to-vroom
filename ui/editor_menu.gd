# Écran d'entrée de l'éditeur : liste les pistes sauvegardées localement
# (user://tracks/) + « Nouvelle piste ». Overlay affiché par-dessus
# ui/main_menu.gd, même patron que ui/vehicle_menu.gd. Le choix (nouvelle
# piste ou piste existante) est transmis à editor/track_editor.tscn via
# l'autoload Session, avant le changement de scène.
class_name EditorMenu
extends Control

signal closed

var _list_container: VBoxContainer

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

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
	vbox.custom_minimum_size = Vector2(320.0, 0.0)
	vbox.add_theme_constant_override("separation", 10)
	vbox.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(vbox)

	var title := Label.new()
	title.text = "Éditeur de pistes"
	title.add_theme_font_size_override("font_size", 28)
	vbox.add_child(title)

	var new_button := Button.new()
	new_button.text = "Nouvelle piste"
	new_button.pressed.connect(_on_new_pressed)
	vbox.add_child(new_button)

	var list_label := Label.new()
	list_label.text = "Pistes sauvegardées :"
	vbox.add_child(list_label)

	_list_container = VBoxContainer.new()
	_list_container.add_theme_constant_override("separation", 4)
	vbox.add_child(_list_container)

	var back_button := Button.new()
	back_button.text = "Retour"
	back_button.pressed.connect(func() -> void: closed.emit())
	vbox.add_child(back_button)

# Échap ferme ce panneau comme le bouton "Retour" — même règle sur tous les
# écrans qui en proposent un (voir ui/vehicle_menu.gd, ui/settings_menu.gd,
# ui/ghost_menu.gd, ui/track_select.gd). Le garde `visible` est nécessaire :
# ce nœud reste dans l'arbre (show()/hide()) même caché.
func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		closed.emit()
		get_viewport().set_input_as_handled()

func focus_first() -> void:
	_refresh_list()

func _refresh_list() -> void:
	for child in _list_container.get_children():
		child.queue_free()

	var found_any: bool = false
	for entry in TrackCatalog.list_tracks():
		if entry["builtin"]:
			continue  # piste intégrée non modifiable, absente de cet écran
		found_any = true
		var button := Button.new()
		button.text = entry["nom"]
		button.pressed.connect(_on_track_pressed.bind(entry["path"]))
		_list_container.add_child(button)

	if not found_any:
		var empty_label := Label.new()
		empty_label.text = "(aucune piste sauvegardée pour l'instant)"
		_list_container.add_child(empty_label)

func _on_new_pressed() -> void:
	Session.pending_track_path = ""
	get_tree().change_scene_to_file("res://editor/track_editor.tscn")

func _on_track_pressed(path: String) -> void:
	Session.pending_track_path = path
	get_tree().change_scene_to_file("res://editor/track_editor.tscn")
