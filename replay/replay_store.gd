# Persistance des replays — user://replays/<nom>.tres, même convention que
# map/track_catalog.gd pour les pistes (.tres sous un dossier user://<pluriel>/,
# par opposition aux .cfg plats de Controls/Leaderboard/VehicleSelection).
#
# Politique de stockage : un fichier par run terminé, JAMAIS "garder
# seulement le meilleur" — c'est la seule option cohérente avec la règle
# déjà en vigueur dans ui/leaderboard.gd ("ne jamais écraser un run par un
# meilleur"). ui/leaderboard.gd reste l'index (chaque entrée référence son
# nom de fichier de replay) : pas de catalogue séparé à maintenir ici.
#
# Charger un Resource depuis le disque est un vecteur d'injection de script
# le jour où des replays seront téléchargeables depuis le site — un
# problème de l'étape 6 (site/backend), pas de celle-ci, mais à garder en
# tête au moment venu.
class_name ReplayStore

const DIR: String = "user://replays"

static func _path(name: String) -> String:
	return "%s/%s" % [DIR, name]

# Sauvegarde `replay` sous un nom déterministe (même recette que
# TrackData.ensure_uid() : FixedHash sur des identifiants + l'horodatage,
# pas de randi()). Renvoie le nom de fichier ("" en cas d'échec) —
# n'importe quel appelant doit tolérer un échec sans bloquer l'écran de fin
# de course.
static func save(replay: ReplayData) -> String:
	var err_dir: Error = DirAccess.make_dir_recursive_absolute(DIR)
	if err_dir != OK and err_dir != ERR_ALREADY_EXISTS:
		push_warning("ReplayStore: échec de création de %s (%s)" % [DIR, error_string(err_dir)])
		return ""

	var h: int = FixedHash.start()
	h = FixedHash.combine(h, replay.track_uid.hash())
	h = FixedHash.combine(h, replay.vehicle_id.hash())
	h = FixedHash.combine(h, replay.finish_ms)
	h = FixedHash.combine(h, int(Time.get_unix_time_from_system() * 1000.0))
	var name: String = "replay_%d.tres" % (h & 0x7fffffffffffffff)

	var err: Error = ResourceSaver.save(replay, _path(name))
	if err != OK:
		push_warning("ReplayStore: échec de sauvegarde de %s (%s)" % [name, error_string(err)])
		return ""
	return name

# Tolérant aux pannes (même patron que Controls/Leaderboard) : fichier
# absent, illisible, ou contenu incohérent -> null, jamais de crash.
# CACHE_MODE_IGNORE est nécessaire, pas juste prudent : un replay sauvegardé
# puis relu dans la même session (écran de fin -> sélection de piste ->
# choix du fantôme) sans ce mode donnerait une lecture périmée depuis le
# cache de ressources de Godot.
static func load_file(name: String) -> ReplayData:
	if name == "" or not FileAccess.file_exists(_path(name)):
		return null
	var loaded: Resource = ResourceLoader.load(_path(name), "", ResourceLoader.CACHE_MODE_IGNORE)
	if not (loaded is ReplayData):
		return null
	var replay: ReplayData = loaded
	if not replay.est_coherent():
		push_warning("ReplayStore: %s incohérent, ignoré" % name)
		return null
	return replay

static func exists(name: String) -> bool:
	return name != "" and FileAccess.file_exists(_path(name))

# Appelé par Leaderboard.clear_track() pour ne pas laisser de fichiers
# orphelins que plus rien ne pourra jamais lister.
static func delete_file(name: String) -> void:
	if name == "":
		return
	DirAccess.remove_absolute(_path(name))
