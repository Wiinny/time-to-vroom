# Éditeur de piste — première version (voir CLAUDE.md, section « Éditeur de
# piste »). Scène autonome comme main.tscn, jamais chargée en overlay.
#
# Outil de création, pas de course : contrairement à sim/ et render/, la
# souris pilote ici la caméra et le placement (clic droit maintenu = orbite/
# déplacement caméra façon éditeur Godot, clic gauche = placer/sélectionner).
# La règle CLAUDE.md « la souris ne pilote jamais le gameplay » vise la
# conduite, pas cet outil.
#
# Édition volontairement plate pour cette v1 (tous les points/éléments à
# y = 0) : l'altitude viendra dans une itération suivante.
extends Node3D

const CAMERA_SPEED: float = 12.0
const MOUSE_SENSITIVITY: float = 0.005
const SELECTION_RADIUS: float = 3.0
const DEFAULT_HALF_WIDTH: float = 5.0
const HALF_WIDTH_STEP: float = 0.5

var _track_data: TrackData
var _track_path: String = ""

var _camera: Camera3D
var _looking: bool = false
var _yaw: float = 0.0
var _pitch: float = -0.4

var _path_visual: Node3D
var _elements_visual: Node3D

var _tool_mode: String = "trace"  # "trace" ou "element"
var _current_half_width: float = DEFAULT_HALF_WIDTH
var _armed_type: String = ""
var _armed_variant: String = ""
var _selected_element_index: int = -1

var _status_label: Label
var _name_edit: LineEdit
var _title_edit: LineEdit
var _author_edit: LineEdit

func _ready() -> void:
	_build_scene()
	_build_ui()
	_load_pending_track()
	_rebuild_path_visual()
	_rebuild_elements_visual()
	_refresh_status()

func _build_scene() -> void:
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.5, 0.7, 0.9)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(1, 1, 1)
	environment.ambient_light_energy = 0.6
	env.environment = environment
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45.0, -30.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400.0, 400.0)
	ground.mesh = plane
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.3, 0.45, 0.3)
	ground.material_override = ground_mat
	add_child(ground)

	_camera = Camera3D.new()
	_camera.position = Vector3(0.0, 12.0, 18.0)
	_camera.rotation.x = -0.5
	_pitch = -0.5
	add_child(_camera)

	_path_visual = Node3D.new()
	add_child(_path_visual)

	_elements_visual = Node3D.new()
	add_child(_elements_visual)

func _load_pending_track() -> void:
	if Session.pending_track_path != "":
		var data: TrackData = TrackData.load_from_path(Session.pending_track_path)
		if data != null:
			_track_data = data
			_track_path = Session.pending_track_path
		Session.pending_track_path = ""
	if _track_data == null:
		_track_data = TrackData.new()

	# Ré-ouvrir une piste existante doit refléter son nom de fichier et ses
	# nom/auteur dans les champs — sinon _on_save_pressed() sauvegarderait
	# sous "ma_piste.tres" par défaut au lieu du fichier d'origine.
	if _track_path != "":
		_name_edit.text = _track_path.get_file().get_basename()
	_title_edit.text = _track_data.nom
	_author_edit.text = _track_data.auteur

# ---------------------------------------------------------------- caméra --

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_looking = event.pressed
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _looking else Input.MOUSE_MODE_VISIBLE
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not _looking:
			_on_click(event.position)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _looking:
		_yaw -= event.relative.x * MOUSE_SENSITIVITY
		_pitch = clampf(_pitch - event.relative.y * MOUSE_SENSITIVITY, -1.5, 1.5)
		_camera.rotation = Vector3(_pitch, _yaw, 0.0)

func _process(delta: float) -> void:
	if not _looking:
		return
	# Touches physiques directes, pas Controls/InputMap : les actions de
	# conduite rebindables (accelerer/gauche/...) n'ont rien à voir avec la
	# caméra libre de l'éditeur — les mélanger prêterait à confusion si le
	# joueur a remappé ses touches de conduite.
	var move := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		move -= _camera.transform.basis.z
	if Input.is_key_pressed(KEY_S):
		move += _camera.transform.basis.z
	if Input.is_key_pressed(KEY_A):
		move -= _camera.transform.basis.x
	if Input.is_key_pressed(KEY_D):
		move += _camera.transform.basis.x
	if Input.is_key_pressed(KEY_SPACE):
		move += Vector3.UP
	if Input.is_key_pressed(KEY_SHIFT):
		move -= Vector3.UP
	if move.length() > 0.0:
		_camera.position += move.normalized() * CAMERA_SPEED * delta

func _ray_ground_point(mouse_pos: Vector2) -> Vector3:
	var from: Vector3 = _camera.project_ray_origin(mouse_pos)
	var dir: Vector3 = _camera.project_ray_normal(mouse_pos)
	if dir.y >= -0.0001:
		return from + dir * 30.0  # vise à l'horizontale ou vers le haut : point arbitraire devant la caméra
	var t: float = -from.y / dir.y
	return from + dir * t

# ------------------------------------------------------------- placement --

