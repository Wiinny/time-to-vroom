class_name Track

const LOCAL_SEARCH_BEHIND: int = 6
const LOCAL_SEARCH_AHEAD: int = 12

var point_x: PackedInt64Array = PackedInt64Array()
var point_y: PackedInt64Array = PackedInt64Array()
var point_z: PackedInt64Array = PackedInt64Array()
var half_width: PackedInt64Array = PackedInt64Array()

var est_ferme: bool = true

var elem_kind: PackedByteArray = PackedByteArray()
var elem_x: PackedInt64Array = PackedInt64Array()
var elem_y: PackedInt64Array = PackedInt64Array()
var elem_z: PackedInt64Array = PackedInt64Array()
var elem_rotation: PackedInt64Array = PackedInt64Array()

var _segment_start: PackedInt64Array = PackedInt64Array()
var _segment_length: PackedInt64Array = PackedInt64Array()
var _total_length: int = 0
var _progress_ready: bool = false

func point_count() -> int:
	return point_x.size()

func add_point(x: int, y: int, z: int, hw: int) -> void:
	point_x.push_back(x)
	point_y.push_back(y)
	point_z.push_back(z)
	half_width.push_back(hw)
	_progress_ready = false

func element_count() -> int:
	return elem_kind.size()

func add_element(kind: int, x: int, y: int, z: int, rotation: int) -> void:
	elem_kind.push_back(kind)
	elem_x.push_back(x)
	elem_y.push_back(y)
	elem_z.push_back(z)
	elem_rotation.push_back(rotation)

func prepare_progress(force: bool = false) -> void:
	var count: int = segment_count()
	if _progress_ready and not force and _segment_length.size() == count:
		return
	_segment_start.resize(count)
	_segment_length.resize(count)
	_total_length = 0
	var n: int = point_count()
	for i in range(count):
		var j: int = (i + 1) % n
		var dx: int = point_x[j] - point_x[i]
		var dz: int = point_z[j] - point_z[i]
		var length: int = FixedMath.sqrt(Fixed.mul(dx, dx) + Fixed.mul(dz, dz))
		_segment_start[i] = _total_length
		_segment_length[i] = length
		_total_length += length
	_progress_ready = true

func segment_count() -> int:
	var n: int = point_count()
	return n if est_ferme else maxi(0, n - 1)

func total_length() -> int:
	prepare_progress()
	return _total_length

func segment_start(index: int) -> int:
	prepare_progress()
	return _segment_start[index]

func closest_point(px: int, pz: int, result: TrackQueryResult) -> void:
	prepare_progress()
	var count: int = segment_count()
	var best_dist_sq: int = -1
	for i in range(count):
		best_dist_sq = _consider_segment(px, pz, i, best_dist_sq, result)
	result.initialized = best_dist_sq >= 0

func closest_point_near(px: int, pz: int, result: TrackQueryResult) -> void:
	prepare_progress()
	var count: int = segment_count()
	if not result.initialized:
		closest_point(px, pz, result)
		return

	var hint: int = result.segment_index

	var best_dist_sq: int = _consider_segment(px, pz, hint, -1, result)
	if est_ferme:
		for offset in range(1, LOCAL_SEARCH_AHEAD + 1):
			best_dist_sq = _consider_segment(px, pz, posmod(hint + offset, count), best_dist_sq, result)
		for offset in range(1, LOCAL_SEARCH_BEHIND + 1):
			best_dist_sq = _consider_segment(px, pz, posmod(hint - offset, count), best_dist_sq, result)
	else:
		for offset in range(1, LOCAL_SEARCH_AHEAD + 1):
			if hint + offset < count:
				best_dist_sq = _consider_segment(px, pz, hint + offset, best_dist_sq, result)
		for offset in range(1, LOCAL_SEARCH_BEHIND + 1):
			if hint - offset >= 0:
				best_dist_sq = _consider_segment(px, pz, hint - offset, best_dist_sq, result)
	result.initialized = best_dist_sq >= 0

func _consider_segment(px: int, pz: int, i: int, best_dist_sq: int, result: TrackQueryResult) -> int:
	var n: int = point_count()
	var j: int = (i + 1) % n
	var ax: int = point_x[i]
	var az: int = point_z[i]
	var bx: int = point_x[j]
	var bz: int = point_z[j]
	var dx: int = bx - ax
	var dz: int = bz - az
	var seg_len_sq: int = Fixed.mul(dx, dx) + Fixed.mul(dz, dz)
	if seg_len_sq == 0:
		return best_dist_sq

	var wx: int = px - ax
	var wz: int = pz - az
	var dot: int = Fixed.mul(wx, dx) + Fixed.mul(wz, dz)
	var t: int = Fixed.clamp(Fixed.div(dot, seg_len_sq), 0, Fixed.ONE)
	var cx: int = ax + Fixed.mul(dx, t)
	var cz: int = az + Fixed.mul(dz, t)
	var ddx: int = px - cx
	var ddz: int = pz - cz
	var dist_sq: int = Fixed.mul(ddx, ddx) + Fixed.mul(ddz, ddz)

	if best_dist_sq >= 0 and dist_sq >= best_dist_sq:
		return best_dist_sq

	var seg_len: int = _segment_length[i]
	var tangent_x: int = Fixed.div(dx, seg_len)
	var tangent_z: int = Fixed.div(dz, seg_len)

	result.segment_index = i
	result.segment_t = t
	result.progress = _segment_start[i] + Fixed.mul(seg_len, t)
	result.closest_x = cx
	result.closest_z = cz
	result.forward_x = tangent_x
	result.forward_z = tangent_z
	result.right_x = tangent_z
	result.right_z = -tangent_x
	result.lateral_offset = Fixed.mul(ddx, tangent_z) - Fixed.mul(ddz, tangent_x)
	result.height = point_y[i] + Fixed.mul(point_y[j] - point_y[i], t)
	result.half_width = half_width[i] + Fixed.mul(half_width[j] - half_width[i], t)
	return dist_sq
