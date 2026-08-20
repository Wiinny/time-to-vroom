extends Node3D

const REC_CHUNK: int = 6000 
const VALIDATION_MAX_TICKS: int = 60000
const VALIDER_APRES_RUN: bool = true

var _track_id: String = TrackCatalog.BUILTIN_UID

var _world: World = World.new()
var _input: InputFrame = InputFrame.new() 
var _track: Track
var _config: CarConfig
var _start: PackedInt64Array
var _elements: Array[Dictionary] = []  

var _car_view: CarView
var _camera: ChaseCamera
var _hud: Hud
var _pause_menu: PauseMenu
var _finish_menu: FinishMenu
var _paused: bool = false
var _run_over: bool = false 

var _rec_accel: PackedByteArray = PackedByteArray()
var _rec_frein: PackedByteArray = PackedByteArray()
var _rec_braquage: PackedByteArray = PackedByteArray()
var _rec_derapage: PackedByteArray = PackedByteArray()
var _rec_count: int = 0
var _rec_start_tick: int = -1 

var _ghost_file: String = ""
var _ghost_replay: ReplayData = null
var _ghost_world: World = null
var _ghost_view: CarView = null
var _ghost_input: InputFrame = InputFrame.new()  
var _ghost_index: int = 0

func _ready() -> void:
	_load_track()
	_config = CarConfig.charger(VehicleSelection.selected_id)
	_build_environment()

	var track_mesh := TrackMesh.new()
	track_mesh.build(_track)
	add_child(track_mesh)

	var elements_view := TrackElementsView.new()
	elements_view.build(_elements)
	add_child(elements_view)

	_car_view = CarView.new()
	add_child(_car_view)

	_camera = ChaseCamera.new()
	add_child(_camera)
	_camera.current = true

	_hud = Hud.new()
	add_child(_hud)

	_pause_menu = PauseMenu.new()
	_pause_menu.hide()
	_pause_menu.resumed.connect(_on_pause_resumed)
	_pause_menu.restarted.connect(_on_pause_restarted)
	_pause_menu.quit_requested.connect(_on_pause_quit)
	add_child(_pause_menu)

	_finish_menu = FinishMenu.new()
	_finish_menu.hide()
	_finish_menu.replayed.connect(_on_finish_replayed)
	_finish_menu.quit_requested.connect(_on_pause_quit)
	_finish_menu.save_ghost_requested.connect(_on_save_ghost_requested)
	add_child(_finish_menu)

	_reset_run()
	_camera.set_target(_car_view)

func _build_environment() -> void:
	var jungle: bool = _track.visual_theme == "jungle"
	var world_env := WorldEnvironment.new()
	var environment := Environment.new()
	if jungle:
		var sky := Sky.new()
		var sky_material := ProceduralSkyMaterial.new()
		sky_material.sky_top_color = Color(0.018, 0.012, 0.065)
		sky_material.sky_horizon_color = Color(0.92, 0.205, 0.055)
		sky_material.ground_bottom_color = Color(0.008, 0.018, 0.01)
		sky_material.ground_horizon_color = Color(0.22, 0.055, 0.025)
		sky_material.sky_curve = 0.18
		sky_material.ground_curve = 0.12
		sky_material.sun_angle_max = 9.0
		sky_material.sun_curve = 0.08
		sky.sky_material = sky_material
		environment.background_mode = Environment.BG_SKY
		environment.sky = sky
	else:
		environment.background_mode = Environment.BG_COLOR
		environment.background_color = Color(0.32, 0.47, 0.66)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.22, 0.13, 0.19) if jungle else Color(0.66, 0.76, 0.92)
	environment.ambient_light_energy = 0.62 if jungle else 0.72
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	if jungle:
		environment.fog_enabled = true
		environment.fog_light_color = Color(0.28, 0.075, 0.055)
		environment.fog_light_energy = 0.72
		environment.fog_density = 0.0045
	world_env.environment = environment
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-28.0, -112.0, 0.0) if jungle else Vector3(-52.0, -28.0, 0.0)
	sun.light_color = Color(1.0, 0.28, 0.075) if jungle else Color(1.0, 0.91, 0.76)
	sun.light_energy = 1.15 if jungle else 1.25
	sun.shadow_enabled = true
	add_child(sun)

