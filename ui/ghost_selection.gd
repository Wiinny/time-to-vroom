# Autoload (nom "GhostSelection"). Mémorise, PAR PISTE, le mode de fantôme
# choisi dans ui/ghost_menu.gd — même patron tolérant aux pannes que
# ui/controls.gd/ui/leaderboard.gd (ConfigFile vers user://, fichier
# absent/corrompu -> défauts, jamais de crash).
#
# Stockage SEUL, volontairement : résoudre un fichier de replay demande
# Leaderboard (autoload) + VehicleSelection (autoload), et les autoloads de
# ce projet restent des îlots indépendants (aucun n'appelle un autre
# autoload ailleurs dans le projet) — l'orchestration revient à l'appelant
# (main.gd, ui/track_select.gd), via replay/ghost_resolver.gd (statique, pur).
#
# C'est cette persistance qui permet d'enchaîner les tentatives sans repasser
# par un menu UNE FOIS le mode PERSO choisi explicitement : il se re-résout à
# chaque tentative — battre son record change le fichier résolu sans qu'on
# ait besoin de changer la sélection elle-même.
extends Node

const SAVE_PATH: String = "user://ghosts.cfg"

# track_uid -> {"source": GhostResolver.Source, "vehicule": String, "fichier": String}
var _selections: Dictionary = {}
var _loaded: bool = false

func _ready() -> void:
	_load()

# Défaut : AUCUN fantôme tant que le joueur n'a rien choisi explicitement
# dans ui/ghost_menu.gd (décision explicite : aucun fantôme ne doit courir
# "par surprise" sur une piste qu'on n'a jamais configurée).
func selection(track_uid: String) -> Dictionary:
	_ensure_loaded()
	return _selections.get(track_uid, {"source": GhostResolver.Source.AUCUN, "vehicule": "", "fichier": ""})

func select(track_uid: String, source: int, vehicule: String = "", fichier: String = "") -> void:
	_ensure_loaded()
	_selections[track_uid] = {"source": source, "vehicule": vehicule, "fichier": fichier}
	_save()

func _ensure_loaded() -> void:
	if not _loaded:
		_load()

func _load() -> void:
	_loaded = true
	_selections = {}
	if not FileAccess.file_exists(SAVE_PATH):
		return

	var cfg := ConfigFile.new()
	var err: Error = cfg.load(SAVE_PATH)
	if err != OK:
		push_warning("GhostSelection: %s illisible, sélections par défaut (%s)" % [SAVE_PATH, error_string(err)])
		return

	for section in cfg.get_sections():
		if cfg.has_section_key(section, "source"):
			var source_str: String = String(cfg.get_value(section, "source", "aucun"))
			_selections[section] = {
				"source": GhostResolver.source_from_name(source_str),
				"vehicule": String(cfg.get_value(section, "vehicule", "")),
				"fichier": String(cfg.get_value(section, "fichier", "")),
			}

func _save() -> void:
	var cfg := ConfigFile.new()
	for track_uid in _selections:
		var sel: Dictionary = _selections[track_uid]
		cfg.set_value(track_uid, "source", GhostResolver.source_name(int(sel.get("source", GhostResolver.Source.AUCUN))))
		cfg.set_value(track_uid, "vehicule", String(sel.get("vehicule", "")))
		cfg.set_value(track_uid, "fichier", String(sel.get("fichier", "")))
	var err: Error = cfg.save(SAVE_PATH)
	if err != OK:
		push_warning("GhostSelection: échec de sauvegarde de %s (%s)" % [SAVE_PATH, error_string(err)])
