# Source unique de la liste des pistes jouables : la piste intégrée
# (map/track_hardcoded.gd, non modifiable) suivie des pistes sauvegardées
# dans user://tracks. Utilisé par ui/editor_menu.gd (lister pour éditer) et
# ui/track_select.gd (lister pour jouer) — évite de dupliquer le parcours du
# dossier entre les deux écrans.
class_name TrackCatalog

const BUILTIN_UID: String = "hardcoded_v1"

# -> [{ "uid", "nom", "auteur", "path", "builtin": bool }, ...]
# "path" est vide pour la piste intégrée (main.gd retombe sur
# TrackHardcoded quand Session.pending_track_path est vide).
static func list_tracks() -> Array[Dictionary]:
	var result: Array[Dictionary] = [
		{"uid": BUILTIN_UID, "nom": "Circuit d'essai", "auteur": "Intégrée", "path": "", "builtin": true},
	]

	DirAccess.make_dir_recursive_absolute("user://tracks")
	var dir: DirAccess = DirAccess.open("user://tracks")
	if dir == null:
		return result

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var path: String = "user://tracks/" + file_name
			var data: TrackData = TrackData.load_from_path(path)
			if data != null:
				result.append({
					"uid": data.uid,
					"nom": data.nom,
					"auteur": data.auteur,
					"path": path,
					"builtin": false,
				})
		file_name = dir.get_next()
	dir.list_dir_end()

	return result

# Supprime définitivement le fichier .tres d'une piste — utilisé par le menu
# contextuel « Supprimer... » (ui/track_select.gd). No-op sur la piste
# intégrée (path vide, jamais transmis ici par l'appelant).
static func delete_track(path: String) -> void:
	if path == "":
		return
	DirAccess.remove_absolute(path)
