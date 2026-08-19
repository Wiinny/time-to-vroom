# Écran de remapping des touches. Overlay affiché par-dessus ui/main_menu.gd,
# pas une scène séparée. Construit par code (comme ui/hud.gd), pas de .tscn.
#
# La capture d'un nouvel input passe par _input() + set_input_as_handled(),
# AVANT le routage GUI de Godot : sans ça, la touche/le bouton qui vient de
# déclencher le "rebind" (ex. Entrée / A manette, si c'est aussi ui_accept)
# risquerait de re-déclencher le bouton focus juste après, ou d'interrompre
# la capture. La souris est explicitement ignorée dans cette capture : un
# contrôle de jeu ne peut jamais être lié à la souris.
class_name SettingsMenu
extends Control

signal closed

const ACTION_LABELS: Dictionary = {
	"accelerer": "Accélérer",
	"freiner": "Freiner",
	"gauche": "Gauche",
	"droite": "Droite",
	"derapage": "Dérapage",
	"reinitialiser": "Réinitialiser",
}

var _listening_action: String = ""
var _listening_kind: String = ""

var _keyboard_buttons: Dictionary = {}
var _gamepad_buttons: Dictionary = {}

func _ready() -> void:
	_build_ui()
	_refresh_labels()

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
	vbox.custom_minimum_size = Vector2(440.0, 0.0)
	vbox.add_theme_constant_override("separation", 10)
	vbox.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(vbox)

	var title := Label.new()
	title.text = "Paramètres — touches"
	title.add_theme_font_size_override("font_size", 28)
	vbox.add_child(title)

	var hint := Label.new()
	hint.text = "Clique un bouton puis appuie sur une touche ou un bouton manette. Échap annule."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(hint)

	for action in Controls.REBINDABLE_ACTIONS:
		var row := HBoxContainer.new()
		vbox.add_child(row)

		var label := Label.new()
		label.text = ACTION_LABELS.get(action, action)
		label.custom_minimum_size = Vector2(140.0, 0.0)
		row.add_child(label)

		var kb_button := Button.new()
		kb_button.custom_minimum_size = Vector2(130.0, 0.0)
		kb_button.pressed.connect(_on_rebind_pressed.bind(action, "keyboard", kb_button))
		row.add_child(kb_button)
		_keyboard_buttons[action] = kb_button

		var gp_button := Button.new()
		gp_button.custom_minimum_size = Vector2(130.0, 0.0)
		gp_button.pressed.connect(_on_rebind_pressed.bind(action, "gamepad", gp_button))
		row.add_child(gp_button)
		_gamepad_buttons[action] = gp_button

	var reset_button := Button.new()
	reset_button.text = "Réinitialiser tout"
	reset_button.pressed.connect(_on_reset_all_pressed)
	vbox.add_child(reset_button)

	var back_button := Button.new()
	back_button.text = "Retour"
	back_button.pressed.connect(_on_back_pressed)
	vbox.add_child(back_button)

func focus_first() -> void:
	_refresh_labels()  # les bindings ont pu changer pendant que l'écran était caché
	_keyboard_buttons[Controls.REBINDABLE_ACTIONS[0]].grab_focus()

func _label_for(action: String, kind: String) -> String:
	for event in InputMap.action_get_events(action):
		if kind == "keyboard" and event is InputEventKey:
			return _keyboard_label(event)
		if kind == "gamepad" and (event is InputEventJoypadButton or event is InputEventJoypadMotion):
			return event.as_text()
	return "—"

# On stocke physical_keycode (scancode, indépendant de la disposition
# clavier — voir Controls.rebind) pour que le remapping et le replay restent
# valides sur n'importe quel clavier. Mais event.as_text() sur un
# physical_keycode affiche le libellé de position "canonique" (disposition
# QWERTY), pas la touche réellement présente à cet endroit sur le clavier de
# l'utilisateur. DisplayServer.keyboard_get_keycode_from_physical() traduit
# la position physique vers la touche localisée de la disposition active
# (ex. Z en AZERTY pour la position physique de W en QWERTY).
func _keyboard_label(event: InputEventKey) -> String:
	var localized: Key = DisplayServer.keyboard_get_keycode_from_physical(event.physical_keycode)
	return OS.get_keycode_string(localized)

func _refresh_labels() -> void:
	for action in Controls.REBINDABLE_ACTIONS:
		_keyboard_buttons[action].text = _label_for(action, "keyboard")
		_gamepad_buttons[action].text = _label_for(action, "gamepad")

func _on_rebind_pressed(action: String, kind: String, button: Button) -> void:
	_listening_action = action
	_listening_kind = kind
	button.text = "…"
	button.release_focus()  # une touche de validation ne doit pas re-déclencher ce bouton

func _stop_listening() -> void:
	_listening_action = ""
	_listening_kind = ""
	_refresh_labels()

func _on_reset_all_pressed() -> void:
	_stop_listening()
	Controls.reset_all()
	_refresh_labels()

func _on_back_pressed() -> void:
	_stop_listening()
	closed.emit()

# Échap ferme cet écran comme le bouton "Retour" — même règle sur tous les
# écrans qui en proposent un (voir ui/vehicle_menu.gd, ui/editor_menu.gd,
# ui/ghost_menu.gd, ui/track_select.gd). Ne s'applique QUE hors capture de
# rebind : _input() ci-dessous consomme déjà Échap pendant l'écoute (annule
# juste l'écoute, cf. son propre commentaire) et marque l'event "handled",
# donc _unhandled_input() ne voit jamais passer cet Échap-là.
func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	if _listening_action == "":
		return
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		return

	if event is InputEventKey:
		if event.pressed and event.physical_keycode == KEY_ESCAPE:
			_stop_listening()
			get_viewport().set_input_as_handled()
			return
		if _listening_kind != "keyboard" or not event.pressed or event.echo:
			return
		var clean := InputEventKey.new()
		clean.physical_keycode = event.physical_keycode
		Controls.rebind(_listening_action, clean)
		_stop_listening()
		get_viewport().set_input_as_handled()

	elif event is InputEventJoypadButton:
		if _listening_kind != "gamepad" or not event.pressed:
			return
		var clean_btn := InputEventJoypadButton.new()
		clean_btn.button_index = event.button_index
		Controls.rebind(_listening_action, clean_btn)
		_stop_listening()
		get_viewport().set_input_as_handled()

	elif event is InputEventJoypadMotion:
		if _listening_kind != "gamepad" or absf(event.axis_value) < 0.5:
			return
		var clean_motion := InputEventJoypadMotion.new()
		clean_motion.axis = event.axis
		clean_motion.axis_value = 1.0 if event.axis_value > 0.0 else -1.0
		Controls.rebind(_listening_action, clean_motion)
		_stop_listening()
		get_viewport().set_input_as_handled()
