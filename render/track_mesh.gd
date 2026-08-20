class_name TrackMesh
extends MeshInstance3D

const WALL_HEIGHT: float = 1.0
const COULEUR_DEPART: Color = Color(0.95, 0.95, 0.95)
const COULEUR_ARRIVEE: Color = Color(0.15, 0.85, 0.30)
const STRIPE_HALF_LEN: float = 1.5 
const CURB_WIDTH: float = 0.55
const CURB_BLOCK_LENGTH: float = 3.0

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
	road_mat.albedo_color = Color(0.105, 0.115, 0.13)
	road_mat.roughness = 0.88
	material_override = road_mat

	_build_ground(centers)
	_build_curbs(centers, lefts, rights, seg_count)
	_build_walls(centers, lefts, rights, seg_count)
	_build_finish_line(centers, track)
	_build_start_gantry(centers, track)

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

func _build_finish_line(centers: PackedVector3Array, track: Track) -> void:
	var n: int = centers.size()
	if n < 2:
		return
	_add_checkered_stripe(centers, track, 0)
	if not track.est_ferme and n >= 3:
		_add_ground_stripe(centers, track, n - 2, COULEUR_ARRIVEE)

func _add_checkered_stripe(centers: PackedVector3Array, track: Track, i: int) -> void:
	var p0: Vector3 = centers[i]
	var tangent: Vector3 = centers[i + 1] - p0
	tangent.y = 0.0
	if tangent.length() < 0.0001:
		return
	tangent = tangent.normalized()
	var right: Vector3 = Vector3(tangent.z, 0.0, -tangent.x)
	var hw: float = Fixed.to_float(track.half_width[i])
	var columns: int = 10
	var rows: int = 2
	var white_st := SurfaceTool.new()
	var dark_st := SurfaceTool.new()
	white_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	dark_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in range(rows):
		var along_a: float = lerpf(-STRIPE_HALF_LEN, STRIPE_HALF_LEN, float(row) / float(rows))
		var along_b: float = lerpf(-STRIPE_HALF_LEN, STRIPE_HALF_LEN, float(row + 1) / float(rows))
		for column in range(columns):
			var side_a: float = lerpf(-hw, hw, float(column) / float(columns))
			var side_b: float = lerpf(-hw, hw, float(column + 1) / float(columns))
			var lift := Vector3(0.0, 0.025, 0.0)
			var a: Vector3 = p0 + right * side_a + tangent * along_a + lift
			var b: Vector3 = p0 + right * side_b + tangent * along_a + lift
			var c: Vector3 = p0 + right * side_b + tangent * along_b + lift
			var d: Vector3 = p0 + right * side_a + tangent * along_b + lift
			_add_quad(white_st if (row + column) % 2 == 0 else dark_st, a, b, c, d)
	_commit_colored_surface(white_st, Color(0.95, 0.95, 0.92))
	_commit_colored_surface(dark_st, Color(0.025, 0.03, 0.04))

func _add_ground_stripe(centers: PackedVector3Array, track: Track, i: int, couleur: Color) -> void:
	var p0: Vector3 = centers[i]
	var tangent: Vector3 = centers[i + 1] - p0
	tangent.y = 0.0
	if tangent.length() < 0.0001:
		return
	tangent = tangent.normalized()
	var right: Vector3 = Vector3(tangent.z, 0.0, -tangent.x)
	var hw: float = Fixed.to_float(track.half_width[i])
	var lift: Vector3 = Vector3(0.0, 0.02, 0.0)  

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
	wall_mat.albedo_color = Color(0.16, 0.18, 0.21)
	wall_mat.metallic = 0.65
	wall_mat.roughness = 0.38
	walls.material_override = wall_mat
	add_child(walls)

