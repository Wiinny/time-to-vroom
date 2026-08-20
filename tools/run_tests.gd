extends SceneTree

const REFERENCE_HASH: int = 3586582507276794061  
const SEQUENCE_LENGTH: int = 6000  

var _passes: int = 0
var _failures: int = 0

func _check(test_name: String, condition: bool) -> void:
	if condition:
		_passes += 1
	else:
		_failures += 1
		print("ÉCHEC: ", test_name)

func _check_approx(test_name: String, a: int, b: int, tol: int) -> void:
	if Fixed.abs(a - b) <= tol:
		_passes += 1
	else:
		_failures += 1
		print("ÉCHEC: ", test_name, " (obtenu ", a, ", attendu ", b, ", tolérance ", tol, ")")

func _test_fixed() -> void:
	_check("mul(2, 3) == 6", Fixed.mul(Fixed.from_int(2), Fixed.from_int(3)) == Fixed.from_int(6))
	_check("div(6, 3) == 2", Fixed.div(Fixed.from_int(6), Fixed.from_int(3)) == Fixed.from_int(2))
	_check("mul puis div revient au point de départ", Fixed.div(Fixed.mul(Fixed.from_int(7), Fixed.from_int(5)), Fixed.from_int(5)) == Fixed.from_int(7))
	_check("clamp borne basse", Fixed.clamp(Fixed.from_int(-5), 0, Fixed.from_int(10)) == 0)
	_check("clamp borne haute", Fixed.clamp(Fixed.from_int(15), 0, Fixed.from_int(10)) == Fixed.from_int(10))
	_check("abs(-4) == 4", Fixed.abs(Fixed.from_int(-4)) == Fixed.from_int(4))
	_check("sign", Fixed.sign(5) == 1 and Fixed.sign(-5) == -1 and Fixed.sign(0) == 0)
	_check("lerp au milieu", Fixed.lerp(Fixed.from_int(0), Fixed.from_int(10), Fixed.HALF) == Fixed.from_int(5))

func _test_fixed_math() -> void:
	_check_approx("sqrt(4) == 2", FixedMath.sqrt(Fixed.from_int(4)), Fixed.from_int(2), 2)
	_check_approx("sqrt(9) == 3", FixedMath.sqrt(Fixed.from_int(9)), Fixed.from_int(3), 2)
	_check_approx("sqrt(16) == 4", FixedMath.sqrt(Fixed.from_int(16)), Fixed.from_int(4), 2)
	_check_approx("sin(0) == 0", FixedMath.sin(0), 0, 2)
	_check_approx("sin(90°) == 1", FixedMath.sin(FixedMath.QUARTER_TURN), Fixed.ONE, 2)
	_check_approx("cos(0) == 1", FixedMath.cos(0), Fixed.ONE, 2)
	_check_approx("cos(90°) == 0", FixedMath.cos(FixedMath.QUARTER_TURN), 0, 2)

	for i in range(16):
		var angle: int = i * (FixedMath.FULL_TURN / 16)
		var s: int = FixedMath.sin(angle)
		var c: int = FixedMath.cos(angle)
		var sum_sq: int = Fixed.mul(s, s) + Fixed.mul(c, c)
		_check_approx("sin²+cos²≈1 à l'angle %d" % angle, sum_sq, Fixed.ONE, 8)

	for i in range(16):
		var angle: int = i * (FixedMath.FULL_TURN / 16)
		var x: int = FixedMath.cos(angle)
		var y: int = FixedMath.sin(angle)
		var recovered: int = FixedMath.atan2(y, x)
		var diff: int = Fixed.abs(recovered - angle)
		diff = Fixed.min(diff, FixedMath.FULL_TURN - diff)
		_check("atan2 retrouve l'angle %d (obtenu %d)" % [angle, recovered], diff <= 40)

func _build_test_world() -> World:
	var track: Track = TrackHardcoded.build()
	var config: CarConfig = CarConfig.new()
	var world: World = World.new()
	var start: PackedInt64Array = TrackHardcoded.start_transform()
	world.setup(
		track, config,
		int(start[0]), int(start[1]), int(start[2]),
		int(start[3])
	)
	return world

func _make_input_sequence(n: int) -> Array[InputFrame]:
	var seq: Array[InputFrame] = []
	for i in range(n):
		var f := InputFrame.new()
		var accel_phase: int = i % 240
		if accel_phase < 150:
			f.accel = Fixed.ONE
		elif accel_phase < 180:
			f.frein = Fixed.ONE

		var steer_phase: int = i % 360
		var tri: int
		if steer_phase < 180:
			tri = -Fixed.ONE + Fixed.div(Fixed.from_int(steer_phase), Fixed.from_int(90))
		else:
			tri = Fixed.ONE - Fixed.div(Fixed.from_int(steer_phase - 180), Fixed.from_int(90))
		f.braquage = Fixed.clamp(tri, -Fixed.ONE, Fixed.ONE)

		if i % 300 >= 60 and i % 300 < 200:
			f.derapage = Fixed.ONE

		seq.append(f)
	return seq

func _hash_state(world: World) -> int:
	return world.state_hash()

func _run_sequence(seq: Array[InputFrame]) -> int:
	var world: World = _build_test_world()
	for f in seq:
		world.tick(f)
	return _hash_state(world)

func _run_sequence_sur_piste(track: Track, config: CarConfig, seq: Array[InputFrame]) -> int:
	var world := World.new()
	var start: PackedInt64Array = TrackHardcoded.start_transform()
	world.setup(track, config, int(start[0]), int(start[1]), int(start[2]), int(start[3]))
	for f in seq:
		world.tick(f)
	return _hash_state(world)

func _test_replay_determinism() -> void:
	var seq: Array[InputFrame] = _make_input_sequence(SEQUENCE_LENGTH)
	var hash1: int = _run_sequence(seq)
	var hash2: int = _run_sequence(seq)
	_check("rejeu : deux simulations de la même séquence donnent le même hash", hash1 == hash2)
	if hash1 != hash2:
		print("  hash1=", hash1, " hash2=", hash2)

func _test_regression() -> void:
	var seq: Array[InputFrame] = _make_input_sequence(SEQUENCE_LENGTH)
	var h: int = _run_sequence(seq)
	if h == REFERENCE_HASH:
		_passes += 1
	else:
		_failures += 1
		print("ÉCHEC: non-régression — hash obtenu ", h, " != référence ", REFERENCE_HASH)
		print("  Si ce changement est volontaire (évolution du modèle de conduite),")
		print("  remplacer REFERENCE_HASH dans tools/run_tests.gd par ", h, ".")

func _test_race_state() -> void:
	var track := Track.new()
	track.add_point(Fixed.from_int(0), 0, Fixed.from_int(0), Fixed.from_int(5))
	track.add_point(Fixed.from_int(0), 0, Fixed.from_int(10), Fixed.from_int(5))

	var rs1 := RaceState.new()
	rs1.setup(track, false)
	rs1.reset()
	rs1.tick(0, Fixed.from_int(-1), 0, Fixed.from_int(1), 1, true)
	_check("race_state: pas d'arrivée avant d'être parti", not rs1.finished)

	var rs2 := RaceState.new()
	rs2.setup(track, false)
	rs2.reset()
	rs2.tick(0, Fixed.from_int(2), 0, Fixed.from_int(5), 1, true)  
	rs2.tick(0, Fixed.from_int(-1), 0, Fixed.from_int(1), 2, true)  
	_check("race_state: arrivée valide après un tour", rs2.finished)
	_check("race_state: finish_ms interpolé au sous-tick (départ au tick 1, franchissement à mi-tick)", rs2.finish_ms == 5)

	var rs3 := RaceState.new()
	rs3.setup(track, false)
	rs3.reset()
	rs3.tick(0, Fixed.from_int(2), 0, Fixed.from_int(5), 1, true)
	rs3.tick(0, Fixed.from_int(1), 0, Fixed.from_int(-1), 2, true)
	_check("race_state: pas d'arrivée en sens inverse", not rs3.finished)

	var rs4 := RaceState.new()
	rs4.setup(track, false)
	rs4.reset()
	rs4.tick(0, Fixed.from_int(2), 0, Fixed.from_int(5), 1, true)
	rs4.tick(Fixed.from_int(10), Fixed.from_int(-1), Fixed.from_int(10), Fixed.from_int(1), 2, true)
	_check("race_state: pas d'arrivée hors largeur de piste", not rs4.finished)

	var rs5 := RaceState.new()
	rs5.setup(track, false)
	rs5.reset()
	rs5.tick(0, Fixed.from_int(2), 0, Fixed.from_int(5), 1, true)
	rs5.tick(0, Fixed.from_int(5), 0, Fixed.from_int(5), RaceState.TIME_LIMIT_TICKS, true)
	_check("race_state: pas de temps écoulé juste avant la limite", not rs5.timed_out)
	rs5.tick(0, Fixed.from_int(5), 0, Fixed.from_int(5), RaceState.TIME_LIMIT_TICKS + 1, true)
	_check("race_state: temps écoulé à 30:00.000 pile", rs5.timed_out)

	var rs6 := RaceState.new()
	rs6.setup(track, false)
	rs6.reset()
	rs6.tick(0, Fixed.from_int(2), 0, Fixed.from_int(5), 1, true)
	rs6.tick(0, Fixed.from_int(5), 0, Fixed.from_int(5), RaceState.TIME_LIMIT_TICKS + 1, true)
	rs6.tick(0, Fixed.from_int(-1), 0, Fixed.from_int(1), RaceState.TIME_LIMIT_TICKS + 2, true)  
	_check("race_state: le temps écoulé bloque toute arrivée ultérieure", not rs6.finished)

	var rs7 := RaceState.new()
	rs7.setup(track, false)
	rs7.reset()
	rs7.tick(0, 0, 0, 0, 5, false)  
	_check("race_state: pas parti tant qu'aucun input n'est actif", not rs7.started)
	_check("race_state: chrono à zéro tant qu'aucun input n'est actif", rs7.current_elapsed == 0)
	rs7.tick(0, 0, 0, Fixed.from_int(1), 6, true)  # premier input, au tick 6
	_check("race_state: parti dès le premier input", rs7.started)
	_check("race_state: chrono à zéro pile au premier input", rs7.current_elapsed == 0)
	rs7.tick(0, Fixed.from_int(1), 0, Fixed.from_int(2), 7, true)
	_check("race_state: chrono relatif au premier input, pas au tick absolu", rs7.current_elapsed == 1)

