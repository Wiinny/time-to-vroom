# Panneau de gestion des collections (façon osu!), ouvert depuis le menu
# contextuel clic droit d'une piste dans ui/track_select.gd — même patron
# d'overlay que ui/vehicle_menu.gd / ui/editor_menu.gd. Les boutons
# Ajouter/Retirer de chaque ligne agissent sur LA piste qui a ouvert ce
# panneau (voir open_for()), comme le clic droit -> Collections d'osu!.
class_name CollectionsMenu
extends Control

signal closed

var _track: Dictionary = {}
var _create_edit: LineEdit
var _rows_container: VBoxContainer
var _rename_target: String = ""  # nom en cours de renommage, "" = aucun

func _ready() -> void:
	_build_ui()

# À appeler avant .show() — ne rafraîchit pas tout de suite, focus_first()
# (appelée par le parent juste après .show(), même patron que les autres
# overlays) s'en charge.
func open_for(track: Dictionary) -> void:
	_track = track
	_rename_target = ""

func focus_first() -> void:
	_refresh()
	_create_edit.grab_focus()

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
	vbox.custom_minimum_size = Vector2(560.0, 0.0)
	vbox.add_theme_constant_override("separation", 10)
	vbox.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(vbox)

	var title := Label.new()
	title.text = "Collections"
	title.add_theme_font_size_override("font_size", 28)
	vbox.add_child(title)

	_create_edit = LineEdit.new()
	_create_edit.placeholder_text = "Nouvelle collection… (Entrée pour créer)"
	_create_edit.text_submitted.connect(_on_create_submitted)
	vbox.add_child(_create_edit)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0.0, 280.0)
	vbox.add_child(scroll)

	_rows_container = VBoxContainer.new()
	_rows_container.add_theme_constant_override("separation", 6)
	_rows_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows_container)

	var back_button := Button.new()
	back_button.text = "Fermer"
	back_button.pressed.connect(func() -> void: closed.emit())
	vbox.add_child(back_button)

func _on_create_submitted(text: String) -> void:
	if Collections.create(text):
		_create_edit.text = ""
	_refresh()
	# text_submitted ne garde pas le focus tout seul une fois que _refresh()
	# a reconstruit les lignes en dessous — sans ce grab_focus(), créer
	# plusieurs collections à la suite au clavier ne marche qu'une fois.
	_create_edit.grab_focus()

func _refresh() -> void:
	for child in _rows_container.get_children():
		child.queue_free()

	var names: Array[String] = Collections.list_names()
	if names.is_empty():
		var empty := Label.new()
		empty.text = "(aucune collection pour l'instant)"
		empty.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		_rows_container.add_child(empty)
		return

	for name in names:
		_rows_container.add_child(_build_row(name))

func _build_row(name: String) -> Control:
	if name == _rename_target:
		return _build_rename_row(name)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var label := Label.new()
	label.text = "%s (%d)" % [name, Collections.count(name)]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var rename_button := Button.new()
	rename_button.text = "Renommer"
	rename_button.pressed.connect(_on_rename_pressed.bind(name))
	row.add_child(rename_button)

	var track_uid: String = _track.get("uid", "")
	var is_member: bool = track_uid != "" and Collections.contains(name, track_uid)
	var toggle_button := Button.new()
	toggle_button.text = "Retirer" if is_member else "Ajouter"
	toggle_button.disabled = track_uid == ""
	toggle_button.pressed.connect(_on_toggle_pressed.bind(name))
	row.add_child(toggle_button)

	var delete_button := Button.new()
	delete_button.text = "Supprimer"
	delete_button.pressed.connect(_on_delete_pressed.bind(name))
	row.add_child(delete_button)

	return row

func _build_rename_row(name: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var edit := LineEdit.new()
	edit.text = name
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.text_submitted.connect(_on_rename_submitted.bind(name))
	row.add_child(edit)

	var cancel_button := Button.new()
	cancel_button.text = "Annuler"
	cancel_button.pressed.connect(_on_rename_cancelled)
	row.add_child(cancel_button)

	edit.call_deferred("grab_focus")
	return row

func _on_rename_pressed(name: String) -> void:
	_rename_target = name
	_refresh()

func _on_rename_cancelled() -> void:
	_rename_target = ""
	_refresh()

func _on_rename_submitted(new_name: String, old_name: String) -> void:
	Collections.rename(old_name, new_name)
	_rename_target = ""
	_refresh()

func _on_toggle_pressed(name: String) -> void:
	var track_uid: String = _track.get("uid", "")
	if track_uid == "":
		return
	if Collections.contains(name, track_uid):
		Collections.remove_track(name, track_uid)
	else:
		Collections.add_track(name, track_uid)
	_refresh()

func _on_delete_pressed(name: String) -> void:
	Collections.delete(name)
	if _rename_target == name:
		_rename_target = ""
	_refresh()
