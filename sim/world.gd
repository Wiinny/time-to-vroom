class_name World

var tick_number: int = 0
var track: Track
var car_state: CarState = CarState.new()
var car_config: CarConfig
var race_state: RaceState = RaceState.new()

var _query: TrackQueryResult = TrackQueryResult.new()

func setup(a_track: Track, a_config: CarConfig, start_x: int, start_y: int, start_z: int, start_yaw: int) -> void:
	track = a_track
	track.prepare_progress(true)
	car_config = a_config
	car_config.bake()
	tick_number = 0
	_query.reset()
	car_state.reset(start_x, start_y, start_z, start_yaw)
	race_state.setup(track)
	race_state.reset()

func tick(input: InputFrame) -> void:
	var prev_x: int = car_state.pos_x
	var prev_z: int = car_state.pos_z
	CarSim.tick(car_state, input, track, car_config, _query)
	tick_number += 1
	var input_active: bool = input.accel != 0 or input.frein != 0 or input.braquage != 0
	race_state.tick(prev_x, prev_z, car_state.pos_x, car_state.pos_z, tick_number, input_active, _query)

func state_hash() -> int:
	return car_state.compute_hash(tick_number)