func _test_race_state_ouverte() -> void:
	var track := Track.new()
	track.est_ferme = false
	track.add_point(Fixed.from_int(0), 0, Fixed.from_int(0), Fixed.from_int(5))
	track.add_point(Fixed.from_int(0), 0, Fixed.from_int(50), Fixed.from_int(5))
	track.add_point(Fixed.from_int(0), 0, Fixed.from_int(60), Fixed.from_int(5))

	var rs1 := RaceState.new()
	rs1.setup(track, false)
	rs1.reset()
	rs1.tick(0, Fixed.from_int(0), 0, Fixed.from_int(10), 1, true)  
	rs1.tick(0, Fixed.from_int(49), 0, Fixed.from_int(51), 2, true)  
	_check("race_state ouverte: arrivée dès le premier franchissement, sans attendre l'éloignement", rs1.finished)
	_check("race_state ouverte: finish_ms interpolé au sous-tick", rs1.finish_ms == 5)

	var rs2 := RaceState.new()
	rs2.setup(track, false)
	rs2.reset()
	rs2.tick(0, Fixed.from_int(0), 0, Fixed.from_int(10), 1, true)
	rs2.tick(0, Fixed.from_int(10), 0, Fixed.from_int(40), 2, true)
	_check("race_state ouverte: pas d'arrivée avant la porte", not rs2.finished)
	rs2.tick(0, Fixed.from_int(40), 0, Fixed.from_int(55), 3, true)
	_check("race_state ouverte: arrivée à la porte du dernier segment", rs2.finished)

	var rs3 := RaceState.new()
	rs3.setup(track, false)
	rs3.reset()
	rs3.tick(0, Fixed.from_int(55), 0, Fixed.from_int(52), 1, true)
	rs3.tick(0, Fixed.from_int(52), 0, Fixed.from_int(45), 2, true)  
	_check("race_state ouverte: pas d'arrivée en sens inverse", not rs3.finished)

	var rs4 := RaceState.new()
	rs4.setup(track, false)
	rs4.reset()
	rs4.tick(Fixed.from_int(10), Fixed.from_int(0), Fixed.from_int(10), Fixed.from_int(10), 1, true)
	rs4.tick(Fixed.from_int(10), Fixed.from_int(49), Fixed.from_int(10), Fixed.from_int(51), 2, true) 
	_check("race_state ouverte: pas d'arrivée hors largeur de piste", not rs4.finished)

	var ferme := Track.new()
	ferme.add_point(Fixed.from_int(0), 0, Fixed.from_int(0), Fixed.from_int(5))
	ferme.add_point(Fixed.from_int(0), 0, Fixed.from_int(50), Fixed.from_int(5))
	ferme.add_point(Fixed.from_int(0), 0, Fixed.from_int(60), Fixed.from_int(5))
	var rs5 := RaceState.new()
	rs5.setup(ferme, false)
	rs5.reset()
	rs5.tick(0, Fixed.from_int(49), 0, Fixed.from_int(51), 1, true)
	_check("race_state fermée: rien ne se déclenche à z=50 (la porte n'est pas au dernier segment)", not rs5.finished)
	rs5.tick(0, Fixed.from_int(1), 0, Fixed.from_int(-1), 2, true)
	_check("race_state fermée: sens inverse au segment 0 toujours ignoré", not rs5.finished)
	rs5.tick(0, Fixed.from_int(-1), 0, Fixed.from_int(1), 3, true)
	_check("race_state fermée: la porte est bien restée au segment 0", rs5.finished)

func _validation_track() -> Track:
	var track := Track.new()
	track.add_point(Fixed.from_int(0), 0, Fixed.from_int(0), Fixed.from_int(5))
	track.add_point(Fixed.from_int(0), 0, Fixed.from_int(40), Fixed.from_int(5))
	track.add_point(Fixed.from_int(40), 0, Fixed.from_int(40), Fixed.from_int(5))
	track.add_point(Fixed.from_int(40), 0, Fixed.from_int(-20), Fixed.from_int(5))
	track.add_point(Fixed.from_int(0), 0, Fixed.from_int(-20), Fixed.from_int(5))
	return track

func _drive_validation_line(rs: RaceState, ax: int, az: int, bx: int, bz: int, tick_start: int) -> int:
	var dx: int = bx - ax
	var dz: int = bz - az
	var length: int = FixedMath.sqrt(Fixed.mul(dx, dx) + Fixed.mul(dz, dz))
	var step_size: int = Fixed.from_int(2)
	var steps: int = maxi(1, (length + step_size - 1) / step_size)
	var prev_x: int = ax
	var prev_z: int = az
	var tick: int = tick_start
	for step in range(1, steps + 1):
		var t: int = Fixed.div(Fixed.from_int(step), Fixed.from_int(steps))
		var cur_x: int = ax + Fixed.mul(dx, t)
		var cur_z: int = az + Fixed.mul(dz, t)
		tick += 1
		rs.tick(prev_x, prev_z, cur_x, cur_z, tick, true)
		prev_x = cur_x
		prev_z = cur_z
	return tick

func _test_progress_validation() -> void:
	var track: Track = _validation_track()
	var valid := RaceState.new()
	valid.setup(track)
	valid.reset()
	var tick: int = 0
	for i in range(track.point_count()):
		var j: int = (i + 1) % track.point_count()
		tick = _drive_validation_line(valid, track.point_x[i], track.point_z[i], track.point_x[j], track.point_z[j], tick)
	tick = _drive_validation_line(valid, track.point_x[0], track.point_z[0], track.point_x[0], Fixed.from_int(2), tick)
	_check("validation parcours: un tour complet valide toutes les zones", valid.validated_zone_count == valid.validation_zone_count)
	_check("validation parcours: arrivée acceptée après le tracé complet", valid.finished and valid.run_valid)

	var shortcut := RaceState.new()
	shortcut.setup(track)
	shortcut.reset()
	tick = _drive_validation_line(shortcut, track.point_x[0], track.point_z[0], track.point_x[0], Fixed.from_int(20), 0)
	tick = _drive_validation_line(shortcut, track.point_x[0], Fixed.from_int(20), track.point_x[0], track.point_z[0], tick)
	_drive_validation_line(shortcut, track.point_x[0], track.point_z[0], track.point_x[0], Fixed.from_int(2), tick)
	_check("validation parcours: un aller-retour sur la même portion ne termine pas la course", not shortcut.finished)
	_check("validation parcours: les zones non parcourues restent non validées", shortcut.validated_zone_count < shortcut.validation_zone_count)

	var jump := RaceState.new()
	jump.setup(track)
	jump.reset()
	jump.tick(0, 0, 0, Fixed.from_int(2), 1, true)
	jump.tick(0, Fixed.from_int(2), Fixed.from_int(40), Fixed.from_int(40), 2, true)
	_check("validation parcours: un saut de progression impossible invalide le run", not jump.run_valid and not jump.finished)

func _test_collision_gabarit() -> void:
	var track := Track.new()
	track.est_ferme = false
	track.add_point(0, 0, 0, Fixed.from_int(5))
	track.add_point(0, 0, Fixed.from_int(100), Fixed.from_int(5))
	var state := CarState.new()
	state.reset(Fixed.from_float(4.8), 0, Fixed.from_int(10), 0)
	var config := CarConfig.new()
	config.bake()
	var input := InputFrame.new()
	var query := TrackQueryResult.new()
	CarSim.tick(state, input, track, config, query)
	var expected_limit: int = Fixed.from_int(5) - ReglesCommunes.demi_largeur_vehicule
	_check("collision piste: le bord du véhicule, pas son centre, reste dans le mur", Fixed.abs(state.pos_x) <= expected_limit)

func _test_track_data_start_transform() -> void:
	var data := TrackData.new()
	data.add_point(Fixed.from_int(0), 0, Fixed.from_int(0), Fixed.from_int(5))
	data.add_point(Fixed.from_int(10), 0, Fixed.from_int(0), Fixed.from_int(5))  
	var start: PackedInt64Array = data.start_transform()
	_check_approx("TrackData.start_transform: cap dérivé du segment 0->1 (vers +X ici)", int(start[3]), FixedMath.QUARTER_TURN, 2)
	_check("TrackData.start_transform: position en Q16.16 telle quelle (pas de reconversion)", int(start[0]) == 0 and int(start[2]) == 0)

func _build_wide_track() -> Track:
	var track := Track.new()
	track.add_point(Fixed.from_int(-1000), 0, Fixed.from_int(-1000), Fixed.from_int(500))
	track.add_point(Fixed.from_int(1000), 0, Fixed.from_int(-1000), Fixed.from_int(500))
	track.add_point(Fixed.from_int(1000), 0, Fixed.from_int(1000), Fixed.from_int(500))
	track.add_point(Fixed.from_int(-1000), 0, Fixed.from_int(1000), Fixed.from_int(500))
	return track

func _build_element_track(kind: int, x: int, z: int) -> Track:
	var track: Track = _build_wide_track()
	track.add_element(kind, x, 0, z, 0)
	return track

func _lateral_speed(state: CarState) -> int:
	var fwd_x: int = FixedMath.sin(state.yaw)
	var fwd_z: int = FixedMath.cos(state.yaw)
	return Fixed.mul(state.vit_x, fwd_z) - Fixed.mul(state.vit_z, fwd_x)

