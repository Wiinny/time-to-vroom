# Construit le mesh de la piste (ruban de route + murets) depuis un Track,
# une seule fois au chargement. Ne lit jamais l'état de simulation par tick,
# ne décide de rien — pure conversion Q16.16 -> float pour l'affichage.
class_name TrackMesh
extends MeshInstance3D

const WALL_HEIGHT: float = 1.0
const COULEUR_DEPART: Color = Color(0.95, 0.95, 0.95)
const COULEUR_ARRIVEE: Color = Color(0.15, 0.85, 0.30)
const STRIPE_HALF_LEN: float = 1.5  # bande de 3 m dans le sens de la course

func build(track: Track) -> void:
	var n: int = track.point_count()
	if n < 2:
		return
	var closed: bool = track.est_ferme
	var seg_count: int = n if closed else n - 1

	var centers: PackedVector3Array = PackedVector3Array()
	for i in range(n):
		centers.append(Vector3(
			Fixed.to_float(track.point_x[i]),
			Fixed.to_float(track.point_y[i]),
			Fixed.to_float(track.point_z[i])
		))

	var lefts: PackedVector3Array = PackedVector3Array()
	var rights: PackedVector3Array = PackedVector3Array()
	for i in range(n):
		# Sur une piste ouverte, les deux extrémités n'ont pas de voisin des
		# deux côtés : différence à un seul côté plutôt que centrée — sinon la
		# normale du point 0 serait calculée avec le DERNIER point de la
		# piste (à l'autre bout), et le ruban partirait de travers.
		var prev: Vector3 = centers[i]
		var nxt: Vector3 = centers[i]
		if closed or i > 0:
			prev = centers[(i - 1 + n) % n]
		if closed or i < n - 1:
			nxt = centers[(i + 1) % n]
		var dir: Vector3 = nxt - prev
		dir.y = 0.0
		if dir.length() < 0.0001:
			dir = Vector3(0.0, 0.0, 1.0)
		dir = dir.normalized()
		var right: Vector3 = Vector3(dir.z, 0.0, -dir.x)
		var hw: float = Fixed.to_float(track.half_width[i])
		lefts.append(centers[i] - right * hw)
		rights.append(centers[i] + right * hw)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(seg_count):
		var j: int = (i + 1) % n
		_add_quad(st, lefts[i], rights[i], rights[j], lefts[j])
	st.generate_normals()
	mesh = st.commit()

	var road_mat := StandardMaterial3D.new()
	road_mat.albedo_color = Color(0.25, 0.25, 0.28)
	material_override = road_mat

	_build_walls(centers, lefts, rights, seg_count)
	_build_finish_line(centers, track)

func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(d)

func _add_wall_segment(st: SurfaceTool, p0: Vector3, p1: Vector3) -> void:
	var p0_top: Vector3 = p0 + Vector3(0.0, WALL_HEIGHT, 0.0)
	var p1_top: Vector3 = p1 + Vector3(0.0, WALL_HEIGHT, 0.0)
	_add_quad(st, p0, p1, p1_top, p0_top)

# Bandes peintes au sol, purement cosmétiques — elles ne décident de rien,
# elles reflètent la porte calculée par sim/race_state.gd. Circuit : une
# seule bande blanche au point 0, départ ET arrivée sont la même porte
# (segment 0). Piste point à point : blanche au départ (point 0) et verte à
# l'arrivée, sur le DERNIER segment (point n-2) — les deux lieux sont
# distincts et doivent être identifiables sans ambiguïté en jeu.
func _build_finish_line(centers: PackedVector3Array, track: Track) -> void:
	var n: int = centers.size()
	if n < 2:
		return
	_add_ground_stripe(centers, track, 0, COULEUR_DEPART)
	if not track.est_ferme and n >= 3:
		_add_ground_stripe(centers, track, n - 2, COULEUR_ARRIVEE)

func _add_ground_stripe(centers: PackedVector3Array, track: Track, i: int, couleur: Color) -> void:
	var p0: Vector3 = centers[i]
	var tangent: Vector3 = centers[i + 1] - p0
	tangent.y = 0.0
	if tangent.length() < 0.0001:
		return
	tangent = tangent.normalized()
	var right: Vector3 = Vector3(tangent.z, 0.0, -tangent.x)
	var hw: float = Fixed.to_float(track.half_width[i])
	var lift: Vector3 = Vector3(0.0, 0.02, 0.0)  # évite le z-fighting avec la route

	var a: Vector3 = p0 - right * hw - tangent * STRIPE_HALF_LEN + lift
	var b: Vector3 = p0 + right * hw - tangent * STRIPE_HALF_LEN + lift
	var c: Vector3 = p0 + right * hw + tangent * STRIPE_HALF_LEN + lift
	var d: Vector3 = p0 - right * hw + tangent * STRIPE_HALF_LEN + lift

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_quad(st, a, b, c, d)
	st.generate_normals()

	var marker := MeshInstance3D.new()
	marker.mesh = st.commit()
	var marker_mat := StandardMaterial3D.new()
	marker_mat.albedo_color = couleur
	marker.material_override = marker_mat
	add_child(marker)

func _build_walls(centers: PackedVector3Array, lefts: PackedVector3Array, rights: PackedVector3Array, seg_count: int) -> void:
	var n: int = centers.size()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(seg_count):
		var j: int = (i + 1) % n
		_add_wall_segment(st, lefts[i], lefts[j])
		_add_wall_segment(st, rights[j], rights[i])
	st.generate_normals()

	var walls := MeshInstance3D.new()
	walls.mesh = st.commit()
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.7, 0.15, 0.15)
	walls.material_override = wall_mat
	add_child(walls)