func _load_track() -> void:
	if Session.pending_track_path != "":
		var path: String = Session.pending_track_path
		Session.pending_track_path = ""
		var data: TrackData = TrackData.load_from_path(path)
		if data != null and data.point_count() >= 2:
			_track = data.to_track()
			_start = data.start_transform()
			_track_id = data.uid
			_elements = data.elements
			Session.pending_builtin_uid = ""
			return

	var builtin_uid: String = Session.pending_builtin_uid
	Session.pending_builtin_uid = ""
	if builtin_uid == "":
		builtin_uid = TrackCatalog.BUILTIN_UID
	_track = TrackCatalog.build_builtin(builtin_uid)
	_start = TrackCatalog.builtin_start(builtin_uid)
	_track_id = builtin_uid
	_elements = [] 

func _resoudre_fantome() -> void:
	var file: String = GhostResolver.resolve(
		GhostSelection.selection(_track_id), Leaderboard.runs(_track_id),
		VehicleSelection.selected_id, []
	)
	if file == _ghost_file:
		return
	_ghost_file = file
	_liberer_fantome()
	if file == "":
		return

	var replay: ReplayData = ReplayStore.load_file(file)
	if replay == null:
		return
	if replay.track_uid != _track_id:
		push_warning("main.gd: replay %s ne correspond pas à la piste chargée, fantôme ignoré" % file)
		return

	_ghost_replay = replay
	_ghost_world = World.new()
	_ghost_view = CarView.new()
	_ghost_view.vehicle_id_override = replay.vehicle_id
	_ghost_view.alpha = 0.45
	add_child(_ghost_view)

func _liberer_fantome() -> void:
	_ghost_replay = null
	_ghost_world = null
	if _ghost_view != null:
		remove_child(_ghost_view)
		_ghost_view.queue_free()
		_ghost_view = null

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _run_over:
		_on_pause_quit()
	else:
		_set_paused(not _paused)

func _set_paused(paused: bool) -> void:
	_paused = paused
	_pause_menu.visible = _paused
	if _paused:
		_pause_menu.focus_first()

func _on_pause_resumed() -> void:
	_set_paused(false)

func _on_pause_restarted() -> void:
	_set_paused(false)
	_reset_run()

func _on_pause_quit() -> void:
	get_tree().change_scene_to_file("res://ui/track_select.tscn")

func _on_finish_replayed() -> void:
	_reset_run()

func _on_save_ghost_requested(replay_file: String) -> void:
	Leaderboard.set_pinned(_track_id, replay_file, true)

func _reset_run() -> void:
	_world.setup(
		_track, _config,
		int(_start[0]), int(_start[1]), int(_start[2]),
		int(_start[3])
	)
	_car_view.sample(_world.car_state)
	_car_view.sample(_world.car_state)  
	_run_over = false
	_finish_menu.hide()
	_rec_count = 0
	_rec_start_tick = -1
	_reset_ghost()

func _reset_ghost() -> void:
	_resoudre_fantome()
	if _ghost_replay == null:
		return
	_ghost_world.setup(
		_track, CarConfig.charger(_ghost_replay.vehicle_id),
		int(_start[0]), int(_start[1]), int(_start[2]),
		int(_start[3])
	)
	_ghost_index = 0
	while _ghost_index < _ghost_replay.start_tick:
		_tick_ghost_frame(false)
	_ghost_view.sample(_ghost_world.car_state)
	_ghost_view.sample(_ghost_world.car_state) 