func _test_courbe_accel() -> void:
	var track: Track = _build_wide_track()
	var query := TrackQueryResult.new()
	var input := InputFrame.new()
	input.accel = Fixed.ONE

	var config := CarConfigGt.new()  
	config.bake()

	var state_bas := CarState.new()
	state_bas.reset(0, 0, 0, 0)
	CarSim.tick(state_bas, input, track, config, query)
	_check_approx("courbe d'accel ≈ accel_basse à v=0", state_bas.vit_z, config.accel_basse, 4)

	var state_haut := CarState.new()
	state_haut.reset(0, 0, 0, 0)
	state_haut.vit_z = config.palier_accel
	CarSim.tick(state_haut, input, track, config, query)
	var delta_haut: int = state_haut.vit_z - config.palier_accel
	_check_approx("courbe d'accel ≈ accel_haute à v≥palier", delta_haut, config.accel_haute, 4)

	var state_mid := CarState.new()
	state_mid.reset(0, 0, 0, 0)
	state_mid.vit_z = config.palier_accel / 2
	CarSim.tick(state_mid, input, track, config, query)
	var delta_mid: int = state_mid.vit_z - config.palier_accel / 2
	_check("courbe d'accel monotone entre accel_basse et accel_haute", delta_mid < config.accel_basse and delta_mid > config.accel_haute)

	var config_lin := CarConfigFormula.new()  
	config_lin.bake()
	var state_lin_bas := CarState.new()
	state_lin_bas.reset(0, 0, 0, 0)
	CarSim.tick(state_lin_bas, input, track, config_lin, query)
	var state_lin_mid := CarState.new()
	state_lin_mid.reset(0, 0, 0, 0)
	state_lin_mid.vit_z = config_lin.palier_accel / 2
	CarSim.tick(state_lin_mid, input, track, config_lin, query)
	var delta_lin_mid: int = state_lin_mid.vit_z - config_lin.palier_accel / 2
	_check_approx("courbe linéaire (accel_basse==accel_haute) constante quel que soit v", state_lin_bas.vit_z, delta_lin_mid, 4)

func _test_echelle_rotation() -> void:
	var config := CarConfigGt.new()
	config.bake()
	var track: Track = _build_wide_track()
	var query := TrackQueryResult.new()

	var input := InputFrame.new()
	input.braquage = Fixed.ONE
	var state := CarState.new()
	state.reset(0, 0, 0, 0)
	state.vit_z = Fixed.from_float(20.0 / 3.6 / float(Horloge.TICKS_PAR_SECONDE))  
	var v_avant: int = FixedMath.length_2d(state.vit_x, state.vit_z)  

	var yaw_avant: int = state.yaw
	CarSim.tick(state, input, track, config, query)
	var yaw_apres: int = state.yaw
	var angle_utilise: int = state.angle_roues

	var dpsi_attendu: int = int(round(Fixed.to_float(v_avant) * float(angle_utilise) / ReglesCommunes.EMPATTEMENT_M))
	var dpsi_obtenu: int = (yaw_apres - yaw_avant) & (FixedMath.FULL_TURN - 1)
	if dpsi_obtenu > FixedMath.HALF_TURN:
		dpsi_obtenu -= FixedMath.FULL_TURN
	_check_approx("échelle de rotation : Δψ ≈ v·angle_roues/EMPATTEMENT (pas divisé par 65536 en trop)", dpsi_obtenu, dpsi_attendu, 5)
	_check("échelle de rotation : le yaw tourne bien de façon significative (pas quasi figé)", Fixed.abs(dpsi_obtenu) > 2)

func _test_braquage_progressif() -> void:
	var track: Track = _build_wide_track()
	var query := TrackQueryResult.new()
	var input := InputFrame.new()
	input.braquage = Fixed.ONE

	var config_lent := CarConfigSuperbike.new() 
	config_lent.bake()
	var state_lent := CarState.new()
	state_lent.reset(0, 0, 0, 0)
	CarSim.tick(state_lent, input, track, config_lent, query)

	var config_rapide := CarConfigStreetBike.new() 
	config_rapide.bake()
	var state_rapide := CarState.new()
	state_rapide.reset(0, 0, 0, 0)
	CarSim.tick(state_rapide, input, track, config_rapide, query)

	_check("braquage progressif : Ironside converge plus lentement que Wasp", state_lent.angle_roues < state_rapide.angle_roues)
	_check_approx("braquage progressif : le pas d'un tick == vitesse_braquage bakée (Ironside)", state_lent.angle_roues, config_lent.vitesse_braquage, 2)
	_check_approx("braquage progressif : le pas d'un tick == vitesse_braquage bakée (Wasp)", state_rapide.angle_roues, config_rapide.vitesse_braquage, 2)

func _test_sous_virage() -> void:
	var config := CarConfigFormula.new()  
	config.bake()
	var track: Track = _build_wide_track()
	var query := TrackQueryResult.new()
	var input := InputFrame.new()
	input.braquage = Fixed.ONE  

	var state := CarState.new()
	state.reset(0, 0, 0, 0)
	state.vit_z = config.vitesse_max  

	var v_avant: int = FixedMath.length_2d(state.vit_x, state.vit_z)
	for i in range(120):
		CarSim.tick(state, input, track, config, query)
	var v_apres: int = FixedMath.length_2d(state.vit_x, state.vit_z)

	_check("sous-virage (AUCUNE) : quasi aucun résidu latéral — ne part jamais en travers", Fixed.abs(_lateral_speed(state)) < Fixed.ONE / 20)
	_check("sous-virage (AUCUNE) : la vitesse chute (perte par scrub)", v_apres < v_avant)

func _test_glisse_raccourcit() -> void:
	var config := CarConfigGt.new() 
	config.bake()
	var track: Track = _build_wide_track()
	var query := TrackQueryResult.new()

	var input_normal := InputFrame.new()
	input_normal.braquage = Fixed.ONE

	var input_glisse := InputFrame.new()
	input_glisse.braquage = Fixed.ONE
	input_glisse.derapage = Fixed.ONE

	var state_normal := CarState.new()
	state_normal.reset(0, 0, 0, 0)
	state_normal.vit_z = config.vitesse_max / 2

	var state_glisse := CarState.new()
	state_glisse.reset(0, 0, 0, 0)
	state_glisse.vit_z = config.vitesse_max / 2

	var angle_v_normal_avant: int = FixedMath.atan2(state_normal.vit_x, state_normal.vit_z)
	var angle_v_glisse_avant: int = FixedMath.atan2(state_glisse.vit_x, state_glisse.vit_z)

	for i in range(Horloge.TICKS_PAR_SECONDE):
		CarSim.tick(state_normal, input_normal, track, config, query)
		CarSim.tick(state_glisse, input_glisse, track, config, query)

	var angle_v_normal_apres: int = FixedMath.atan2(state_normal.vit_x, state_normal.vit_z)
	var angle_v_glisse_apres: int = FixedMath.atan2(state_glisse.vit_x, state_glisse.vit_z)
	var rotation_normal: int = (angle_v_normal_apres - angle_v_normal_avant) & (FixedMath.FULL_TURN - 1)
	var rotation_glisse: int = (angle_v_glisse_apres - angle_v_glisse_avant) & (FixedMath.FULL_TURN - 1)

	_check("glisse (PIVOT_AVANT) : la trajectoire tourne réellement plus vite qu'en conduite normale", rotation_glisse > rotation_normal)

func _test_glisse_travers() -> void:
	var config := CarConfigGt.new()
	config.bake()
	var track: Track = _build_wide_track()
	var query := TrackQueryResult.new()

	var input_glisse := InputFrame.new()
	input_glisse.braquage = Fixed.ONE
	input_glisse.derapage = Fixed.ONE

	var state := CarState.new()
	state.reset(0, 0, 0, 0)
	state.vit_z = config.vitesse_max / 2
	for i in range(40):
		CarSim.tick(state, input_glisse, track, config, query)
	_check("glisse (PIVOT_AVANT) : le travers est établi (résidu latéral non nul)", Fixed.abs(_lateral_speed(state)) > 0)

	var input_relache := InputFrame.new() 
	for i in range(60):
		CarSim.tick(state, input_relache, track, config, query)
	_check("glisse (PIVOT_AVANT) : corrigeable — revient vers l'axe au relâchement", Fixed.abs(_lateral_speed(state)) < Fixed.ONE / 10)

func _test_saut_arc() -> void:
	var config := CarConfigStreetBike.new() 
	config.bake()
	var track: Track = _build_wide_track()
	var query := TrackQueryResult.new()

	var input := InputFrame.new()
	input.braquage = Fixed.ONE
	input.derapage = Fixed.ONE  

	var state := CarState.new()
	state.reset(0, 0, 0, 0)
	state.vit_z = config.vitesse_max
	var v_avant: int = FixedMath.length_2d(state.vit_x, state.vit_z)

	CarSim.tick(state, input, track, config, query)
	_check("saut (SAUT_ARC) : décolle au déclenchement", not state.au_sol)

	var ticks_en_l_air: int = 0
	for i in range(config.saut_duree_ticks + 5):
		if not state.au_sol:
			ticks_en_l_air += 1
		CarSim.tick(state, input, track, config, query)
	_check_approx("saut (SAUT_ARC) : durée en l'air ≈ saut_duree_ticks", ticks_en_l_air, config.saut_duree_ticks, 2)
	_check("saut (SAUT_ARC) : de retour au sol après la phase aérienne", state.au_sol)

	for i in range(30): 
		CarSim.tick(state, input, track, config, query)
	_check("saut (SAUT_ARC) : engage bien la phase ARC après atterrissage (glisse_etat == ARC ou déjà relâché)", state.glisse_etat == CarState.GlisseEtat.ARC or state.glisse_etat == CarState.GlisseEtat.LIBRE)

	var v_apres: int = FixedMath.length_2d(state.vit_x, state.vit_z)
	_check("saut (SAUT_ARC) : coût en vitesse appliqué (cout_vitesse_saut + drain de l'arc)", v_apres < v_avant)

