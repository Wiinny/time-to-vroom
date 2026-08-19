# Autoload (nom "Leaderboard"). Historique local de tous les runs terminés
# (un run n'écrase jamais un run précédent — voir CLAUDE.md, « Données à
# enregistrer pour chaque run »). Depuis le système de fantôme
# (replay/replay_store.gd), chaque entrée référence aussi son fichier de
# replay + son hash — Leaderboard sert d'index, pas besoin d'un catalogue
# séparé pour les replays. Reste un sous-ensemble volontairement léger du
# log complet de l'étape 5 (pas de temps aux checkpoints, pas de mods) : les
# champs manquants s'ajouteront sans casser ce qui existe.
#
# Même patron que ui/controls.gd : ConfigFile vers user://, tolérant aux
# pannes (fichier absent/corrompu -> historique vide, jamais de crash).
#
# Temps stockés en millisecondes (clé "ms"), pas en ticks : passage de la
# simulation à 100 Hz avec chrono interpolé au sous-tick (voir
# sim/race_state.gd). Les anciennes entrées ("ticks", 60 Hz) ne sont plus
# reconnues et sont donc ignorées au chargement — décision explicite de
# repartir de zéro plutôt que d'afficher des temps faux après le changement
# de cadence (un ancien run de 30 s à 60 Hz afficherait 18 s à 100 Hz s'il
# était réinterprété tel quel).
extends Node

const SAVE_PATH: String = "user://leaderboard.cfg"

# track_uid -> Array[{"vehicule": String, "ms": int, "date": String}]
var _runs: Dictionary = {}
var _loaded: bool = false

func _ready() -> void:
	_load()

# -1 si aucun run enregistré pour cette piste+véhicule.
func best_time_ms(track_id: String, vehicle_id: String) -> int:
	var best: Dictionary = personal_best(track_id, vehicle_id)
	return int(best.get("ms", -1))

# Enregistre un run terminé (jamais écrasé). Renvoie true si c'est un
# nouveau meilleur temps pour cette piste+véhicule. replay_file/hash_final
# sont optionnels (un appelant qui n'a pas de replay à associer peut les
# omettre, l'entrée reste valide avec des défauts vides).
func submit_time(track_id: String, vehicle_id: String, time_ms: int, replay_file: String = "", hash_final: int = 0) -> bool:
	_ensure_loaded()
	var current_best: int = best_time_ms(track_id, vehicle_id)
	var is_record: bool = current_best < 0 or time_ms < current_best

	var list: Array = _runs.get(track_id, [])
	list.append({
		"vehicule": vehicle_id,
		"ms": time_ms,
		"date": Time.get_datetime_string_from_system(),
		"replay": replay_file,
		"hash": hash_final,
		"epingle": false,
	})
	_runs[track_id] = list
	_save()
	return is_record

# Épingle/désépingle un run comme fantôme "ajouté manuellement" (voir
# ui/ghost_menu.gd) — utilisé quand un run qui n'est pas un record est quand
# même sauvegardé (ui/finish_menu.gd) ou retiré (ui/ghost_menu.gd).
func set_pinned(track_id: String, replay_file: String, epingle: bool) -> void:
	_ensure_loaded()
	var list: Array = _runs.get(track_id, [])
	for entry in list:
		if entry.get("replay", "") == replay_file:
			entry["epingle"] = epingle
	_runs[track_id] = list
	_save()

# Runs épinglés d'une piste, tous véhicules confondus.
func pinned_runs(track_id: String) -> Array[Dictionary]:
	_ensure_loaded()
	var result: Array[Dictionary] = []
	for entry in _runs.get(track_id, []):
		if entry.get("epingle", false):
			result.append(entry)
	return result

