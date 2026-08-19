# Autoload (nom "VehicleSelection"). Mémorise le véhicule choisi entre deux
# lancements du jeu — même patron que ui/controls.gd (ConfigFile vers
# user://, tolérant aux pannes : fichier absent/corrompu/ID inconnu ->
# défaut, jamais de crash).
extends Node

const SAVE_PATH: String = "user://vehicle.cfg"

var selected_id: String = VehicleRoster.default_id()

func _ready() -> void:
	_load()

func select(id: String) -> void:
	if VehicleRoster.find(id).is_empty():
		return
	selected_id = id
	_save()

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("vehicle", "id", selected_id)
	var err: Error = cfg.save(SAVE_PATH)
	if err != OK:
		push_warning("VehicleSelection: échec de sauvegarde de %s (%s)" % [SAVE_PATH, error_string(err)])

func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return

	var cfg := ConfigFile.new()
	var err: Error = cfg.load(SAVE_PATH)
	if err != OK:
		push_warning("VehicleSelection: %s illisible, retour au véhicule par défaut (%s)" % [SAVE_PATH, error_string(err)])
		return

	var value: Variant = cfg.get_value("vehicle", "id", "")
	if typeof(value) != TYPE_STRING or VehicleRoster.find(value).is_empty():
		return

	selected_id = value