func _test_permanente() -> void:
	var config := CarConfigHover.new()  
	config.bake()
	var track: Track = _build_wide_track()
	var query := TrackQueryResult.new()

	var input_tout_droit := InputFrame.new()
	var state := CarState.new()
	state.reset(0, 0, 0, 0)
	state.vit_z = config.vitesse_max
	var v_avant: int = FixedMath.length_2d(state.vit_x, state.vit_z)
	for i in range(Horloge.TICKS_PAR_SECONDE):
		CarSim.tick(state, input_tout_droit, track, config, query)
	var v_apres: int = FixedMath.length_2d(state.vit_x, state.vit_z)
	var perte_attendue: int = Horloge.TICKS_PAR_SECONDE * config.decel_naturelle
	_check_approx("permanente (Halcyon) : la perte en ligne droite vient seulement de decel_naturelle, pas d'un drain de glisse", v_avant - v_apres, perte_attendue, 10)

	var input_virage := InputFrame.new()
	input_virage.braquage = Fixed.ONE
	var state_virage := CarState.new()
	state_virage.reset(0, 0, 0, 0)
	state_virage.vit_z = config.vitesse_max
	for i in range(60):
		CarSim.tick(state_virage, input_virage, track, config, query)
	_check("permanente (Halcyon) : le résidu latéral persiste en virage (on oriente une dérive)", Fixed.abs(_lateral_speed(state_virage)) > 0)

func _test_boost() -> void:
	var config_a := CarConfigGt.new()
	config_a.bake()
	var config_b := CarConfigHover.new() 
	config_b.bake()

	var state := CarState.new()
	state.reset(0, 0, 0, 0)
	state.vit_x = Fixed.from_int(3)
	state.vit_z = Fixed.from_int(1)
	var v_avant: int = FixedMath.length_2d(state.vit_x, state.vit_z)
	CarSim.declencher_boost(state, config_a)
	var v_apres: int = FixedMath.length_2d(state.vit_x, state.vit_z)
	_check_approx("boost : poussée absolue +45 km/h le long de la trajectoire", v_apres - v_avant, ReglesCommunes.boost_poussee, 4)
	var ratio_avant: int = Fixed.div(state.vit_x, state.vit_z)
	_check_approx("boost : ne change pas la direction de la trajectoire", ratio_avant, Fixed.div(Fixed.from_int(3), Fixed.from_int(1)), 50)

	state.bonus_vitesse = Fixed.from_int(1)
	for i in range(Horloge.TICKS_PAR_SECONDE):
		state.bonus_vitesse = Fixed.max(0, state.bonus_vitesse - ReglesCommunes.boost_decroissance)
	_check_approx("boost : le surplus décroît de 12 km/h après 1 s", Fixed.from_int(1) - state.bonus_vitesse, ReglesCommunes.boost_decroissance * Horloge.TICKS_PAR_SECONDE, 4)

	var state_a := CarState.new()
	state_a.reset(0, 0, 0, 0)
	state_a.bonus_vitesse = Fixed.from_int(1)
	var state_b := CarState.new()
	state_b.reset(0, 0, 0, 0)
	state_b.bonus_vitesse = Fixed.from_int(1)
	for i in range(Horloge.TICKS_PAR_SECONDE):
		state_a.bonus_vitesse = Fixed.max(0, state_a.bonus_vitesse - ReglesCommunes.boost_decroissance)
		state_b.bonus_vitesse = Fixed.max(0, state_b.bonus_vitesse - ReglesCommunes.boost_decroissance)
	_check("boost : décroissance identique quel que soit decel_naturelle", state_a.bonus_vitesse == state_b.bonus_vitesse)

func _test_track_data_elements() -> void:
	var data := TrackData.new()
	data.add_point(Fixed.from_int(-100), 0, Fixed.from_int(-100), Fixed.from_int(50))
	data.add_point(Fixed.from_int(100), 0, Fixed.from_int(-100), Fixed.from_int(50))
	data.add_element("boost", "defaut", Fixed.from_int(5), 0, Fixed.from_int(5), 0)
	data.add_element("id_inconnu", "defaut", Fixed.from_int(1), 0, Fixed.from_int(1), 0)
	data.elements.append({"type": "mur"})  

	var track: Track = data.to_track()
	_check("TrackData.to_track: id inconnu ignoré, id valide (même mal formé) conservé", track.element_count() == 2)
	var kinds: Array = []
	for i in range(track.element_count()):
		kinds.append(track.elem_kind[i])
	_check("TrackData.to_track: le boost est propagé avec le bon kind", kinds.has(ElementRoster.Kind.BOOST))
	_check("TrackData.to_track: le mur (dict incomplet) est conservé avec des défauts à 0", kinds.has(ElementRoster.Kind.MUR))
	_check("TrackHardcoded: piste intégrée toujours sans éléments", TrackHardcoded.build().element_count() == 0)

func _test_element_rayons() -> void:
	var n: int = ElementRoster.Kind.size()
	_check("ElementEffects: rayons dimensionné sur tout le roster", ElementEffects.rayons.size() == n)
	_check("ElementEffects: rayons_sq dimensionné pareil", ElementEffects.rayons_sq.size() == n)
	var plancher: int = Fixed.from_float(2.0)
	for k in range(n):
		var r: int = ElementEffects.rayons[k]
		_check("ElementEffects: rayon du kind %d nul ou >= 2,0 m" % k, r == 0 or r >= plancher)
		_check_approx("ElementEffects: rayons_sq cohérent avec rayons pour le kind %d" % k, ElementEffects.rayons_sq[k], Fixed.mul(r, r), 2)
	_check("ElementEffects: le pad de boost a bien un rayon", ElementEffects.rayons[ElementRoster.Kind.BOOST] == ElementEffects.rayon_pad)

func _test_element_boost() -> void:
	var config := CarConfigGt.new()
	config.bake()
	var track: Track = _build_element_track(ElementRoster.Kind.BOOST, 0, 0)
	var query := TrackQueryResult.new()
	var input := InputFrame.new()  

	var state := CarState.new()
	state.reset(0, 0, 0, 0)
	state.vit_z = config.vitesse_max

	state.pos_x = 0; state.pos_z = 0
	CarSim.tick(state, input, track, config, query)
	_check("boost (élément) : déclenché au premier tick dans le rayon", state.bonus_vitesse > 0)
	var bonus_apres_entree: int = state.bonus_vitesse

	state.pos_x = 0; state.pos_z = 0  
	CarSim.tick(state, input, track, config, query)
	_check("boost (élément) : pas de nouveau déclenchement en restant sur le pad", state.bonus_vitesse <= bonus_apres_entree)

	state.pos_x = Fixed.from_int(50); state.pos_z = 0  
	CarSim.tick(state, input, track, config, query)
	state.pos_x = 0; state.pos_z = 0  
	var bonus_avant_retour: int = state.bonus_vitesse
	CarSim.tick(state, input, track, config, query)
	_check("boost (élément) : redéclenché après sortie puis rentrée sur le pad", state.bonus_vitesse > bonus_avant_retour)

func _test_element_rampe() -> void:
	var config := CarConfigGt.new() 
	config.bake()
	_check("rampe (élément) : config non-Wasp a bien saut_gravite=0 (sinon le test ne prouve rien)", config.saut_gravite == 0)

	var track: Track = _build_element_track(ElementRoster.Kind.RAMPE, 0, 0)
	var query := TrackQueryResult.new()
	var input := InputFrame.new()

	var state := CarState.new()
	state.reset(0, 0, 0, 0)

	CarSim.tick(state, input, track, config, query)
	_check("rampe (élément) : décolle au déclenchement", not state.au_sol)
	_check("rampe (élément) : vitesse verticale positive au décollage", state.vit_y > 0)
	_check("rampe (élément) : glisse_etat jamais détourné vers SAUT (machine à états de SAUT_ARC)", state.glisse_etat != CarState.GlisseEtat.SAUT)

	var ticks_en_l_air: int = 0
	for i in range(ElementEffects.rampe_duree_ticks + 10):
		if not state.au_sol:
			ticks_en_l_air += 1
		CarSim.tick(state, input, track, config, query)
	_check_approx("rampe (élément) : durée en l'air ≈ rampe_duree_ticks", ticks_en_l_air, ElementEffects.rampe_duree_ticks, 3)
	_check("rampe (élément) : de retour au sol après la phase aérienne", state.au_sol)

func _test_element_ralentit() -> void:
	var config := CarConfigFormula.new()  
	config.bake()
	var track: Track = _build_element_track(ElementRoster.Kind.ROUTE_RALENTIT, 0, 0)
	var query := TrackQueryResult.new()
	var input := InputFrame.new()
	input.accel = Fixed.ONE

	var state := CarState.new()
	state.reset(0, 0, 0, 0)
	state.vit_z = config.vitesse_max 

	CarSim.tick(state, input, track, config, query)
	_check("route_ralentit : pas un mur — la vitesse ne chute pas d'un coup au plafond dès le premier tick", FixedMath.length_2d(state.vit_x, state.vit_z) > ElementEffects.ralentit_plafond)

	for i in range(1000):
		state.pos_x = 0; state.pos_z = 0  
		CarSim.tick(state, input, track, config, query)
	var v_final: int = FixedMath.length_2d(state.vit_x, state.vit_z)
	_check_approx("route_ralentit : converge vers le plafond de zone après un moment plein régime", v_final, ElementEffects.ralentit_plafond, Fixed.from_float(0.03))

	var state_hors := CarState.new()
	state_hors.reset(Fixed.from_int(1000), 0, 0, 0)  
	state_hors.vit_z = config.vitesse_max
	CarSim.tick(state_hors, input, track, config, query)
	_check("route_ralentit : hors zone, la vitesse max n'est pas plafonnée", FixedMath.length_2d(state_hors.vit_x, state_hors.vit_z) > ElementEffects.ralentit_plafond)

