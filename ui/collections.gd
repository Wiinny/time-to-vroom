# Autoload (nom "Collections"). Collections de pistes créées librement par
# le joueur pour s'organiser (façon collections d'osu!) — persistées dans
# user://collections.cfg, même patron que ui/leaderboard.gd (tolérant aux
# pannes : fichier absent/corrompu -> aucune collection, jamais de crash).
extends Node

const SAVE_PATH: String = "user://collections.cfg"

# nom -> Array[String] (track uids, voir map/track_data.gd)
var _collections: Dictionary = {}
var _loaded: bool = false

func _ready() -> void:
	_load()

func list_names() -> Array[String]:
	_ensure_loaded()
	var names: Array[String] = []
	for name in _collections:
		names.append(name)
	names.sort()
	return names

# false si le nom est vide ou déjà pris.
func create(name: String) -> bool:
	_ensure_loaded()
	var trimmed: String = name.strip_edges()
	if trimmed == "" or _collections.has(trimmed):
		return false
	_collections[trimmed] = []
	_save()
	return true

func rename(old_name: String, new_name: String) -> bool:
	_ensure_loaded()
	var trimmed: String = new_name.strip_edges()
	if trimmed == "" or trimmed == old_name or not _collections.has(old_name) or _collections.has(trimmed):
		return false
	_collections[trimmed] = _collections[old_name]
	_collections.erase(old_name)
	_save()
	return true

func delete(name: String) -> void:
	_ensure_loaded()
	if _collections.erase(name):
		_save()

func contains(name: String, track_uid: String) -> bool:
	_ensure_loaded()
	var list: Array = _collections.get(name, [])
	return list.has(track_uid)

func add_track(name: String, track_uid: String) -> void:
	_ensure_loaded()
	if not _collections.has(name):
		return
	var list: Array = _collections[name]
	if not list.has(track_uid):
		list.append(track_uid)
		_save()

func remove_track(name: String, track_uid: String) -> void:
	_ensure_loaded()
	if not _collections.has(name):
		return
	var list: Array = _collections[name]
	if list.has(track_uid):
		list.erase(track_uid)
		_save()

func tracks_in(name: String) -> Array[String]:
	_ensure_loaded()
	var result: Array[String] = []
	for uid in _collections.get(name, []):
		result.append(String(uid))
	return result

func count(name: String) -> int:
	_ensure_loaded()
	return (_collections.get(name, []) as Array).size()

# Appelé quand une piste est supprimée (ui/track_select.gd) pour ne pas
# laisser de références mortes dans les collections.
func remove_track_everywhere(track_uid: String) -> void:
	_ensure_loaded()
	var changed: bool = false
	for name in _collections:
		var list: Array = _collections[name]
		if list.has(track_uid):
			list.erase(track_uid)
			changed = true
	if changed:
		_save()

func _ensure_loaded() -> void:
	if not _loaded:
		_load()

func _load() -> void:
	_loaded = true
	_collections = {}
	if not FileAccess.file_exists(SAVE_PATH):
		return

	var cfg := ConfigFile.new()
	var err: Error = cfg.load(SAVE_PATH)
	if err != OK:
		push_warning("Collections: %s illisible, aucune collection (%s)" % [SAVE_PATH, error_string(err)])
		return

	for name in cfg.get_sections():
		if not cfg.has_section_key(name, "tracks"):
			continue
		var value: Variant = cfg.get_value(name, "tracks")
		if typeof(value) != TYPE_ARRAY:
			continue
		var list: Array = []
		for item in value:
			if item is String:
				list.append(item)
		_collections[name] = list

func _save() -> void:
	var cfg := ConfigFile.new()
	for name in _collections:
		cfg.set_value(name, "tracks", _collections[name])
	var err: Error = cfg.save(SAVE_PATH)
	if err != OK:
		push_warning("Collections: échec de sauvegarde de %s (%s)" % [SAVE_PATH, error_string(err)])
