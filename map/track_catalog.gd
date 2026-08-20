class_name TrackCatalog

const BUILTIN_UID: String = "hardcoded_v1"
const JUNGLE_UID: String = TrackJungle.UID

static func list_tracks() -> Array[Dictionary]:
	var result: Array[Dictionary] = [
		{"uid": BUILTIN_UID, "nom": "Track Test 1", "auteur": "shmelebelek", "path": "", "builtin": true, "date_ajout": ""},
		{"uid": JUNGLE_UID, "nom": TrackJungle.NOM, "auteur": TrackJungle.AUTEUR, "path": "", "builtin": true, "date_ajout": ""},
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
					"date_ajout": data.date_ajout,
				})
		file_name = dir.get_next()
	dir.list_dir_end()

	return result

static func build_builtin(uid: String) -> Track:
	if uid == JUNGLE_UID:
		return TrackJungle.build()
	return TrackHardcoded.build()

static func builtin_start(uid: String) -> PackedInt64Array:
	if uid == JUNGLE_UID:
		return TrackJungle.start_transform()
	return TrackHardcoded.start_transform()

static func delete_track(path: String) -> void:
	if path == "":
		return
	DirAccess.remove_absolute(path)