# Supprime UN run précis (entrée + fichier de replay) — jamais utilisé sans
# confirmation explicite de l'utilisateur (voir ui/ghost_menu.gd). Sort
# volontairement du principe "on garde l'historique" : cette règle vise le
# système qui écraserait un run silencieusement, pas le joueur qui efface le
# sien explicitement (même précédent que "Supprimer..."/"Effacer les scores
# locaux" dans ui/track_select.gd).
func delete_run(track_id: String, replay_file: String) -> void:
	_ensure_loaded()
	var list: Array = _runs.get(track_id, [])
	for i in range(list.size() - 1, -1, -1):
		if list[i].get("replay", "") == replay_file:
			list.remove_at(i)
	_runs[track_id] = list
	ReplayStore.delete_file(replay_file)
	_save()

# Tous les runs d'une piste, triés par temps croissant. vehicle_id == "" ->
# tous véhicules confondus.
func runs(track_id: String, vehicle_id: String = "") -> Array[Dictionary]:
	_ensure_loaded()
	var result: Array[Dictionary] = []
	for entry in _runs.get(track_id, []):
		if vehicle_id == "" or entry.get("vehicule", "") == vehicle_id:
			result.append(entry)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["ms"]) < int(b["ms"]))
	return result

# {} si aucun run enregistré pour cette piste+véhicule.
func personal_best(track_id: String, vehicle_id: String) -> Dictionary:
	var list: Array[Dictionary] = runs(track_id, vehicle_id)
	return list[0] if not list.is_empty() else {}

# Efface tout l'historique local d'une piste (tous véhicules confondus) —
# utilisé par le menu contextuel « Effacer les scores locaux »
# (ui/track_select.gd). Supprime aussi les fichiers de replay associés :
# sinon ce sont des fichiers orphelins que plus rien ne peut jamais lister
# (Leaderboard est l'unique index).
func clear_track(track_id: String) -> void:
	_ensure_loaded()
	for entry in _runs.get(track_id, []):
		ReplayStore.delete_file(String(entry.get("replay", "")))
	if _runs.erase(track_id):
		_save()

func _ensure_loaded() -> void:
	if not _loaded:
		_load()

func _load() -> void:
	_loaded = true
	_runs = {}
	if not FileAccess.file_exists(SAVE_PATH):
		return

	var cfg := ConfigFile.new()
	var err: Error = cfg.load(SAVE_PATH)
	if err != OK:
		push_warning("Leaderboard: %s illisible, historique local vide (%s)" % [SAVE_PATH, error_string(err)])
		return

	for section in cfg.get_sections():
		if cfg.has_section_key(section, "runs"):
			var value: Variant = cfg.get_value(section, "runs")
			if typeof(value) == TYPE_ARRAY:
				_runs[section] = _sanitize_runs(value)
		# Sections "piste|véhicule" (ancien format best_ticks) ou entrées
		# "ticks" (60 Hz, avant le passage à 100 Hz) : ni migrées ni lues,
		# ignorées silencieusement — voir l'en-tête de ce fichier.

func _sanitize_runs(value: Array) -> Array:
	var result: Array = []
	for item in value:
		if item is Dictionary and typeof(item.get("ms")) == TYPE_INT:
			result.append({
				"vehicule": String(item.get("vehicule", "")),
				"ms": int(item["ms"]),
				"date": String(item.get("date", "")),
				# Clés absentes des entrées antérieures au système de replay :
				# défauts vides, chargent sans migration (même promesse que le
				# reste de ce fichier).
				"replay": String(item.get("replay", "")),
				"hash": int(item.get("hash", 0)) if typeof(item.get("hash", 0)) == TYPE_INT else 0,
				# Absente des entrées antérieures au système de fantômes
				# épinglés : défaut false, charge sans migration.
				"epingle": bool(item.get("epingle", false)),
			})
	return result

func _save() -> void:
	var cfg := ConfigFile.new()
	for track_id in _runs:
		cfg.set_value(track_id, "runs", _runs[track_id])
	var err: Error = cfg.save(SAVE_PATH)
	if err != OK:
		push_warning("Leaderboard: échec de sauvegarde de %s (%s)" % [SAVE_PATH, error_string(err)])