func _on_click(mouse_pos: Vector2) -> void:
	var point: Vector3 = _ray_ground_point(mouse_pos)
	if _tool_mode == "trace":
		# Quantification en Q16.16 au moment où le point est posé, jamais
		# plus tard — même principe que main.gd::_quantize_uni/_quantize_bi.
		_track_data.add_point(Fixed.from_float(point.x), Fixed.from_int(0), Fixed.from_float(point.z), Fixed.from_float(_current_half_width))
		_rebuild_path_visual()
	else:
		if _armed_type != "":
			_track_data.add_element(_armed_type, _armed_variant, Fixed.from_float(point.x), Fixed.from_int(0), Fixed.from_float(point.z), 0)
			_rebuild_elements_visual()
		else:
			_select_nearest_element(point)
	_refresh_status()

func _select_nearest_element(point: Vector3) -> void:
	var best_i: int = -1
	var best_d: float = SELECTION_RADIUS
	for i in range(_track_data.elements.size()):
		var e: Dictionary = _track_data.elements[i]
		var ex: float = Fixed.to_float(e["pos_x"])
		var ez: float = Fixed.to_float(e["pos_z"])
		var d: float = Vector2(ex, ez).distance_to(Vector2(point.x, point.z))
		if d < best_d:
			best_d = d
			best_i = i
	_selected_element_index = best_i
	_rebuild_elements_visual()

# --------------------------------------------------------------- visuels --

func _rebuild_path_visual() -> void:
	for child in _path_visual.get_children():
		child.queue_free()

	var n: int = _track_data.point_count()
	var pts: PackedVector3Array = PackedVector3Array()
	for i in range(n):
		var p := Vector3(Fixed.to_float(_track_data.point_x[i]), Fixed.to_float(_track_data.point_y[i]), Fixed.to_float(_track_data.point_z[i]))
		pts.append(p)

		var marker := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.4
		sphere.height = 0.8
		marker.mesh = sphere
		marker.position = p + Vector3(0.0, 0.4, 0.0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.9, 0.2)
		marker.material_override = mat
		_path_visual.add_child(marker)

	if n >= 2:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_LINES)
		for i in range(n - 1):
			st.add_vertex(pts[i] + Vector3(0.0, 0.05, 0.0))
			st.add_vertex(pts[i + 1] + Vector3(0.0, 0.05, 0.0))
		var line := MeshInstance3D.new()
		line.mesh = st.commit()
		var line_mat := StandardMaterial3D.new()
		line_mat.albedo_color = Color(0.2, 0.9, 1.0)
		line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		line.material_override = line_mat
		_path_visual.add_child(line)

func _rebuild_elements_visual() -> void:
	for child in _elements_visual.get_children():
		child.queue_free()

	for i in range(_track_data.elements.size()):
		var e: Dictionary = _track_data.elements[i]
		var marker := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.8, 0.8, 0.8)
		marker.mesh = box
		marker.position = Vector3(Fixed.to_float(e["pos_x"]), Fixed.to_float(e["pos_y"]), Fixed.to_float(e["pos_z"])) + Vector3(0.0, 0.4, 0.0)
		marker.rotation.y = float(e["rotation"]) / 65536.0 * TAU
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.15, 0.15) if i == _selected_element_index else ElementRoster.color_for_type(e["type"])
		marker.material_override = mat
		_elements_visual.add_child(marker)

