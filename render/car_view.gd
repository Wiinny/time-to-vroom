# Représentation visuelle de la voiture : primitives simples, interpole
# entre deux échantillons de CarState. Ne décide de rien — sample() est
# appelé une fois par tick de simulation (depuis main.gd), _process()
# interpole pour le rendu à la fréquence d'affichage.
class_name CarView
extends Node3D

var _prev_pos: Vector3 = Vector3.ZERO
var _cur_pos: Vector3 = Vector3.ZERO
var _prev_yaw: float = 0.0
var _cur_yaw: float = 0.0

# À régler AVANT add_child() — voir CLAUDE.md, piège look_at()/global_transform
# similaire : ces deux champs ne sont lus qu'une fois, dans _ready().
# "" (défaut) = comportement inchangé, VehicleSelection.selected_id (la
# voiture du joueur). Sert au fantôme (main.gd) pour afficher le véhicule
# enregistré dans le replay, indépendant du véhicule courant du joueur.
var vehicle_id_override: String = ""
# < 1.0 = fantôme semi-transparent. 1.0 (défaut) = opaque, comportement
# inchangé pour la voiture du joueur.
var alpha: float = 1.0

func _ready() -> void:
	var vehicle_id: String = vehicle_id_override if vehicle_id_override != "" else VehicleSelection.selected_id
	_build_primitives(vehicle_id)
	if alpha < 1.0:
		_appliquer_transparence(self)

# Parcourt récursivement les enfants (le bonhomme des motos/vaisseau est un
# Node3D imbriqué, voir _add_rider()) et rend transparent tout MeshInstance3D
# dont le matériau est un StandardMaterial3D propre à cette instance —
# jamais partagé entre CarView, donc cette passe ne risque jamais de teinter
# le véhicule du joueur depuis celui du fantôme ou inversement.
func _appliquer_transparence(node: Node) -> void:
	if node is MeshInstance3D:
		var mat: Material = (node as MeshInstance3D).material_override
		if mat is StandardMaterial3D:
			var std_mat: StandardMaterial3D = mat
			var c: Color = std_mat.albedo_color
			std_mat.albedo_color = Color(c.r, c.g, c.b, c.a * alpha)
			std_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			std_mat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_appliquer_transparence(child)

# Silhouette différente par véhicule (voir ui/vehicle_roster.gd) — primitives
# simples assemblées par code, dans le même esprit que le modèle d'origine ;
# pas de modèle 3D importé, ce projet n'en a pas la pipeline (cf. CLAUDE.md,
# "modèles 3D volontairement simples").
func _build_primitives(vehicle_id: String) -> void:
	match vehicle_id:
		"formula":
			_build_formula()
		"superbike":
			_build_superbike()
		"street_bike":
			_build_street_bike()
		"hover":
			_build_hover()
		_:
			_build_gt()  # "gt" et tout ID inconnu retombent sur la voiture de référence

func _add_body(size: Vector3, y: float, color: Color) -> void:
	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = size
	body.mesh = body_mesh
	body.position = Vector3(0.0, y, 0.0)
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = color
	body.material_override = body_mat
	add_child(body)

# Bonhomme très simple (torse + tête + bras), toujours le même modèle,
# seules les couleurs changent d'un véhicule à l'autre pour rester
# distinguables. Nœud séparé (add_child sur un Node3D dédié, pas fusionné
# au corps du véhicule) — uniquement moto/vaisseau, jamais les voitures.
func _add_rider(y: float, suit_color: Color, helmet_color: Color) -> void:
	var rider := Node3D.new()
	rider.position = Vector3(0.0, y, 0.0)
	add_child(rider)

	var suit_mat := StandardMaterial3D.new()
	suit_mat.albedo_color = suit_color

	var torso := MeshInstance3D.new()
	var torso_mesh := CapsuleMesh.new()
	torso_mesh.radius = 0.22
	torso_mesh.height = 0.6
	torso.mesh = torso_mesh
	torso.position = Vector3(0.0, 0.3, 0.0)
	torso.material_override = suit_mat
	rider.add_child(torso)

	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.18
	head_mesh.height = 0.36
	head.mesh = head_mesh
	head.position = Vector3(0.0, 0.68, 0.0)
	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = helmet_color
	head.material_override = head_mat
	rider.add_child(head)

	for side in [-1.0, 1.0]:
		var arm := MeshInstance3D.new()
		var arm_mesh := BoxMesh.new()
		arm_mesh.size = Vector3(0.12, 0.4, 0.12)
		arm.mesh = arm_mesh
		arm.position = Vector3(side * 0.28, 0.35, 0.15)
		arm.rotation.x = -0.5
		arm.material_override = suit_mat
		rider.add_child(arm)