func _test_element_degrade_controles() -> void:
	var config := CarConfigStreetBike.new()  
	config.bake()
	var track: Track = _build_element_track(ElementRoster.Kind.ROUTE_DEGRADE_CONTROLES, 0, 0)
	var query := TrackQueryResult.new()
	var input := InputFrame.new()
	input.braquage = Fixed.ONE

	var state_zone := CarState.new()
	state_zone.reset(0, 0, 0, 0)
	var state_hors := CarState.new()
	state_hors.reset(Fixed.from_int(1000), 0, 0, 0)

	for i in range(30):
		state_zone.pos_x = 0; state_zone.pos_z = 0  
		CarSim.tick(state_zone, input, track, config, query)
		CarSim.tick(state_hors, input, track, config, query)

	_check("route_degrade_controles : angle de roues réduit dans la zone par rapport à hors zone", state_zone.angle_roues < state_hors.angle_roues)
	_check_approx("route_degrade_controles : réduction ≈ DEGRADE_AUTORITE", state_zone.angle_roues, Fixed.mul(state_hors.angle_roues, ElementEffects.degrade_autorite), 4)

func _test_element_aimantee() -> void:
	var config := CarConfigHover.new()  
	config.bake()
	var track_aimante: Track = _build_element_track(ElementRoster.Kind.ROUTE_AIMANTEE, 0, 0)
	var track_normal: Track = _build_wide_track()
	var query := TrackQueryResult.new()
	var input := InputFrame.new()
	input.braquage = Fixed.ONE

	var state_aimante := CarState.new()
	state_aimante.reset(0, 0, 0, 0)
	state_aimante.vit_z = config.vitesse_max / 2

	var state_normal := CarState.new()
	state_normal.reset(0, 0, 0, 0)
	state_normal.vit_z = config.vitesse_max / 2

	var angle_avant_aimante: int = FixedMath.atan2(state_aimante.vit_x, state_aimante.vit_z)
	var angle_avant_normal: int = FixedMath.atan2(state_normal.vit_x, state_normal.vit_z)

	for i in range(Horloge.TICKS_PAR_SECONDE):
		state_aimante.pos_x = 0; state_aimante.pos_z = 0  
		CarSim.tick(state_aimante, input, track_aimante, config, query)
		CarSim.tick(state_normal, input, track_normal, config, query)

	var angle_apres_aimante: int = FixedMath.atan2(state_aimante.vit_x, state_aimante.vit_z)
	var angle_apres_normal: int = FixedMath.atan2(state_normal.vit_x, state_normal.vit_z)
	var rotation_aimante: int = (angle_apres_aimante - angle_avant_aimante) & (FixedMath.FULL_TURN - 1)
	var rotation_normal: int = (angle_apres_normal - angle_avant_normal) & (FixedMath.FULL_TURN - 1)

	_check("route_aimantee : la trajectoire tourne plus vite dans la zone (budget latéral élargi) qu'en dehors", rotation_aimante > rotation_normal)

func _test_element_obstacle_ralentit() -> void:
	var config := CarConfigGt.new()
	config.bake()
	var track: Track = _build_element_track(ElementRoster.Kind.OBSTACLE_RALENTIT, 0, 0)
	var query := TrackQueryResult.new()
	var input := InputFrame.new()

	var state := CarState.new()
	state.reset(0, 0, 0, 0)
	state.vit_z = config.vitesse_max
	var v_avant: int = FixedMath.length_2d(state.vit_x, state.vit_z)

	CarSim.tick(state, input, track, config, query)
	var v_apres: int = FixedMath.length_2d(state.vit_x, state.vit_z)
	_check_approx("obstacle_ralentit : perte de vitesse ponctuelle ≈ PLOT_PENALITE_KMH", v_avant - v_apres, ElementEffects.plot_penalite, Fixed.from_float(0.02))
	_check("obstacle_ralentit : ne fait jamais reculer", state.vit_z >= 0)

	var v_apres_premier: int = v_apres
	state.pos_x = 0; state.pos_z = 0  
	CarSim.tick(state, input, track, config, query)
	_check("obstacle_ralentit : pas de second impact en restant dans le rayon", FixedMath.length_2d(state.vit_x, state.vit_z) >= v_apres_premier - Fixed.from_float(0.02))

func _test_element_obstacle_mortel() -> void:
	for kind in [ElementRoster.Kind.OBSTACLE_MORTEL, ElementRoster.Kind.VIDE]:
		var config := CarConfigGt.new()
		config.bake()
		var track: Track = _build_element_track(kind, 0, 0)
		var query := TrackQueryResult.new()
		var input := InputFrame.new()  

		var state := CarState.new()
		state.reset(0, 0, 0, 0)
		state.vit_z = config.vitesse_max
		state.bonus_vitesse = Fixed.from_float(1.0)  

		CarSim.tick(state, input, track, config, query)
		_check("mortel/vide (kind %d) : vitesse clampée à 0" % kind, state.vit_x == 0 and state.vit_z == 0)
		_check("mortel/vide (kind %d) : le surplus de boost est annulé" % kind, state.bonus_vitesse == 0)
		_check("mortel/vide (kind %d) : verrou de direction posé" % kind, state.controle_perdu_ticks > 0)

		var input_braquage := InputFrame.new()
		input_braquage.braquage = Fixed.ONE

		var state_verrou := CarState.new()
		state_verrou.reset(Fixed.from_int(1000), 0, 0, 0)  
		state_verrou.controle_perdu_ticks = ElementEffects.mortel_controle_perdu_ticks
		var state_libre := CarState.new()
		state_libre.reset(Fixed.from_int(1000), 0, 0, 0)
		for i in range(30):
			CarSim.tick(state_verrou, input_braquage, track, config, query)
			CarSim.tick(state_libre, input_braquage, track, config, query)
		_check("mortel/vide (kind %d) : autorité de direction réduite pendant le verrou" % kind, state_verrou.angle_roues < state_libre.angle_roues)

		for i in range(ElementEffects.mortel_controle_perdu_ticks + 5):
			CarSim.tick(state_verrou, input_braquage, track, config, query)
		_check("mortel/vide (kind %d) : le verrou finit par se lever" % kind, state_verrou.controle_perdu_ticks == 0)

func _test_element_zones_ne_cumulent_pas() -> void:
	var config := CarConfigStreetBike.new()
	config.bake()
	var track_un: Track = _build_element_track(ElementRoster.Kind.ROUTE_DEGRADE_CONTROLES, 0, 0)
	var track_deux: Track = _build_wide_track()
	track_deux.add_element(ElementRoster.Kind.ROUTE_DEGRADE_CONTROLES, 0, 0, 0, 0)
	track_deux.add_element(ElementRoster.Kind.ROUTE_DEGRADE_CONTROLES, Fixed.from_int(1), 0, Fixed.from_int(1), 0)
	var query := TrackQueryResult.new()
	var input := InputFrame.new()
	input.braquage = Fixed.ONE

	var state_un := CarState.new()
	state_un.reset(0, 0, 0, 0)
	CarSim.tick(state_un, input, track_un, config, query)

	var state_deux := CarState.new()
	state_deux.reset(0, 0, 0, 0)
	CarSim.tick(state_deux, input, track_deux, config, query)

	_check_approx("route_degrade_controles : deux zones qui se chevauchent ne réduisent pas plus qu'une seule", state_deux.angle_roues, state_un.angle_roues, 4)

	var config_hover := CarConfigHover.new()
	config_hover.bake()
	var track_aimante_un: Track = _build_element_track(ElementRoster.Kind.ROUTE_AIMANTEE, 0, 0)
	var track_aimante_deux: Track = _build_wide_track()
	track_aimante_deux.add_element(ElementRoster.Kind.ROUTE_AIMANTEE, 0, 0, 0, 0)
	track_aimante_deux.add_element(ElementRoster.Kind.ROUTE_AIMANTEE, Fixed.from_int(1), 0, Fixed.from_int(1), 0)

	var state_aimante_un := CarState.new()
	state_aimante_un.reset(0, 0, 0, 0)
	state_aimante_un.vit_z = config_hover.vitesse_max / 2
	CarSim.tick(state_aimante_un, input, track_aimante_un, config_hover, query)

	var state_aimante_deux := CarState.new()
	state_aimante_deux.reset(0, 0, 0, 0)
	state_aimante_deux.vit_z = config_hover.vitesse_max / 2
	CarSim.tick(state_aimante_deux, input, track_aimante_deux, config_hover, query)

	_check("route_aimantee : deux zones qui se chevauchent ne donnent pas plus de grip qu'une seule", state_aimante_deux.elem_bonus_grip == state_aimante_un.elem_bonus_grip)

func _test_element_sans_effet() -> void:
	var seq: Array[InputFrame] = _make_input_sequence(600)
	var h_reference: int = _run_sequence_sur_piste(TrackHardcoded.build(), CarConfig.new(), seq)

	var kinds_lot_b: Array = [
		ElementRoster.Kind.MUR, ElementRoster.Kind.BARRIERE,
		ElementRoster.Kind.CHECKPOINT, ElementRoster.Kind.ROUTE_NORMALE, ElementRoster.Kind.LIGNE_DEPART_ARRIVEE,
	]
	for kind in kinds_lot_b:
		var avec_element: Track = TrackHardcoded.build()
		avec_element.add_element(kind, 0, 0, 0, 0) 
		var h: int = _run_sequence_sur_piste(avec_element, CarConfig.new(), seq)
		_check("élément sans effet en Lot A (kind %d) posé sous la voiture : hash identique à une piste sans éléments" % kind, h == h_reference)

