class_name TrackJungle

const UID: String = "jungle_dominante_v2"
const NOM: String = "La Jungle Dominante"
const AUTEUR: String = "Wiinny"
const HW_NORMAL: int = 6
const HW_HAIRPIN: int = 5
const SMOOTH_STEPS: int = 5
const CORNER_CUT_M: int = 11
const SCALE_NUM: int = 17
const SCALE_DEN: int = 20

const ANCHORS: Array[Vector2i] = [
	Vector2i(0, 0),
	Vector2i(0, 55),
	Vector2i(20, 85),
	Vector2i(65, 95),
	Vector2i(105, 78),
	Vector2i(125, 45),
	Vector2i(124, 10),
	Vector2i(135, -15),
	Vector2i(135, -55),
	Vector2i(121, -72),
	Vector2i(107, -55),
	Vector2i(107, -18),
	Vector2i(93, -2),
	Vector2i(79, -18),
	Vector2i(79, -55),
	Vector2i(65, -72),
	Vector2i(51, -55),
	Vector2i(51, -18),
	Vector2i(37, -2),
	Vector2i(23, -18),
	Vector2i(23, -60),
	Vector2i(10, -93),
	Vector2i(-50, -115),
	Vector2i(-95, -110),
	Vector2i(-130, -80),
	Vector2i(-145, -35),
	Vector2i(-140, 15),
	Vector2i(-115, 55),
	Vector2i(-80, 78),
	Vector2i(-45, 75),
	Vector2i(-25, 55),
	Vector2i(-38, 35),
	Vector2i(-58, 20),
	Vector2i(-65, -5),
	Vector2i(-55, -30),
	Vector2i(-32, -42),
	Vector2i(-10, -36),
	Vector2i(0, -25),
]

const ROCKS: Array[Vector2i] = [
	Vector2i(2, 36),
	Vector2i(55, 92),
	Vector2i(120, 27),
	Vector2i(-34, -105),
	Vector2i(-132, -73),
	Vector2i(-96, 66),
]

static func build() -> Track:
	var track := Track.new()
	track.visual_theme = "jungle"
	var count: int = ANCHORS.size()
	for i in range(count):
		var previous: Vector2i = ANCHORS[(i - 1 + count) % count]
		var current: Vector2i = ANCHORS[i]
		var following: Vector2i = ANCHORS[(i + 1) % count]
		var ax: int = _scaled(previous.x)
		var az: int = _scaled(previous.y)
		var bx: int = _scaled(current.x)
		var bz: int = _scaled(current.y)
		var cx: int = _scaled(following.x)
		var cz: int = _scaled(following.y)
		var prev_dx: int = ax - bx
		var prev_dz: int = az - bz
		var next_dx: int = cx - bx
		var next_dz: int = cz - bz
		var prev_length: int = FixedMath.length_2d(prev_dx, prev_dz)
		var next_length: int = FixedMath.length_2d(next_dx, next_dz)
		var cut: int = Fixed.min(Fixed.from_int(CORNER_CUT_M), Fixed.min(Fixed.div(prev_length, Fixed.from_int(3)), Fixed.div(next_length, Fixed.from_int(3))))
		var entry_x: int = bx + Fixed.mul(prev_dx, Fixed.div(cut, prev_length))
		var entry_z: int = bz + Fixed.mul(prev_dz, Fixed.div(cut, prev_length))
		var exit_x: int = bx + Fixed.mul(next_dx, Fixed.div(cut, next_length))
		var exit_z: int = bz + Fixed.mul(next_dz, Fixed.div(cut, next_length))
		var width: int = HW_HAIRPIN if i >= 8 and i <= 20 else HW_NORMAL
		track.add_point(entry_x, 0, entry_z, Fixed.from_int(width), Track.Surface.TERRE)
		for step in range(1, SMOOTH_STEPS + 1):
			var t: int = Fixed.div(Fixed.from_int(step), Fixed.from_int(SMOOTH_STEPS))
			var inv: int = Fixed.ONE - t
			var inv_sq: int = Fixed.mul(inv, inv)
			var t_sq: int = Fixed.mul(t, t)
			var middle: int = Fixed.mul(Fixed.from_int(2), Fixed.mul(inv, t))
			var x: int = Fixed.mul(inv_sq, entry_x) + Fixed.mul(middle, bx) + Fixed.mul(t_sq, exit_x)
			var z: int = Fixed.mul(inv_sq, entry_z) + Fixed.mul(middle, bz) + Fixed.mul(t_sq, exit_z)
			track.add_point(x, 0, z, Fixed.from_int(width), Track.Surface.TERRE)
	for rock in ROCKS:
		track.add_element(ElementRoster.Kind.OBSTACLE_BLOQUANT, _scaled(rock.x), 0, _scaled(rock.y), 0)
	return track

static func start_transform() -> PackedInt64Array:
	var track: Track = build()
	var yaw: int = FixedMath.atan2(track.point_x[1] - track.point_x[0], track.point_z[1] - track.point_z[0])
	return PackedInt64Array([track.point_x[0], track.point_y[0], track.point_z[0], yaw])

static func _scaled(value: int) -> int:
	return Fixed.div(Fixed.from_int(value * SCALE_NUM), Fixed.from_int(SCALE_DEN))