func _physics_process(_delta: float) -> void:
	if _paused:
		return

	if Input.is_action_just_pressed("reinitialiser"):
		_reset_run()
		return

	if _run_over:
		return

	var cran_accel: int = InputCrans.uni_to_cran(Input.get_action_strength("accelerer"))
	var cran_frein: int = InputCrans.uni_to_cran(Input.get_action_strength("freiner"))
	var steer_raw: float = Input.get_action_strength("gauche") - Input.get_action_strength("droite")
	var cran_braquage: int = InputCrans.bi_to_cran(steer_raw)
	var cran_derapage: int = InputCrans.uni_to_cran(Input.get_action_strength("derapage"))

	_input.accel = InputCrans.cran_to_fixed_uni(cran_accel)
	_input.frein = InputCrans.cran_to_fixed_uni(cran_frein)
	_input.braquage = InputCrans.cran_to_fixed_bi(cran_braquage)
	_input.derapage = InputCrans.cran_to_fixed_uni(cran_derapage)

	_enregistrer(cran_accel, cran_frein, cran_braquage, cran_derapage)

	_world.tick(_input)
	_car_view.sample(_world.car_state)
	if _rec_start_tick < 0 and _world.race_state.started:
		_rec_start_tick = _rec_count - 1
	_tick_ghost()
	_hud.update(_world.car_state, _world.race_state)

	if _world.race_state.finished:
		_run_over = true
		var finish_ms: int = _world.race_state.finish_ms
		var vehicle_id: String = VehicleSelection.selected_id
		var hash_final: int = _world.state_hash()
		var replay_file: String = _sauvegarder_replay(finish_ms, vehicle_id, hash_final)
		var is_record: bool = Leaderboard.submit_time(_track_id, vehicle_id, finish_ms, replay_file, hash_final)
		var best: int = Leaderboard.best_time_ms(_track_id, vehicle_id)
		_finish_menu.show_result(finish_ms, is_record, best, replay_file)
		_finish_menu.focus_first()
	elif _world.race_state.timed_out:
		_run_over = true
		_finish_menu.show_timeout()
		_finish_menu.focus_first()

func _enregistrer(cran_accel: int, cran_frein: int, cran_braquage: int, cran_derapage: int) -> void:
	if _rec_count == _rec_accel.size():
		var nouvelle_taille: int = _rec_count + REC_CHUNK
		_rec_accel.resize(nouvelle_taille)
		_rec_frein.resize(nouvelle_taille)
		_rec_braquage.resize(nouvelle_taille)
		_rec_derapage.resize(nouvelle_taille)
	_rec_accel[_rec_count] = cran_accel
	_rec_frein[_rec_count] = cran_frein
	_rec_braquage[_rec_count] = InputCrans.bi_to_octet(cran_braquage)
	_rec_derapage[_rec_count] = cran_derapage
	_rec_count += 1

func _sauvegarder_replay(finish_ms: int, vehicle_id: String, hash_final: int) -> String:
	var replay := ReplayData.new()
	replay.track_uid = _track_id
	replay.vehicle_id = vehicle_id
	replay.finish_ms = finish_ms
	replay.date = Time.get_datetime_string_from_system()
	replay.hash_final = hash_final
	replay.start_tick = maxi(_rec_start_tick, 0)
	replay.accel_crans = _rec_accel.slice(0, _rec_count)
	replay.frein_crans = _rec_frein.slice(0, _rec_count)
	replay.braquage_crans = _rec_braquage.slice(0, _rec_count)
	replay.derapage_crans = _rec_derapage.slice(0, _rec_count)

	var file: String = ReplayStore.save(replay)
	if file != "" and VALIDER_APRES_RUN:
		_valider_replay(replay)
	return file

func _valider_replay(replay: ReplayData) -> void:
	if replay.tick_count() > VALIDATION_MAX_TICKS:
		return
	var world_test := World.new()
	var config_test: CarConfig = CarConfig.charger(replay.vehicle_id)
	world_test.setup(_track, config_test, int(_start[0]), int(_start[1]), int(_start[2]), int(_start[3]))
	var input_test := InputFrame.new()
	for i in range(replay.tick_count()):
		replay.remplir_input(i, input_test)
		world_test.tick(input_test)
	if world_test.state_hash() != replay.hash_final:
		push_warning("main.gd: contre-rejeu du replay ne correspond pas au hash enregistré (déterminisme suspect)")

func _tick_ghost() -> void:
	if _ghost_replay == null or not _world.race_state.started:
		return
	_tick_ghost_frame()

func _tick_ghost_frame(echantillonner: bool = true) -> void:
	if _ghost_index >= _ghost_replay.tick_count():
		return
	_ghost_replay.remplir_input(_ghost_index, _ghost_input)
	_ghost_world.tick(_ghost_input)
	_ghost_index += 1
	if echantillonner:
		_ghost_view.sample(_ghost_world.car_state)