func _test_element_reset() -> void:
	var config := CarConfigGt.new()
	config.bake()
	var track: Track = _build_element_track(ElementRoster.Kind.BOOST, 0, 0)
	var query := TrackQueryResult.new()
	var input := InputFrame.new()

	var state := CarState.new()
	state.reset(0, 0, 0, 0)  
	state.vit_z = config.vitesse_max 
	CarSim.tick(state, input, track, config, query)
	_check("reset (éléments) : boost déclenché une première fois", state.bonus_vitesse > 0)

	state.reset(0, 0, 0, 0)  
	state.vit_z = config.vitesse_max
	_check("reset (éléments) : elements_dans réarmé", state.elements_dans[0] == 0)
	CarSim.tick(state, input, track, config, query)
	_check("reset (éléments) : boost redéclenché après redémarrage sur le même pad", state.bonus_vitesse > 0)

	var track_vide: Track = _build_wide_track()
	CarSim.tick(state, input, track_vide, config, query)
	_check("reset (éléments) : passage à une piste sans élément ne plante pas", true)

	var track_deux: Track = _build_wide_track()
	track_deux.add_element(ElementRoster.Kind.BOOST, 0, 0, 0, 0)
	track_deux.add_element(ElementRoster.Kind.ROUTE_RALENTIT, Fixed.from_int(100), 0, Fixed.from_int(100), 0)
	CarSim.tick(state, input, track_deux, config, query)
	_check("reset (éléments) : passage à une piste à 2 éléments redimensionne elements_dans", state.elements_dans.size() == 2)

func _test_bake_unites() -> void:
	var config := CarConfigGt.new()
	config.bake()
	_check_approx("bake: adherence_laterale_ms2 -> /TICKS_PAR_SECONDE_CARRE (accélération)", config.adherence, Fixed.from_float(25.2 / float(Horloge.TICKS_PAR_SECONDE_CARRE)), 2)
	_check_approx("bake: angle_braquage_max_deg -> PAS de /TICKS_PAR_SECONDE (position angulaire)", config.angle_braquage_max, int(round(34.0 / 360.0 * 65536.0)), 1)
	_check_approx("bake: vitesse_braquage_deg_s -> /TICKS_PAR_SECONDE (taux angulaire)", config.vitesse_braquage, int(round(180.0 / 360.0 * 65536.0 / float(Horloge.TICKS_PAR_SECONDE))), 1)
	_check_approx("bake: vitesse_max_kmh -> /3.6/TICKS_PAR_SECONDE (vitesse cible par tick)", config.vitesse_max, Fixed.from_float(180.0 / 3.6 / float(Horloge.TICKS_PAR_SECONDE)), 2)

func _test_horloge() -> void:
	_check("horloge : la cadence divise 1000 ms exactement (condition du chrono au millième)", 1000 % Horloge.TICKS_PAR_SECONDE == 0)
	_check("horloge : MS_PAR_TICK cohérent avec TICKS_PAR_SECONDE", Horloge.MS_PAR_TICK * Horloge.TICKS_PAR_SECONDE == 1000)
	_check("time_format: format_ms rend bien un millième quelconque", TimeFormat.format_ms(834) == "0:00.834")
	_check("time_format: format_ms gère minutes et secondes", TimeFormat.format_ms(75123) == "1:15.123")
	_check("time_format: format_ticks reste cohérent avec format_ms", TimeFormat.format_ticks(1) == TimeFormat.format_ms(Horloge.MS_PAR_TICK))

func _test_input_crans() -> void:
	_check("InputCrans: uni_to_cran(0.0) == 0", InputCrans.uni_to_cran(0.0) == 0)
	_check("InputCrans: uni_to_cran(1.0) == QUANT_UNI", InputCrans.uni_to_cran(1.0) == InputCrans.QUANT_UNI)
	_check("InputCrans: uni_to_cran clampe au-delà de 1.0", InputCrans.uni_to_cran(2.0) == InputCrans.QUANT_UNI)
	_check("InputCrans: bi_to_cran(-1.0) == -QUANT_BI", InputCrans.bi_to_cran(-1.0) == -InputCrans.QUANT_BI)
	_check("InputCrans: bi_to_cran(0.0) == 0", InputCrans.bi_to_cran(0.0) == 0)
	_check("InputCrans: bi_to_cran(1.0) == QUANT_BI", InputCrans.bi_to_cran(1.0) == InputCrans.QUANT_BI)

	_check("InputCrans: cran_to_fixed_uni(0) == 0", InputCrans.cran_to_fixed_uni(0) == 0)
	_check_approx("InputCrans: cran_to_fixed_uni(QUANT_UNI) == Fixed.ONE", InputCrans.cran_to_fixed_uni(InputCrans.QUANT_UNI), Fixed.ONE, 1)
	_check_approx("InputCrans: cran_to_fixed_bi(QUANT_BI) == Fixed.ONE", InputCrans.cran_to_fixed_bi(InputCrans.QUANT_BI), Fixed.ONE, 1)
	_check_approx("InputCrans: cran_to_fixed_bi(-QUANT_BI) == -Fixed.ONE", InputCrans.cran_to_fixed_bi(-InputCrans.QUANT_BI), -Fixed.ONE, 1)

	var tous_dans_la_plage: bool = true
	var aller_retour_ok: bool = true
	for cran in range(-InputCrans.QUANT_BI, InputCrans.QUANT_BI + 1):
		var octet: int = InputCrans.bi_to_octet(cran)
		if octet < 0 or octet > 255:
			tous_dans_la_plage = false
		if InputCrans.octet_to_bi(octet) != cran:
			aller_retour_ok = false
	_check("InputCrans: bi_to_octet reste dans [0, 255] sur toute la plage [-127, 127]", tous_dans_la_plage)
	_check("InputCrans: octet_to_bi(bi_to_octet(c)) == c sur toute la plage", aller_retour_ok)

func _make_cran_sequence(n: int) -> Array:
	var accel: PackedByteArray = PackedByteArray()
	var frein: PackedByteArray = PackedByteArray()
	var braquage: PackedByteArray = PackedByteArray()
	var derapage: PackedByteArray = PackedByteArray()
	accel.resize(n); frein.resize(n); braquage.resize(n); derapage.resize(n)
	for i in range(n):
		var phase: int = i % 240
		accel[i] = InputCrans.QUANT_UNI if phase < 150 else 0
		frein[i] = InputCrans.QUANT_UNI if (phase >= 150 and phase < 180) else 0
		var steer_phase: int = i % 255
		var cran_braq: int = clampi(steer_phase - 127, -InputCrans.QUANT_BI, InputCrans.QUANT_BI)
		braquage[i] = InputCrans.bi_to_octet(cran_braq)
		derapage[i] = InputCrans.QUANT_UNI if (i % 300 >= 60 and i % 300 < 200) else 0
	return [accel, frein, braquage, derapage]

func _run_world_depuis_crans(accel: PackedByteArray, frein: PackedByteArray, braquage: PackedByteArray, derapage: PackedByteArray) -> World:
	var world: World = _build_test_world()
	var input := InputFrame.new()
	for i in range(accel.size()):
		input.accel = InputCrans.cran_to_fixed_uni(accel[i])
		input.frein = InputCrans.cran_to_fixed_uni(frein[i])
		input.braquage = InputCrans.cran_to_fixed_bi(InputCrans.octet_to_bi(braquage[i]))
		input.derapage = InputCrans.cran_to_fixed_uni(derapage[i])
		world.tick(input)
	return world

func _test_replay_round_trip() -> void:
	var crans: Array = _make_cran_sequence(2000)
	var accel: PackedByteArray = crans[0]
	var frein: PackedByteArray = crans[1]
	var braquage: PackedByteArray = crans[2]
	var derapage: PackedByteArray = crans[3]

	var world_a: World = _run_world_depuis_crans(accel, frein, braquage, derapage)

	var replay := ReplayData.new()
	replay.track_uid = "test"
	replay.vehicle_id = "gt"
	replay.finish_ms = 1234
	replay.start_tick = 0
	replay.accel_crans = accel
	replay.frein_crans = frein
	replay.braquage_crans = braquage
	replay.derapage_crans = derapage
	_check("replay round-trip: le replay encodé est cohérent (est_coherent)", replay.est_coherent())

	var world_b: World = _build_test_world()
	var input_b := InputFrame.new()
	for i in range(replay.tick_count()):
		replay.remplir_input(i, input_b)
		world_b.tick(input_b)

	_check("replay round-trip: enregistrer puis rejouer est bit-exact (hash)", world_a.state_hash() == world_b.state_hash())
	_check("replay round-trip: tableaux d'octets identiques après aller-retour", accel == replay.accel_crans and frein == replay.frein_crans and braquage == replay.braquage_crans and derapage == replay.derapage_crans)

func _test_replay_serialisation() -> void:
	var crans: Array = _make_cran_sequence(50)
	var replay := ReplayData.new()
	replay.track_uid = "piste_test"
	replay.vehicle_id = "hover"
	replay.finish_ms = 98765
	replay.date = "test"
	replay.hash_final = -1234567890123456789  
	replay.start_tick = 3
	replay.accel_crans = crans[0]
	replay.frein_crans = crans[1]
	replay.braquage_crans = crans[2]
	replay.derapage_crans = crans[3]

	var path: String = "user://_test_replay_tmp.tres"
	var err: Error = ResourceSaver.save(replay, path)
	_check("replay sérialisation: sauvegarde réussie", err == OK)

	var loaded: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	_check("replay sérialisation: rechargé comme ReplayData", loaded is ReplayData)
	if loaded is ReplayData:
		var r: ReplayData = loaded
		_check("replay sérialisation: hash_final (int64 signé pleine plage) préservé", r.hash_final == replay.hash_final)
		_check("replay sérialisation: start_tick préservé", r.start_tick == replay.start_tick)
		_check("replay sérialisation: les 4 tableaux d'octets préservés", r.accel_crans == replay.accel_crans and r.frein_crans == replay.frein_crans and r.braquage_crans == replay.braquage_crans and r.derapage_crans == replay.derapage_crans)
		_check("replay sérialisation: track_uid/vehicle_id préservés", r.track_uid == replay.track_uid and r.vehicle_id == replay.vehicle_id)

	DirAccess.remove_absolute(path)
	if FileAccess.file_exists(path + ".uid"):
		DirAccess.remove_absolute(path + ".uid")

