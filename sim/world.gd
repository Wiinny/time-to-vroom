# Orchestrateur de la simulation. Ne connaît rien du rendu (pas de Node3D,
# pas de caméra, pas d'entrée clavier directe) — tourne à l'identique en
# --headless. res://main.gd lui fournit un InputFrame déjà quantifié à
# chaque _physics_process et lit son état pour l'affichage.
class_name World

var tick_number: int = 0
var track: Track
var car_state: CarState = CarState.new()
var car_config: CarConfig
var race_state: RaceState = RaceState.new()

var _query: TrackQueryResult = TrackQueryResult.new()

func setup(a_track: Track, a_config: CarConfig, start_x: int, start_y: int, start_z: int, start_yaw: int) -> void:
	track = a_track
	car_config = a_config
	car_config.bake()
	tick_number = 0
	car_state.reset(start_x, start_y, start_z, start_yaw)
	race_state.setup(track)
	race_state.reset()

func tick(input: InputFrame) -> void:
	var prev_x: int = car_state.pos_x
	var prev_z: int = car_state.pos_z
	CarSim.tick(car_state, input, track, car_config, _query)
	tick_number += 1
	var input_active: bool = input.accel != 0 or input.frein != 0 or input.braquage != 0
	race_state.tick(prev_x, prev_z, car_state.pos_x, car_state.pos_z, tick_number, input_active)

# Raccourci pour la validation de replay (voir replay/replay_data.gd) et les
# tests de non-régression.
func state_hash() -> int:
	return car_state.compute_hash(tick_number)
