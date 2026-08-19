# Écran de sélection du véhicule. Overlay affiché par-dessus ui/main_menu.gd,
# pas une scène séparée — même patron que ui/settings_menu.gd.
class_name VehicleMenu
extends Control

signal closed

var _rows: Dictionary = {}  # id -> { "button": Button, "status": Label }

func _ready() -> void:
	_build_ui()
	_refresh()

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
	vbox.custom_minimum_size = Vector2(480.0, 0.0)
	vbox.add_theme_constant_override("separation", 10)
	vbox.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(vbox)

	var title := Label.new()
	title.text = "Choix du véhicule"
	title.add_theme_font_size_override("font_size", 28)
	vbox.add_child(title)

	for entry in VehicleRoster.VEHICLES:
		var id: String = entry["id"]

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		vbox.add_child(row)

		var button := Button.new()
		button.text = "%s — %s" % [entry["nom"], entry["reference"]]
		button.custom_minimum_size = Vector2(220.0, 0.0)
		button.pressed.connect(_on_vehicle_pressed.bind(id))
		row.add_child(button)

		var status := Label.new()
		row.add_child(status)

		_rows[id] = {"button": button, "status": status}

		var geste := Label.new()
		geste.text = entry["geste"]
		geste.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
		geste.autowrap_mode = TextServer.AUTOWRAP_WORD
		vbox.add_child(geste)

	var back_button := Button.new()
	back_button.text = "Retour"
	back_button.pressed.connect(func() -> void: closed.emit())
	vbox.add_child(back_button)

# Échap ferme ce panneau comme le bouton "Retour" — même règle sur tous les
# écrans qui en proposent un (voir ui/editor_menu.gd, ui/settings_menu.gd,
# ui/ghost_menu.gd, ui/track_select.gd). Le garde `visible` est nécessaire :
# ce nœud reste dans l'arbre (show()/hide()) même caché.
func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		closed.emit()
		get_viewport().set_input_as_handled()

func _on_vehicle_pressed(id: String) -> void:
	VehicleSelection.select(id)
	_refresh()

# Rafraîchit l'indicateur de sélection — le choix a pu changer depuis la
# construction de l'écran (même règle que SettingsMenu.focus_first()).
func _refresh() -> void:
	for id in _rows:
		var row: Dictionary = _rows[id]
		var is_selected: bool = id == VehicleSelection.selected_id
		(row["status"] as Label).text = "Sélectionné" if is_selected else ""

func focus_first() -> void:
	_refresh()
	var first_id: String = VehicleRoster.default_id()
	(_rows[first_id]["button"] as Button).grab_focus()