func _test_deux_mondes_isoles() -> void:
	var seq_a: Array[InputFrame] = _make_input_sequence(1500)
	var seq_b: Array[InputFrame] = _make_input_sequence(1200) 

	var ref_a: int = _run_sequence(seq_a)
	var world_ref_b: World = _build_test_world()
	for f in seq_b:
		world_ref_b.tick(f)
	var ref_b: int = world_ref_b.state_hash()

	var track: Track = TrackHardcoded.build()
	var start: PackedInt64Array = TrackHardcoded.start_transform()
	var world_a := World.new()
	world_a.setup(track, CarConfig.new(), int(start[0]), int(start[1]), int(start[2]), int(start[3]))
	var world_b := World.new()
	world_b.setup(track, CarConfig.new(), int(start[0]), int(start[1]), int(start[2]), int(start[3]))

	var n: int = maxi(seq_a.size(), seq_b.size())
	for i in range(n):
		if i < seq_a.size():
			world_a.tick(seq_a[i])
		if i < seq_b.size():
			world_b.tick(seq_b[i])

	_check("deux mondes isolés: le monde A entrelacé retrouve le hash de la séquence A jouée seule", world_a.state_hash() == ref_a)
	_check("deux mondes isolés: le monde B entrelacé retrouve le hash de la séquence B jouée seule", world_b.state_hash() == ref_b)

func _make_dummy_replay(track_uid: String, vehicle_id: String, finish_ms: int) -> String:
	var replay := ReplayData.new()
	replay.track_uid = track_uid
	replay.vehicle_id = vehicle_id
	replay.finish_ms = finish_ms
	return ReplayStore.save(replay)

func _test_ghost_resolver() -> void:
	var track_uid: String = "ghost_resolver_test"
	var file_lent: String = _make_dummy_replay(track_uid, "gt", 5000)
	var file_rapide: String = _make_dummy_replay(track_uid, "gt", 4000)
	var file_formula: String = _make_dummy_replay(track_uid, "formula", 6000)

	var runs: Array[Dictionary] = [
		{"vehicule": "gt", "ms": 5000, "replay": file_lent},
		{"vehicule": "gt", "ms": 4000, "replay": file_rapide},
		{"vehicule": "gt", "ms": 1000, "replay": "fichier_jamais_sauvegarde.tres"},
		{"vehicule": "formula", "ms": 6000, "replay": file_formula},
	]

	var sel_perso_gt: Dictionary = {"source": GhostResolver.Source.PERSO, "vehicule": "gt", "fichier": ""}
	_check("GhostResolver PERSO: prend le meilleur run du bon véhicule, ignore l'orphelin plus rapide",
		GhostResolver.resolve(sel_perso_gt, runs, "", []) == file_rapide)

	var sel_perso_auto: Dictionary = {"source": GhostResolver.Source.PERSO, "vehicule": "", "fichier": ""}
	_check("GhostResolver PERSO(''): suit vehicule_courant",
		GhostResolver.resolve(sel_perso_auto, runs, "gt", []) == file_rapide)
	_check("GhostResolver PERSO(''): change de résultat si vehicule_courant change",
		GhostResolver.resolve(sel_perso_auto, runs, "formula", []) == file_formula)

	var file_record: String = _make_dummy_replay(track_uid, "gt", 3000)
	var runs_apres_record: Array[Dictionary] = runs.duplicate()
	runs_apres_record.append({"vehicule": "gt", "ms": 3000, "replay": file_record})
	_check("GhostResolver PERSO: un nouveau record change le fichier résolu, sélection inchangée",
		GhostResolver.resolve(sel_perso_gt, runs_apres_record, "", []) == file_record
		and int(sel_perso_gt["source"]) == GhostResolver.Source.PERSO)

	var sel_mondial: Dictionary = {"source": GhostResolver.Source.MONDIAL, "vehicule": "gt", "fichier": ""}
	_check("GhostResolver MONDIAL: aucun WR fourni -> retombe sur PERSO",
		GhostResolver.resolve(sel_mondial, runs, "", []) == file_rapide)
	var wr_lent: Array[Dictionary] = [{"vehicule": "gt", "ms": 10000, "fichier": "wr_lent.tres"}]
	_check("GhostResolver MONDIAL: record perso plus rapide que le WR -> dégrade vers PERSO",
		GhostResolver.resolve(sel_mondial, runs, "", wr_lent) == file_rapide)
	var wr_rapide: Array[Dictionary] = [{"vehicule": "gt", "ms": 100, "fichier": "wr_rapide.tres"}]
	_check("GhostResolver MONDIAL: WR plus rapide que le record perso -> reste sur le WR",
		GhostResolver.resolve(sel_mondial, runs, "", wr_rapide) == "wr_rapide.tres")

	var sel_manuel: Dictionary = {"source": GhostResolver.Source.MANUEL, "vehicule": "", "fichier": file_lent}
	_check("GhostResolver MANUEL: épinglé tel quel, ignore runs même après un nouveau record",
		GhostResolver.resolve(sel_manuel, runs_apres_record, "", []) == file_lent)

	var sel_aucun: Dictionary = {"source": GhostResolver.Source.AUCUN}
	_check("GhostResolver AUCUN: résout vers \"\"", GhostResolver.resolve(sel_aucun, runs, "", []) == "")

	var sources: Array[int] = [GhostResolver.Source.AUCUN, GhostResolver.Source.PERSO, GhostResolver.Source.MONDIAL, GhostResolver.Source.MANUEL]
	for source in sources:
		_check("GhostResolver source_name/source_from_name: aller-retour pour %d" % source,
			GhostResolver.source_from_name(GhostResolver.source_name(source)) == source)
	_check("GhostResolver source_from_name: chaîne inconnue -> AUCUN",
		GhostResolver.source_from_name("valeur_corrompue") == GhostResolver.Source.AUCUN)

	ReplayStore.delete_file(file_lent)
	ReplayStore.delete_file(file_rapide)
	ReplayStore.delete_file(file_formula)
	ReplayStore.delete_file(file_record)

func _test_track_grouping_alpha() -> void:
	var entries: Array[Dictionary] = [
		{"uid": "1", "nom": "Zebra"},
		{"uid": "2", "nom": "apple"},
		{"uid": "3", "nom": "3-way"},
		{"uid": "4", "nom": "Éclair"},
		{"uid": "5", "nom": "#hashtag"},
		{"uid": "6", "nom": ""},
		{"uid": "7", "nom": "amber"},
	]
	var sections: Array[Dictionary] = TrackGrouping.sections_alpha(entries, "nom")
	_check("grouping alpha: 5 sections non vides (A, E, Z, 0-9, Autre)", sections.size() == 5)
	if sections.size() == 5:
		_check("grouping alpha: ordre A, E, Z, 0-9, Autre",
			sections[0]["label"] == "A" and sections[1]["label"] == "E" and sections[2]["label"] == "Z"
			and sections[3]["label"] == "0-9" and sections[4]["label"] == "Autre")
		var section_a: Array = sections[0]["entries"]
		_check("grouping alpha: section A triée (amber avant apple)",
			section_a.size() == 2 and section_a[0]["nom"] == "amber" and section_a[1]["nom"] == "apple")
		_check("grouping alpha: accent normalisé (Éclair -> E)", sections[1]["entries"][0]["nom"] == "Éclair")
		_check("grouping alpha: chiffre -> 0-9", sections[3]["entries"][0]["nom"] == "3-way")
		var section_autre: Array = sections[4]["entries"]
		var uids_autre: Array = section_autre.map(func(e: Dictionary) -> String: return String(e["uid"]))
		_check("grouping alpha: vide et symbole -> Autre", uids_autre.has("5") and uids_autre.has("6"))

	_check("grouping alpha: borne chiffre '9'", TrackGrouping._alpha_label("9eme ciel") == "0-9")
	_check("grouping alpha: borne lettre 'A'", TrackGrouping._alpha_label("A") == "A")
	_check("grouping alpha: borne lettre 'Z'", TrackGrouping._alpha_label("z") == "Z")
	_check("grouping alpha: espaces seuls -> Autre", TrackGrouping._alpha_label("   ") == "Autre")

func _test_track_grouping_date_ajout() -> void:
	var jour1: int = 1700000000 
	var jour2: int = jour1 + 2 * 86400
	var str_jour1: String = Time.get_datetime_string_from_unix_time(jour1)
	var str_jour1_plus_tard: String = Time.get_datetime_string_from_unix_time(jour1 + 3600)
	var str_jour2: String = Time.get_datetime_string_from_unix_time(jour2)

	var entries: Array[Dictionary] = [
		{"uid": "a", "date_ajout": str_jour2},
		{"uid": "b", "date_ajout": str_jour1},
		{"uid": "c", "date_ajout": str_jour1_plus_tard},
		{"uid": "d", "date_ajout": ""},
	]
	var sections: Array[Dictionary] = TrackGrouping.sections_date_ajout(entries)
	_check("grouping date_ajout: 3 sections (jour2, jour1, Date inconnue)", sections.size() == 3)
	if sections.size() == 3:
		_check("grouping date_ajout: jour le plus récent en premier", sections[0]["entries"][0]["uid"] == "a")
		var section_jour1: Array = sections[1]["entries"]
		_check("grouping date_ajout: même jour regroupé, plus tardif en premier",
			section_jour1.size() == 2 and section_jour1[0]["uid"] == "c" and section_jour1[1]["uid"] == "b")
		_check("grouping date_ajout: Date inconnue en dernier",
			sections[2]["label"] == "Date inconnue" and sections[2]["entries"][0]["uid"] == "d")

