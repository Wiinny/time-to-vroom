class_name RaceState

const DEPARTED_THRESHOLD: int = 3 << 16  
const TIME_LIMIT_TICKS: int = Horloge.TICKS_PAR_SECONDE * 60 * 30  
const TIME_LIMIT_MS: int = TIME_LIMIT_TICKS * Horloge.MS_PAR_TICK
const VALIDATION_SPACING_M: int = 20
const MIN_VALIDATION_SECTORS: int = 8
const MAX_VALIDATION_SECTORS: int = 64
const MAX_PROGRESS_STEP_M: int = 5
static var MAX_PROGRESS_STEP: int = Fixed.from_int(MAX_PROGRESS_STEP_M)

var finished: bool = false
var finish_ms: int = 0  
var timed_out: bool = false
var started: bool = false 
var current_elapsed: int = 0  
var run_valid: bool = true
var validation_zone_count: int = 0
var validated_zone_count: int = 0

var _p0_x: int = 0
var _p0_z: int = 0
var _tangent_x: int = 0
var _tangent_z: int = Fixed.ONE
var _half_width: int = 0
var _departed: bool = false
var _needs_departure: bool = true 
var _start_tick: int = 0
var _track: Track
var _validation_enabled: bool = true
var _validation_gates: PackedInt64Array = PackedInt64Array()
var _race_length: int = 0
var _last_progress: int = 0
var _unwrapped_progress: int = 0
var _has_progress: bool = false
var _fallback_query: TrackQueryResult = TrackQueryResult.new()

func setup(track: Track, enable_progress_validation: bool = true) -> void:
	_track = track
	_validation_enabled = enable_progress_validation
	track.prepare_progress(true)
	var n: int = track.point_count()
	var g: int = 0 if track.est_ferme else max(0, n - 2)
	_p0_x = track.point_x[g]
	_p0_z = track.point_z[g]
	var dx: int = track.point_x[g + 1] - _p0_x
	var dz: int = track.point_z[g + 1] - _p0_z
	var seg_len: int = FixedMath.sqrt(Fixed.mul(dx, dx) + Fixed.mul(dz, dz))
	_tangent_x = Fixed.div(dx, seg_len)
	_tangent_z = Fixed.div(dz, seg_len)
	_half_width = track.half_width[g]
	_needs_departure = track.est_ferme
	_race_length = track.total_length() if track.est_ferme else track.segment_start(g)
	_build_validation_gates()

func _build_validation_gates() -> void:
	_validation_gates.clear()
	if not _validation_enabled or _race_length <= 0:
		validation_zone_count = 0
		return
	var spacing: int = Fixed.from_int(VALIDATION_SPACING_M)
	var sectors: int = (_race_length + spacing - 1) / spacing
	sectors = clampi(sectors, MIN_VALIDATION_SECTORS, MAX_VALIDATION_SECTORS)
	for i in range(1, sectors):
		_validation_gates.push_back(_race_length * i / sectors)
	validation_zone_count = _validation_gates.size()

func reset() -> void:
	finished = false
	finish_ms = 0
	timed_out = false
	started = false
	current_elapsed = 0
	run_valid = true
	validated_zone_count = 0
	_departed = not _needs_departure
	_start_tick = 0
	_last_progress = 0
	_unwrapped_progress = 0
	_has_progress = false
	_fallback_query.reset()

func tick(prev_x: int, prev_z: int, cur_x: int, cur_z: int, tick_number: int, input_active: bool, track_query: TrackQueryResult = null) -> void:
	if finished or timed_out:
		return

	if not started:
		if not input_active:
			return
		started = true
		_start_tick = tick_number

	current_elapsed = tick_number - _start_tick

	if current_elapsed >= TIME_LIMIT_TICKS:
		timed_out = true
		return

	if _validation_enabled:
		_update_progress(cur_x, cur_z, track_query)

	var prev_rel_x: int = prev_x - _p0_x
	var prev_rel_z: int = prev_z - _p0_z
	var cur_rel_x: int = cur_x - _p0_x
	var cur_rel_z: int = cur_z - _p0_z

	var prev_forward: int = Fixed.mul(prev_rel_x, _tangent_x) + Fixed.mul(prev_rel_z, _tangent_z)
	var cur_forward: int = Fixed.mul(cur_rel_x, _tangent_x) + Fixed.mul(cur_rel_z, _tangent_z)

	if not _departed:
		if cur_forward > DEPARTED_THRESHOLD:
			_departed = true
		return 

	if prev_forward > 0 or cur_forward <= 0:
		return

	var right_x: int = _tangent_z
	var right_z: int = -_tangent_x
	var prev_lateral: int = Fixed.mul(prev_rel_x, right_x) + Fixed.mul(prev_rel_z, right_z)
	var cur_lateral: int = Fixed.mul(cur_rel_x, right_x) + Fixed.mul(cur_rel_z, right_z)

	var denom: int = cur_forward - prev_forward 
	var t: int = Fixed.div(-prev_forward, denom)
	var lateral_at_crossing: int = prev_lateral + Fixed.mul(cur_lateral - prev_lateral, t)

	var progression_complete: bool = not _validation_enabled or validated_zone_count == validation_zone_count
	if Fixed.abs(lateral_at_crossing) <= _half_width and run_valid and progression_complete:
		finished = true
		var elapsed_fixed: int = (current_elapsed - 1) * Fixed.ONE + t
		finish_ms = Fixed.mul(elapsed_fixed, Horloge.MS_PAR_TICK)

func _update_progress(cur_x: int, cur_z: int, track_query: TrackQueryResult) -> void:
	var query: TrackQueryResult = track_query
	if query == null:
		_track.closest_point_near(cur_x, cur_z, _fallback_query)
		query = _fallback_query
	if not query.initialized:
		run_valid = false
		return

	var current: int = query.progress
	if not _has_progress:
		_last_progress = current
		_has_progress = true
		return

	var delta: int = current - _last_progress
	if _track.est_ferme and _race_length > 0:
		var half_lap: int = _race_length / 2
		if delta < -half_lap:
			delta += _race_length
		elif delta > half_lap:
			delta -= _race_length
	_last_progress = current

	if Fixed.abs(delta) > MAX_PROGRESS_STEP:
		run_valid = false
		return

	_unwrapped_progress = maxi(0, _unwrapped_progress + delta)
	while validated_zone_count < validation_zone_count and _unwrapped_progress >= _validation_gates[validated_zone_count]:
		validated_zone_count += 1
