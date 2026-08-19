# Piste comme polyligne centrale : liste de points (x, y, z, demi-largeur) en
# Q16.16, tracé fermé OU ouvert selon est_ferme. Sert de base à la conduite
# (hauteur, barrières) et au rendu (res://render/track_mesh.gd).
#
# C'est la représentation en mémoire, PAS le format de fichier de piste
# (map/track_data.gd::to_track() fait la conversion, et propage son propre
# champ est_ferme depuis le fichier .tres).
class_name Track

var point_x: PackedInt64Array = PackedInt64Array()
var point_y: PackedInt64Array = PackedInt64Array()
var point_z: PackedInt64Array = PackedInt64Array()
var half_width: PackedInt64Array = PackedInt64Array()

# true (défaut, comportement historique inchangé) : le dernier point est
# relié au premier, comme un circuit — la porte d'arrivée (sim/race_state.gd)
# est alors au premier segment, confondue avec le départ. false : la piste
# est un tronçon ouvert, point à point (pas de segment de fermeture) — la
# porte d'arrivée passe au DERNIER segment, distinct du départ. Sans ça, sur
# un tracé fermé, le segment fantôme dernier->premier pourrait traverser un
# virage et closest_point() y accrocher la voiture (même piège que celui
# documenté en tête de map/track_hardcoded.gd, en pire sur un tracé ouvert).
# Vient soit d'un TrackData chargé depuis un fichier (map/track_data.gd),
# soit construit directement en mémoire par un banc de mesure isolé
# (tools/bench_rayon.gd).
var est_ferme: bool = true

# Éléments posés (map/element_roster.gd) : uniquement leur PLACEMENT, jamais
# leur apparence — pas de champ variante ici (une variante ne change que le
# modèle 3D/la hitbox, jamais le comportement, voir ElementRoster ; la
# porter jusqu'à sim/ inviterait à violer cette règle). elem_kind est
# reconstruit depuis les ids par map/track_data.gd::to_track() à chaque
# chargement (ElementRoster.kind_for_id()), jamais sérialisé directement.
# elem_y/elem_rotation sont écrits mais pas encore lus par sim/ (réservés à
# la collision orientée des obstacles, hors scope pour l'instant — voir
# CLAUDE.md, section « Éléments de piste »).
var elem_kind: PackedByteArray = PackedByteArray()
var elem_x: PackedInt64Array = PackedInt64Array()
var elem_y: PackedInt64Array = PackedInt64Array()
var elem_z: PackedInt64Array = PackedInt64Array()
var elem_rotation: PackedInt64Array = PackedInt64Array()

func point_count() -> int:
	return point_x.size()

func add_point(x: int, y: int, z: int, hw: int) -> void:
	point_x.push_back(x)
	point_y.push_back(y)
	point_z.push_back(z)
	half_width.push_back(hw)

func element_count() -> int:
	return elem_kind.size()

func add_element(kind: int, x: int, y: int, z: int, rotation: int) -> void:
	elem_kind.push_back(kind)
	elem_x.push_back(x)
	elem_y.push_back(y)
	elem_z.push_back(z)
	elem_rotation.push_back(rotation)

# Projette (px, pz) sur le segment le plus proche de la ligne centrale et
# remplit `result` en place — aucune allocation, `result` est réutilisé à
# chaque tick par res://sim/world.gd.
func closest_point(px: int, pz: int, result: TrackQueryResult) -> void:
	var n: int = point_x.size()
	var segment_count: int = n if est_ferme else n - 1
	var best_dist_sq: int = -1

	for i in range(segment_count):
		var j: int = (i + 1) % n
		var ax: int = point_x[i]
		var az: int = point_z[i]
		var bx: int = point_x[j]
		var bz: int = point_z[j]
		var dx: int = bx - ax
		var dz: int = bz - az
		var seg_len_sq: int = Fixed.mul(dx, dx) + Fixed.mul(dz, dz)
		if seg_len_sq == 0:
			continue

		var wx: int = px - ax
		var wz: int = pz - az
		var dot: int = Fixed.mul(wx, dx) + Fixed.mul(wz, dz)
		var t: int = Fixed.clamp(Fixed.div(dot, seg_len_sq), 0, Fixed.ONE)
		var cx: int = ax + Fixed.mul(dx, t)
		var cz: int = az + Fixed.mul(dz, t)
		var ddx: int = px - cx
		var ddz: int = pz - cz
		var dist_sq: int = Fixed.mul(ddx, ddx) + Fixed.mul(ddz, ddz)

		if best_dist_sq >= 0 and dist_sq >= best_dist_sq:
			continue
		best_dist_sq = dist_sq

		var seg_len: int = FixedMath.sqrt(seg_len_sq)
		var tangent_x: int = Fixed.div(dx, seg_len)
		var tangent_z: int = Fixed.div(dz, seg_len)

		result.segment_index = i
		result.closest_x = cx
		result.closest_z = cz
		result.forward_x = tangent_x
		result.forward_z = tangent_z
		result.right_x = tangent_z
		result.right_z = -tangent_x
		result.lateral_offset = Fixed.mul(ddx, tangent_z) - Fixed.mul(ddz, tangent_x)
		result.height = point_y[i] + Fixed.mul(point_y[j] - point_y[i], t)
		result.half_width = half_width[i] + Fixed.mul(half_width[j] - half_width[i], t)