func _test_track_grouping_duree() -> void:
	var meilleurs_temps: Dictionary = {
		"a": 10000, "b": 29999, "c": 30000, "d": 59999, "e": 60000,
		"f": 119999, "g": 120000, "h": 299999, "i": 300000, "j": 500000,
	}
	var entries: Array[Dictionary] = []
	for uid in ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k"]:
		entries.append({"uid": uid})  

	var sections: Array[Dictionary] = TrackGrouping.sections_duree(entries, meilleurs_temps)
	var attendu: Array[Array] = [
		["a", "b"], ["c", "d"], ["e", "f"], ["g", "h"], ["i", "j"], ["k"],
	]
	_check("grouping durée: 6 tranches non vides", sections.size() == attendu.size())
	if sections.size() == attendu.size():
		var ok: bool = true
		for i in range(attendu.size()):
			var uids: Array = (sections[i]["entries"] as Array).map(func(e: Dictionary) -> String: return String(e["uid"]))
			if uids != attendu[i]:
				ok = false
		_check("grouping durée: tranches croissantes, ordre ascendant dans chacune, inconnue en dernier", ok)

	_check("grouping durée: borne 29999ms", TrackGrouping._duree_label(29999) == "Moins de 30 secondes")
	_check("grouping durée: borne 30000ms", TrackGrouping._duree_label(30000) == "30 secondes à 1 minute")
	_check("grouping durée: borne 300000ms", TrackGrouping._duree_label(300000) == "Plus de 5 minutes")
	_check("grouping durée: jamais joué (-1)", TrackGrouping._duree_label(-1) == "Durée inconnue")

func _test_track_grouping_recemment_jouees() -> void:
	var now: float = Time.get_unix_time_from_system()
	var derniers_joues: Dictionary = {
		"a": now - 3600.0,        
		"b": now - 3.0 * 86400.0,   
		"c": now - 15.0 * 86400.0,   
		"d": now - 40.0 * 86400.0,  
	}
	var entries: Array[Dictionary] = [
		{"uid": "a"}, {"uid": "b"}, {"uid": "c"}, {"uid": "d"}, {"uid": "e"},  
	]
	var sections: Array[Dictionary] = TrackGrouping.sections_recemment_jouees(entries, derniers_joues)
	var attendu: Array[String] = ["a", "b", "c", "d", "e"]
	_check("grouping récence: 5 sections, la plus récente en premier, jamais en dernier",
		sections.size() == 5)
	if sections.size() == 5:
		var ok: bool = true
		for i in range(5):
			if (sections[i]["entries"] as Array)[0]["uid"] != attendu[i]:
				ok = false
		_check("grouping récence: une piste par section dans le bon ordre", ok)

	_check("grouping récence: borne 1 jour pile -> Cette semaine, pas Aujourd'hui",
		TrackGrouping._recence_label(now - 86400.0, now) == "Cette semaine")
	_check("grouping récence: borne 7 jours pile -> Ce mois-ci",
		TrackGrouping._recence_label(now - 7.0 * 86400.0, now) == "Ce mois-ci")
	_check("grouping récence: borne 30 jours pile -> plus d'un mois",
		TrackGrouping._recence_label(now - 30.0 * 86400.0, now) == "Il y a plus d'un mois")
	_check("grouping récence: jamais joué (-1)", TrackGrouping._recence_label(-1.0, now) == "Jamais jouée")

func _test_track_grouping_vehicule() -> void:
	var entries: Array[Dictionary] = [
		{"uid": "1", "nom": "Zebra Track"},
		{"uid": "2", "nom": "Alpha Track"},
	]
	var sections: Array[Dictionary] = TrackGrouping.sections_vehicule(entries)
	_check("grouping véhicule: une seule section 'Tous les véhicules'",
		sections.size() == 1 and sections[0]["label"] == "Tous les véhicules")
	if sections.size() == 1:
		var noms: Array = (sections[0]["entries"] as Array).map(func(e: Dictionary) -> String: return String(e["nom"]))
		_check("grouping véhicule: tri alphabétique", noms == ["Alpha Track", "Zebra Track"])
	_check("grouping véhicule: liste vide -> aucune section", TrackGrouping.sections_vehicule([]).is_empty())

func _test_configs_chargeables() -> void:
	var ids: PackedStringArray = ["gt", "formula", "superbike", "street_bike", "hover", "id_inconnu"]
	for id in ids:
		var config: CarConfig = CarConfig.charger(id)
		_check("config chargeable pour id '%s'" % id, config != null and config is CarConfig)
		config.bake()
		_check("config '%s': vitesse_max bakée non nulle" % id, config.vitesse_max > 0)
		_check("config '%s': accel_basse bakée non nulle" % id, config.accel_basse > 0)

func _test_jungle_dominante() -> void:
	var track := TrackJungle.build()
	track.prepare_progress(true)
	_check("jungle: circuit fermé et fortement lissé", track.est_ferme and track.point_count() == TrackJungle.ANCHORS.size() * (TrackJungle.SMOOTH_STEPS + 1))
	_check("jungle: longueur calibrée entre 900 et 1150 m",
		track.total_length() >= Fixed.from_int(900) and track.total_length() <= Fixed.from_int(1150))
	_check("jungle: thème visuel actif", track.visual_theme == "jungle")
	var narrow_count: int = 0
	var dirt_count: int = 0
	for i in range(track.point_count()):
		if track.surface_kind[i] == Track.Surface.TERRE:
			dirt_count += 1
		if track.half_width[i] == Fixed.from_int(TrackJungle.HW_HAIRPIN):
			narrow_count += 1
	_check("jungle: toute la piste est en terre", dirt_count == track.point_count())
	_check("jungle: longue section étroite des quatre épingles", narrow_count >= 70)
	_check("jungle: six rochers bloquants", track.element_count() == TrackJungle.ROCKS.size())

	var catalog: Array[Dictionary] = TrackCatalog.list_tracks()
	var found: bool = false
	for entry in catalog:
		if entry.get("uid", "") == TrackJungle.UID:
			found = entry.get("nom", "") == TrackJungle.NOM and entry.get("auteur", "") == TrackJungle.AUTEUR
	_check("jungle: présente au catalogue sous le nom et l'auteur demandés", found)

	var crossing: bool = false
	var n: int = track.point_count()
	for i in range(n):
		var i2: int = (i + 1) % n
		var a := Vector2(Fixed.to_float(track.point_x[i]), Fixed.to_float(track.point_z[i]))
		var b := Vector2(Fixed.to_float(track.point_x[i2]), Fixed.to_float(track.point_z[i2]))
		for j in range(i + 1, n):
			var j2: int = (j + 1) % n
			if i == j or i2 == j or j2 == i:
				continue
			var c := Vector2(Fixed.to_float(track.point_x[j]), Fixed.to_float(track.point_z[j]))
			var d := Vector2(Fixed.to_float(track.point_x[j2]), Fixed.to_float(track.point_z[j2]))
			if Geometry2D.segment_intersects_segment(a, b, c, d) != null:
				crossing = true
	_check("jungle: aucun segment ne se croise", not crossing)
	var routes_too_close: bool = false
	var minimum_distance_sq: int = Fixed.mul(Fixed.from_int(18), Fixed.from_int(18))
	for i in range(n):
		for j in range(i + 1, n):
			var index_distance: int = mini(j - i, n - (j - i))
			if index_distance <= 12:
				continue
			var dx: int = track.point_x[i] - track.point_x[j]
			var dz: int = track.point_z[i] - track.point_z[j]
			if Fixed.mul(dx, dx) + Fixed.mul(dz, dz) < minimum_distance_sq:
				routes_too_close = true
	_check("jungle: les portions non voisines restent séparées", not routes_too_close)
	var obstacle_query := TrackQueryResult.new()
	var obstacles_on_track: bool = true
	for i in range(track.element_count()):
		track.closest_point(track.elem_x[i], track.elem_z[i], obstacle_query)
		if Fixed.abs(obstacle_query.lateral_offset) > obstacle_query.half_width:
			obstacles_on_track = false
	_check("jungle: tous les rochers sont sur la piste", obstacles_on_track)
	var visual := TrackMesh.new()
	visual.build(track)
	_check("jungle: mesh, vibreurs, rochers et décor procédural se construisent", visual.mesh != null and visual.get_child_count() >= 13)
	visual.free()

func _test_element_obstacle_bloquant() -> void:
	var config := CarConfigGt.new()
	config.bake()
	var track: Track = _build_element_track(ElementRoster.Kind.OBSTACLE_BLOQUANT, 0, 0)
	var state := CarState.new()
	state.reset(0, 0, 0, 0)
	state.vit_z = config.vitesse_max
	var query := TrackQueryResult.new()
	CarSim.tick(state, InputFrame.new(), track, config, query)
	var distance: int = FixedMath.length_2d(state.pos_x, state.pos_z)
	_check("obstacle bloquant: la voiture est arrêtée", state.vit_x == 0 and state.vit_z == 0)
	_check("obstacle bloquant: la voiture est repoussée hors du rocher", distance >= ElementEffects.rayon_rocher - 2)

func _initialize() -> void:
	_test_fixed()
	_test_fixed_math()
	_test_replay_determinism()
	_test_race_state()
	_test_race_state_ouverte()
	_test_progress_validation()
	_test_collision_gabarit()
	_test_track_data_start_transform()
	_test_courbe_accel()
	_test_echelle_rotation()
	_test_braquage_progressif()
	_test_sous_virage()
	_test_glisse_raccourcit()
	_test_glisse_travers()
	_test_saut_arc()
	_test_permanente()
	_test_boost()
	_test_track_data_elements()
	_test_element_rayons()
	_test_element_boost()
	_test_element_rampe()
	_test_element_ralentit()
	_test_element_degrade_controles()
	_test_element_aimantee()
	_test_element_obstacle_ralentit()
	_test_element_obstacle_mortel()
	_test_element_obstacle_bloquant()
	_test_element_zones_ne_cumulent_pas()
	_test_element_sans_effet()
	_test_element_reset()
	_test_input_crans()
	_test_replay_round_trip()
	_test_replay_serialisation()
	_test_deux_mondes_isoles()
	_test_ghost_resolver()
	_test_track_grouping_alpha()
	_test_track_grouping_date_ajout()
	_test_track_grouping_duree()
	_test_track_grouping_recemment_jouees()
	_test_track_grouping_vehicule()
	_test_bake_unites()
	_test_configs_chargeables()
	_test_jungle_dominante()
	_test_horloge()
	_test_regression()

	print("")
	print("%d test(s) réussi(s), %d échec(s)" % [_passes, _failures])
	quit(1 if _failures > 0 else 0)