func _build_curbs(centers: PackedVector3Array, lefts: PackedVector3Array, rights: PackedVector3Array, seg_count: int) -> void:
	var red_st := SurfaceTool.new()
	var white_st := SurfaceTool.new()
	red_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	white_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var block_index: int = 0
	var n: int = centers.size()
	for i in range(seg_count):
		var j: int = (i + 1) % n
		var segment_length: float = maxf(centers[i].distance_to(centers[j]), 0.001)
		var blocks: int = maxi(1, ceili(segment_length / CURB_BLOCK_LENGTH))
		for block in range(blocks):
			var t0: float = float(block) / float(blocks)
			var t1: float = float(block + 1) / float(blocks)
			var center0: Vector3 = centers[i].lerp(centers[j], t0)
			var center1: Vector3 = centers[i].lerp(centers[j], t1)
			var left0: Vector3 = lefts[i].lerp(lefts[j], t0) + Vector3.UP * 0.018
			var left1: Vector3 = lefts[i].lerp(lefts[j], t1) + Vector3.UP * 0.018
			var right0: Vector3 = rights[i].lerp(rights[j], t0) + Vector3.UP * 0.018
			var right1: Vector3 = rights[i].lerp(rights[j], t1) + Vector3.UP * 0.018
			var left_inner0: Vector3 = left0.move_toward(center0, CURB_WIDTH)
			var left_inner1: Vector3 = left1.move_toward(center1, CURB_WIDTH)
			var right_inner0: Vector3 = right0.move_toward(center0, CURB_WIDTH)
			var right_inner1: Vector3 = right1.move_toward(center1, CURB_WIDTH)
			var target: SurfaceTool = red_st if block_index % 2 == 0 else white_st
			_add_quad(target, left0, left1, left_inner1, left_inner0)
			_add_quad(target, right_inner0, right_inner1, right1, right0)
			block_index += 1
	_commit_colored_surface(red_st, Color(0.78, 0.055, 0.045))
	_commit_colored_surface(white_st, Color(0.93, 0.91, 0.84))

func _build_ground(centers: PackedVector3Array) -> void:
	var min_x: float = centers[0].x
	var max_x: float = centers[0].x
	var min_z: float = centers[0].z
	var max_z: float = centers[0].z
	var min_y: float = centers[0].y
	for p in centers:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_z = minf(min_z, p.z)
		max_z = maxf(max_z, p.z)
		min_y = minf(min_y, p.y)
	var margin: float = 55.0
	var ground := MeshInstance3D.new()
	var ground_mesh := BoxMesh.new()
	ground_mesh.size = Vector3(max_x - min_x + margin * 2.0, 0.3, max_z - min_z + margin * 2.0)
	ground.mesh = ground_mesh
	ground.position = Vector3((min_x + max_x) * 0.5, min_y - 0.18, (min_z + max_z) * 0.5)
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.055, 0.095, 0.06)
	ground_mat.roughness = 1.0
	ground.material_override = ground_mat
	add_child(ground)

func _build_start_gantry(centers: PackedVector3Array, track: Track) -> void:
	if centers.size() < 2:
		return
	var tangent: Vector3 = centers[1] - centers[0]
	tangent.y = 0.0
	if tangent.length() < 0.0001:
		return
	tangent = tangent.normalized()
	var right: Vector3 = Vector3(tangent.z, 0.0, -tangent.x)
	var hw: float = Fixed.to_float(track.half_width[0])
	var root := Node3D.new()
	root.position = centers[0]
	root.rotation.y = atan2(-right.z, right.x)
	add_child(root)
	_add_gantry_box(root, Vector3(-hw - 0.45, 2.15, 0.0), Vector3(0.28, 4.3, 0.28))
	_add_gantry_box(root, Vector3(hw + 0.45, 2.15, 0.0), Vector3(0.28, 4.3, 0.28))
	_add_gantry_box(root, Vector3(0.0, 4.15, 0.0), Vector3(hw * 2.0 + 1.2, 0.32, 0.32))

func _add_gantry_box(parent: Node3D, pos: Vector3, size: Vector3) -> void:
	var part := MeshInstance3D.new()
	var part_mesh := BoxMesh.new()
	part_mesh.size = size
	part.mesh = part_mesh
	part.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.055, 0.06, 0.07)
	mat.metallic = 0.8
	mat.roughness = 0.3
	part.material_override = mat
	parent.add_child(part)

func _commit_colored_surface(st: SurfaceTool, color: Color) -> void:
	st.generate_normals()
	var instance := MeshInstance3D.new()
	instance.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.78
	instance.material_override = mat
	add_child(instance)
