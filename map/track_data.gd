# Format de fichier de piste — sauvegardé/chargé via ResourceSaver/
# ResourceLoader vers user://tracks/<nom>.tres. C'est un Resource Godot
# natif (versionné, typé), pas un format maison à parser.
#
# Ce n'est PAS le Track utilisé par la simulation (map/track.gd) : to_track()
# fait la conversion, comme CarConfig.bake() convertit des valeurs humaines
# en grandeurs Q16.16. Les positions restent en Q16.16 ici aussi — c'est
# res://editor/track_editor.gd qui quantifie les positions flottantes de la
# souris/caméra au moment où un point ou un élément est posé (même principe
# que main.gd::_quantize_uni/_quantize_bi pour les inputs de conduite),
# jamais la simulation elle-même.
class_name TrackData
extends Resource

@export var format_version: int = 2

# Identité affichée dans l'écran de sélection de piste (ui/track_select.gd) —
# `uid` est la clé de leaderboard, générée une seule fois par ensure_uid() à
# la première sauvegarde (jamais recalculée, jamais dans la simulation) pour
# que renommer le fichier .tres ne fasse pas perdre les records associés.
@export var uid: String = ""
@export var nom: String = ""
@export var auteur: String = ""

@export var point_x: PackedInt64Array = PackedInt64Array()
@export var point_y: PackedInt64Array = PackedInt64Array()
@export var point_z: PackedInt64Array = PackedInt64Array()
@export var half_width: PackedInt64Array = PackedInt64Array()

# false : piste point à point (rallye) — le dernier point n'est PAS relié au
# premier, et la ligne d'arrivée est calculée sur le DERNIER segment au lieu
# du premier (voir sim/race_state.gd). true (défaut) = circuit, comportement
# historique : les .tres déjà sauvegardés n'ont pas cette clé et Godot leur
# applique le défaut — aucune migration nécessaire.
@export var est_ferme: bool = true

# Un élément : {"type": String (ElementRoster id), "variant": String,
# "pos_x"/"pos_y"/"pos_z": int Q16.16, "rotation": int (unités brutes,
# convention FixedMath — 65536 = un tour, comme CarState.yaw)}. La variante
# reste purement déclarative (apparence uniquement, voir ElementRoster) ;
# le type est branché dans sim/ depuis le lot "Effets des éléments de piste"
# — to_track() le résout vers Track.elem_kind via ElementRoster.kind_for_id()
# (voir CLAUDE.md, section « Éléments de piste » pour la matrice Lot A/Lot B).
@export var elements: Array[Dictionary] = []

func point_count() -> int:
	return point_x.size()

func add_point(x: int, y: int, z: int, hw: int) -> void:
	point_x.push_back(x)
	point_y.push_back(y)
	point_z.push_back(z)
	half_width.push_back(hw)

func remove_last_point() -> void:
	var n: int = point_count()
	if n == 0:
		return
	point_x.resize(n - 1)
	point_y.resize(n - 1)
	point_z.resize(n - 1)
	half_width.resize(n - 1)

func add_element(type: String, variant: String, x: int, y: int, z: int, rotation: int) -> void:
	elements.append({"type": type, "variant": variant, "pos_x": x, "pos_y": y, "pos_z": z, "rotation": rotation})

func remove_element(index: int) -> void:
	if index >= 0 and index < elements.size():
		elements.remove_at(index)

# Construit un Track jouable (centre + demi-largeur uniquement). Il faut au
# moins 2 points pour qu'un segment existe ; est_ferme décide si le dernier
# point est relié au premier (Track.closest_point(), sim/race_state.gd,
# render/track_mesh.gd en dépendent tous les trois).
func to_track() -> Track:
	var track := Track.new()
	track.est_ferme = est_ferme
	for i in range(point_count()):
		track.add_point(point_x[i], point_y[i], point_z[i], half_width[i])
	# Tolérant aux dictionnaires mal formés (même patron que Controls/
	# Leaderboard) : un id inconnu ou un champ manquant est ignoré plutôt que
	# de faire planter le chargement de la piste.
	for e in elements:
		if not (e is Dictionary):
			continue
		var kind: int = ElementRoster.kind_for_id(String(e.get("type", "")))
		if kind == ElementRoster.Kind.INCONNU:
			continue
		track.add_element(kind, int(e.get("pos_x", 0)), int(e.get("pos_y", 0)), int(e.get("pos_z", 0)), int(e.get("rotation", 0)))
	return track

# [x, y, z, cap] du point de départ, en Q16.16 pour la position et en unités
# FixedMath pour le cap (65536 = un tour, comme CarState.yaw) — même contrat
# que TrackHardcoded.start_transform(), les appelants (main.gd,
# tools/run_tests.gd) les consomment tels quels, sans reconversion. Le cap
# est dérivé du premier segment : le figer à 0 faisait apparaître la voiture
# face au +Z quel que soit le tracé (sans effet visible sur un circuit qui
# démarre plein nord, mais elle partait hors piste dès le premier tick sur
# toute autre orientation).
func start_transform() -> PackedInt64Array:
	if point_count() == 0:
		return PackedInt64Array([0, 0, 0, 0])
	var yaw: int = 0
	if point_count() >= 2:
		yaw = FixedMath.atan2(point_x[1] - point_x[0], point_z[1] - point_z[0])
	return PackedInt64Array([point_x[0], point_y[0], point_z[0], yaw])

# Générée une seule fois, à la première sauvegarde — un appel ultérieur est
# un no-op. Pas de randi() : combine nom/auteur/horodatage via FixedHash
# (res://core/hash.gd), suffisant pour un identifiant local jamais réutilisé,
# et de toute façon hors simulation (outillage éditeur uniquement).
func ensure_uid() -> void:
	if uid != "":
		return
	var h: int = FixedHash.start()
	h = FixedHash.combine(h, nom.hash())
	h = FixedHash.combine(h, auteur.hash())
	h = FixedHash.combine(h, int(Time.get_unix_time_from_system() * 1000.0))
	uid = "piste_%d" % (h & 0x7fffffffffffffff)

# Charge une piste et migre les .tres antérieurs au format_version 2 (pas
# d'uid) : uid retombe sur le nom de fichier pour préserver les records déjà
# enregistrés sous cet identifiant (voir CLAUDE.md, section « Éditeur de
# piste »). Migration en mémoire seulement — persistée à la prochaine
# sauvegarde depuis l'éditeur, jamais réécrite ici. Renvoie null si le
# fichier n'est pas une TrackData valide.
static func load_from_path(path: String) -> TrackData:
	var loaded: Resource = ResourceLoader.load(path)
	if not (loaded is TrackData):
		return null
	var data: TrackData = loaded
	if data.uid == "":
		var base: String = path.get_file().get_basename()
		data.uid = base
		if data.nom == "":
			data.nom = base
	return data
