# Autoload (nom "Controls"). Gère le remapping des 6 actions de jeu et sa
# persistance. Les défauts ne sont PAS dupliqués ici : on les capture depuis
# l'InputMap déjà rempli par project.godot au tout premier _ready(), pour
# n'avoir qu'une seule source de vérité.
extends Node

const SAVE_PATH: String = "user://controls.cfg"
const REBINDABLE_ACTIONS: PackedStringArray = ["accelerer", "freiner", "gauche", "droite", "derapage", "reinitialiser"]

var _defaults: Dictionary = {}  # action -> Array[InputEvent]

func _ready() -> void:
	for action in REBINDABLE_ACTIONS:
		_defaults[action] = InputMap.action_get_events(action).duplicate()
	_load()

func _kind_of(event: InputEvent) -> String:
	if event is InputEventKey:
		return "keyboard"
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		return "gamepad"
	return ""

func _events_match(a: InputEvent, b: InputEvent) -> bool:
	if a is InputEventKey and b is InputEventKey:
		return a.physical_keycode == b.physical_keycode
	if a is InputEventJoypadButton and b is InputEventJoypadButton:
		return a.button_index == b.button_index
	if a is InputEventJoypadMotion and b is InputEventJoypadMotion:
		return a.axis == b.axis and signf(a.axis_value) == signf(b.axis_value)
	return false

# Assigne `event` à `action`. Retire cet événement de toute autre action
# rebindable qui l'utilisait déjà (une touche/bouton ne peut jamais être
# liée à deux actions de jeu en même temps), puis remplace tous les
# événements du même type (clavier, ou manette) déjà présents sur `action`.
func rebind(action: String, event: InputEvent) -> void:
	var kind: String = _kind_of(event)
	if kind == "" or not REBINDABLE_ACTIONS.has(action):
		return

	for other in REBINDABLE_ACTIONS:
		if other == action:
			continue
		for existing in InputMap.action_get_events(other):
			if _events_match(existing, event):
				InputMap.action_erase_event(other, existing)

	for existing in InputMap.action_get_events(action):
		if _kind_of(existing) == kind:
			InputMap.action_erase_event(action, existing)
	InputMap.action_add_event(action, event)

	_save()

func reset_action(action: String) -> void:
	if not _defaults.has(action):
		return
	for existing in InputMap.action_get_events(action):
		InputMap.action_erase_event(action, existing)
	for event in _defaults[action]:
		InputMap.action_add_event(action, event)
	_save()

func reset_all() -> void:
	for action in REBINDABLE_ACTIONS:
		reset_action(action)

func _save() -> void:
	var cfg := ConfigFile.new()
	for action in REBINDABLE_ACTIONS:
		cfg.set_value("bindings", action, InputMap.action_get_events(action))
	var err: Error = cfg.save(SAVE_PATH)
	if err != OK:
		push_warning("Controls: échec de sauvegarde de %s (%s)" % [SAVE_PATH, error_string(err)])

# Tolérant aux pannes : fichier absent, illisible, ou contenu invalide ->
# on ignore et les défauts déjà actifs dans l'InputMap restent en place.
# Jamais de crash, jamais d'état partiellement appliqué pour une action.
func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return

	var cfg := ConfigFile.new()
	var err: Error = cfg.load(SAVE_PATH)
	if err != OK:
		push_warning("Controls: %s illisible, retour aux touches par défaut (%s)" % [SAVE_PATH, error_string(err)])
		return

	for action in REBINDABLE_ACTIONS:
		if not cfg.has_section_key("bindings", action):
			continue
		var value: Variant = cfg.get_value("bindings", action)
		if typeof(value) != TYPE_ARRAY:
			continue

		var events: Array = []
		for item in value:
			if item is InputEvent and _kind_of(item) != "":
				events.append(item)
		if events.is_empty():
			continue

		for existing in InputMap.action_get_events(action):
			InputMap.action_erase_event(action, existing)
		for event in events:
			InputMap.action_add_event(action, event)
