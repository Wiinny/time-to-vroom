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

	var asphalt_st := SurfaceTool.new()
	var dirt_st := SurfaceTool.new()
	var mud_st := SurfaceTool.new()
	asphalt_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	dirt_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	mud_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var asphalt_count: int = 0
	var dirt_count: int = 0
	var mud_count: int = 0
	for i in range(seg_count):
		var j: int = (i + 1) % n
		var surface: int = track.surface_kind[i] if i < track.surface_kind.size() else Track.Surface.ASPHALTE
		var target: SurfaceTool = asphalt_st
		match surface:
			Track.Surface.TERRE:
				target = dirt_st
				dirt_count += 1
			Track.Surface.BOUE:
				target = mud_st
				mud_count += 1
			_:
				asphalt_count += 1
		_add_quad(target, lefts[i], rights[i], rights[j], lefts[j])

	_commit_road_surface(asphalt_st, asphalt_count, Color(0.105, 0.115, 0.13), true)
	_commit_road_surface(dirt_st, dirt_count, Color(0.34, 0.19, 0.075), asphalt_count == 0)
	_commit_road_surface(mud_st, mud_count, Color(0.105, 0.062, 0.028), asphalt_count == 0 and dirt_count == 0)

	_build_ground(centers, track.visual_theme)
	_build_curbs(centers, lefts, rights, seg_count)
	_build_walls(centers, lefts, rights, seg_count, track.visual_theme)
	_build_finish_line(centers, track)
	_build_start_gantry(centers, track)
	if track.visual_theme == "jungle":
		_build_jungle_decor(centers, lefts, rights, seg_count)
		_build_jungle_landmarks()

func _commit_road_surface(st: SurfaceTool, count: int, color: Color, use_self: bool) -> void:
	if count == 0:
		return
	st.generate_normals()
	var committed: ArrayMesh = st.commit()
	var road_mat := StandardMaterial3D.new()
	road_mat.albedo_color = color
	road_mat.roughness = 0.98
	if use_self:
		mesh = committed
		material_override = road_mat
	else:
		var part := MeshInstance3D.new()
		part.mesh = committed
		part.material_override = road_mat
		add_child(part)

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

func _build_walls(centers: PackedVector3Array, lefts: PackedVector3Array, rights: PackedVector3Array, seg_count: int, theme: String) -> void:
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
	wall_mat.albedo_color = Color(0.22, 0.105, 0.035) if theme == "jungle" else Color(0.16, 0.18, 0.21)
	wall_mat.metallic = 0.0 if theme == "jungle" else 0.65
	wall_mat.roughness = 0.92 if theme == "jungle" else 0.38
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

func _build_ground(centers: PackedVector3Array, theme: String) -> void:
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
	ground_mat.albedo_color = Color(0.025, 0.115, 0.035) if theme == "jungle" else Color(0.055, 0.095, 0.06)
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
	if track.visual_theme == "jungle":
		_add_gantry_box(root, Vector3(-hw - 0.45, 4.7, 0.0), Vector3(0.65, 1.35, 0.65))
		_add_gantry_box(root, Vector3(hw + 0.45, 4.7, 0.0), Vector3(0.65, 1.35, 0.65))

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

func _build_jungle_decor(centers: PackedVector3Array, lefts: PackedVector3Array, rights: PackedVector3Array, seg_count: int) -> void:
	var trunk_transforms: Array[Transform3D] = []
	var crown_transforms: Array[Transform3D] = []
	var fern_transforms: Array[Transform3D] = []
	for i in range(0, seg_count, 2):
		var j: int = (i + 1) % centers.size()
		var tangent: Vector3 = centers[j] - centers[i]
		tangent.y = 0.0
		if tangent.length() < 0.001:
			continue
		tangent = tangent.normalized()
		var right: Vector3 = Vector3(tangent.z, 0.0, -tangent.x)
		for side in [-1, 1]:
			var edge: Vector3 = rights[i] if side > 0 else lefts[i]
			var distance: float = 8.0 + float((i * 7 + side * 3 + 30) % 11)
			var along: float = float((i * 13 + side * 5 + 40) % 9) - 4.0
			var pos: Vector3 = edge + right * distance * float(side) + tangent * along
			var scale_factor: float = 0.82 + float((i * 17 + side * 2 + 20) % 7) * 0.07
			trunk_transforms.append(Transform3D(Basis().scaled(Vector3(scale_factor, scale_factor, scale_factor)), pos + Vector3.UP * 2.3 * scale_factor))
			crown_transforms.append(Transform3D(Basis().scaled(Vector3(scale_factor, scale_factor, scale_factor)), pos + Vector3.UP * 6.0 * scale_factor))
			fern_transforms.append(Transform3D(Basis(Vector3.UP, float((i * 97 + side * 31) % 360) * PI / 180.0).scaled(Vector3(scale_factor, scale_factor, scale_factor)), edge + right * (3.1 + float(i % 3)) * float(side) + Vector3.UP * 0.35))

	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.34
	trunk_mesh.bottom_radius = 0.58
	trunk_mesh.height = 4.6
	trunk_mesh.radial_segments = 7
	trunk_mesh.material = _material(Color(0.19, 0.075, 0.025), 1.0)
	_add_multimesh(trunk_mesh, trunk_transforms)

	var crown_mesh := SphereMesh.new()
	crown_mesh.radius = 3.6
	crown_mesh.height = 5.0
	crown_mesh.radial_segments = 10
	crown_mesh.rings = 6
	crown_mesh.material = _material(Color(0.025, 0.28, 0.055), 0.93)
	_add_multimesh(crown_mesh, crown_transforms)

	var fern_mesh := QuadMesh.new()
	fern_mesh.size = Vector2(2.8, 1.25)
	fern_mesh.orientation = PlaneMesh.FACE_Y
	fern_mesh.material = _material(Color(0.08, 0.42, 0.095), 0.96)
	_add_multimesh(fern_mesh, fern_transforms)

func _add_multimesh(source_mesh: Mesh, transforms: Array[Transform3D]) -> void:
	if transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = source_mesh
	mm.instance_count = transforms.size()
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = mm
	add_child(instance)

func _build_jungle_landmarks() -> void:
	var stone: StandardMaterial3D = _material(Color(0.16, 0.23, 0.12), 1.0)
	for base_pos in [Vector3(128.0, 0.0, -58.0), Vector3(-101.0, 0.0, -42.0)]:
		_add_decor_box(base_pos + Vector3(0.0, 2.2, 0.0), Vector3(3.2, 4.4, 3.2), stone)
		_add_decor_box(base_pos + Vector3(0.0, 5.0, 0.0), Vector3(4.4, 1.2, 4.4), stone)
	var water_mat: StandardMaterial3D = _material(Color(0.025, 0.24, 0.21), 0.18)
	water_mat.metallic = 0.25
	var pool := MeshInstance3D.new()
	var pool_mesh := CylinderMesh.new()
	pool_mesh.top_radius = 18.0
	pool_mesh.bottom_radius = 18.0
	pool_mesh.height = 0.12
	pool_mesh.radial_segments = 32
	pool_mesh.material = water_mat
	pool.mesh = pool_mesh
	pool.position = Vector3(-82.0, 0.0, -70.0)
	add_child(pool)

func _add_decor_box(pos: Vector3, size: Vector3, material: Material) -> void:
	var part := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = material
	part.mesh = box
	part.position = pos
	add_child(part)

func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	return mat