# -------------------------------------------------------------------- UI --

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.position = Vector2(8.0, 8.0)
	top.add_theme_constant_override("separation", 8)
	layer.add_child(top)

	var trace_button := Button.new()
	trace_button.text = "Tracé"
	trace_button.pressed.connect(_on_mode_pressed.bind("trace"))
	top.add_child(trace_button)

	var element_button := Button.new()
	element_button.text = "Élément"
	element_button.pressed.connect(_on_mode_pressed.bind("element"))
	top.add_child(element_button)

	var width_minus := Button.new()
	width_minus.text = "Largeur -"
	width_minus.pressed.connect(_on_width_changed.bind(-HALF_WIDTH_STEP))
	top.add_child(width_minus)

	var width_plus := Button.new()
	width_plus.text = "Largeur +"
	width_plus.pressed.connect(_on_width_changed.bind(HALF_WIDTH_STEP))
	top.add_child(width_plus)

	var remove_point := Button.new()
	remove_point.text = "Retirer dernier point"
	remove_point.pressed.connect(_on_remove_point_pressed)
	top.add_child(remove_point)

	var remove_element := Button.new()
	remove_element.text = "Supprimer l'élément sélectionné"
	remove_element.pressed.connect(_on_remove_element_pressed)
	top.add_child(remove_element)

	_status_label = Label.new()
	_status_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_status_label.position = Vector2(8.0, 40.0)
	layer.add_child(_status_label)

	var palette_scroll := ScrollContainer.new()
	palette_scroll.position = Vector2(8.0, 72.0)
	palette_scroll.custom_minimum_size = Vector2(260.0, 480.0)
	layer.add_child(palette_scroll)

	var palette := VBoxContainer.new()
	palette.add_theme_constant_override("separation", 4)
	palette_scroll.add_child(palette)

	var none_row := Button.new()
	none_row.text = "(Sélection — rien à placer)"
	none_row.pressed.connect(_on_arm_pressed.bind("", ""))
	palette.add_child(none_row)

	for entry in ElementRoster.ELEMENTS:
		var row := HBoxContainer.new()
		palette.add_child(row)
		var label := Label.new()
		label.text = entry["nom"]
		label.custom_minimum_size = Vector2(150.0, 0.0)
		row.add_child(label)
		for v in entry["variants"]:
			var vbutton := Button.new()
			vbutton.text = v["nom"]
			vbutton.pressed.connect(_on_arm_pressed.bind(entry["id"], v["id"]))
			row.add_child(vbutton)

	var bottom := HBoxContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.position = Vector2(8.0, -40.0)
	bottom.add_theme_constant_override("separation", 8)
	layer.add_child(bottom)

	_title_edit = LineEdit.new()
	_title_edit.placeholder_text = "Nom de la course"
	_title_edit.custom_minimum_size = Vector2(160.0, 0.0)
	bottom.add_child(_title_edit)

	_author_edit = LineEdit.new()
	_author_edit.placeholder_text = "Créée par"
	_author_edit.custom_minimum_size = Vector2(140.0, 0.0)
	bottom.add_child(_author_edit)

	_name_edit = LineEdit.new()
	_name_edit.text = "ma_piste"
	_name_edit.custom_minimum_size = Vector2(160.0, 0.0)
	bottom.add_child(_name_edit)

	var save_button := Button.new()
	save_button.text = "Sauvegarder"
	save_button.pressed.connect(_on_save_pressed)
	bottom.add_child(save_button)

	var play_button := Button.new()
	play_button.text = "Jouer cette piste"
	play_button.pressed.connect(_on_play_pressed)
	bottom.add_child(play_button)

	var publish_button := Button.new()
	publish_button.text = "Publier (bientôt disponible)"
	publish_button.disabled = true
	bottom.add_child(publish_button)

	var back_button := Button.new()
	back_button.text = "Retour"
	back_button.pressed.connect(_on_back_pressed)
	bottom.add_child(back_button)

func _on_mode_pressed(mode: String) -> void:
	_tool_mode = mode
	_refresh_status()

func _on_width_changed(delta: float) -> void:
	_current_half_width = clampf(_current_half_width + delta, 1.0, 20.0)
	_refresh_status()

func _on_remove_point_pressed() -> void:
	_track_data.remove_last_point()
	_rebuild_path_visual()
	_refresh_status()

func _on_remove_element_pressed() -> void:
	if _selected_element_index >= 0:
		_track_data.remove_element(_selected_element_index)
		_selected_element_index = -1
		_rebuild_elements_visual()
		_refresh_status()

func _on_arm_pressed(type_id: String, variant_id: String) -> void:
	_armed_type = type_id
	_armed_variant = variant_id
	_refresh_status()

func _refresh_status() -> void:
	var mode_txt: String = "Tracé (clic = ajoute un point)" if _tool_mode == "trace" else "Élément"
	var armed_txt: String = ""
	if _tool_mode == "element":
		if _armed_type != "":
			var entry: Dictionary = ElementRoster.find(_armed_type)
			var variant: Dictionary = ElementRoster.find_variant(entry, _armed_variant)
			armed_txt = " — armé : %s (%s), clic = placer" % [entry.get("nom", _armed_type), variant.get("nom", _armed_variant)]
		else:
			armed_txt = " — clic sur un élément = sélectionner"
	var boucle_txt: String = "oui" if _track_data.est_ferme else "non"
	_status_label.text = "Mode : %s%s | Largeur : %.1f m | Points : %d | Éléments : %d | Boucle : %s" % [
		mode_txt, armed_txt, _current_half_width, _track_data.point_count(), _track_data.elements.size(), boucle_txt
	]

func _on_save_pressed() -> void:
	DirAccess.make_dir_recursive_absolute("user://tracks")
	# validate_filename() remplace les caractères interdits (dont "/") par
	# "_" : sans ça, un nom comme "a/b" produisait un chemin invalide et
	# ResourceSaver.save() échouait en silence (juste un push_warning, rien
	# à l'écran).
	var file_name: String = _name_edit.text.strip_edges().validate_filename()
	if file_name.is_empty():
		file_name = "ma_piste"
	_track_path = "user://tracks/%s.tres" % file_name
	_track_data.nom = _title_edit.text.strip_edges()
	_track_data.auteur = _author_edit.text.strip_edges()
	_track_data.ensure_uid()
	var err: Error = ResourceSaver.save(_track_data, _track_path)
	if err != OK:
		push_warning("TrackEditor: échec de sauvegarde de %s (%s)" % [_track_path, error_string(err)])

func _on_play_pressed() -> void:
	if _track_data.point_count() < 2:
		return
	if _track_path == "":
		_on_save_pressed()
	else:
		ResourceSaver.save(_track_data, _track_path)
	Session.pending_track_path = _track_path
	get_tree().change_scene_to_file("res://main.tscn")

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