func _add_wheel(offset: Vector3, radius: float, width: float) -> void:
	var wheel := MeshInstance3D.new()
	var wheel_mesh := CylinderMesh.new()
	wheel_mesh.top_radius = radius
	wheel_mesh.bottom_radius = radius
	wheel_mesh.height = width
	wheel.mesh = wheel_mesh
	var wheel_mat := StandardMaterial3D.new()
	wheel_mat.albedo_color = Color(0.05, 0.05, 0.05)
	wheel.material_override = wheel_mat
	wheel.position = offset
	wheel.rotation.z = PI / 2.0
	add_child(wheel)

# gt / Roadster (Forza Horizon) : voiture de référence, gabarit "normal".
func _build_gt() -> void:
	_add_body(Vector3(1.6, 1.0, 4.0), 0.6, Color(0.85, 0.15, 0.1))
	for offset in [Vector3(0.9, 0.35, 1.3), Vector3(-0.9, 0.35, 1.3), Vector3(0.9, 0.35, -1.3), Vector3(-0.9, 0.35, -1.3)]:
		_add_wheel(offset, 0.35, 0.3)

# formula / Needle (Trackmania) : basse, étroite, longue, roues à l'air
# (plus larges que la carrosserie) — silhouette monoplace.
func _build_formula() -> void:
	_add_body(Vector3(1.1, 0.5, 4.6), 0.35, Color(0.1, 0.3, 0.85))
	for offset in [Vector3(1.0, 0.4, 1.6), Vector3(-1.0, 0.4, 1.6), Vector3(1.0, 0.4, -1.6), Vector3(-1.0, 0.4, -1.6)]:
		_add_wheel(offset, 0.4, 0.25)

# superbike / Ironside (Bécane Bowser) : moto lourde, deux grosses roues,
# carrosserie haute et large pour une deux-roues.
func _build_superbike() -> void:
	_add_body(Vector3(0.9, 1.1, 3.0), 0.7, Color(0.55, 0.25, 0.05))
	_add_wheel(Vector3(0.0, 0.5, 1.4), 0.5, 0.35)
	_add_wheel(Vector3(0.0, 0.5, -1.4), 0.5, 0.35)
	_add_rider(1.3, Color(0.12, 0.1, 0.1), Color(0.7, 0.1, 0.1))

# street_bike / Wasp (moto légère MKWii) : deux-roues légère et fine, roues
# plus petites que la superbike.
func _build_street_bike() -> void:
	_add_body(Vector3(0.6, 0.7, 2.6), 0.55, Color(0.9, 0.85, 0.15))
	_add_wheel(Vector3(0.0, 0.35, 1.15), 0.35, 0.2)
	_add_wheel(Vector3(0.0, 0.35, -1.15), 0.35, 0.2)
	_add_rider(0.95, Color(0.85, 0.75, 0.1), Color(0.9, 0.9, 0.9))

# hover / Halcyon (F-Zero) : pas de roues, carlingue basse et large flottant
# au-dessus de la piste, deux ailerons arrière.
func _build_hover() -> void:
	_add_body(Vector3(1.8, 0.4, 3.6), 0.6, Color(0.2, 0.75, 0.85))
	for offset in [Vector3(0.9, 0.7, -1.5), Vector3(-0.9, 0.7, -1.5)]:
		var fin := MeshInstance3D.new()
		var fin_mesh := BoxMesh.new()
		fin_mesh.size = Vector3(0.15, 0.5, 0.3)
		fin.mesh = fin_mesh
		fin.position = offset
		var fin_mat := StandardMaterial3D.new()
		fin_mat.albedo_color = Color(0.2, 0.75, 0.85)
		fin.material_override = fin_mat
		add_child(fin)
	_add_rider(0.9, Color(0.6, 0.65, 0.7), Color(0.2, 0.8, 0.9))

# Appelé une fois par tick de simulation, juste après World.tick().
func sample(state: CarState) -> void:
	_prev_pos = _cur_pos
	_prev_yaw = _cur_yaw
	_cur_pos = Vector3(Fixed.to_float(state.pos_x), Fixed.to_float(state.pos_y), Fixed.to_float(state.pos_z))
	_cur_yaw = _yaw_to_radians(state.yaw)

func _yaw_to_radians(yaw: int) -> float:
	return TAU * float(yaw) / float(FixedMath.FULL_TURN)

func _process(_delta: float) -> void:
	var t: float = Engine.get_physics_interpolation_fraction()
	global_position = _prev_pos.lerp(_cur_pos, t)
	# rotation.y de Godot tourne dans le MÊME sens que notre cap (les deux
	# amènent +Z vers +X quand l'angle augmente) : pas de signe à inverser.
	# Mais Godot considère qu'un nœud "regarde" vers -Z par défaut, alors que
	# notre cap = 0 pointe vers +Z (voir sim/car_sim.gd) — d'où le décalage
	# de PI, sans quoi la caméra de poursuite (qui lit ce basis.z comme
	# "arrière" du véhicule) se place devant la voiture au lieu de derrière.
	rotation.y = lerp_angle(_prev_yaw, _cur_yaw, t) + PI
