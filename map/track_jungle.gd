class_name TrackJungle

const UID: String = "jungle_dominante_v1"
const NOM: String = "La Jungle Dominante"
const AUTEUR: String = "Wiinny"
const HW_NORMAL: int = 6
const HW_HAIRPIN: int = 5

static func build() -> Track:
	var track := Track.new()
	track.visual_theme = "jungle"

	_add(track, 0, 0)
	_add(track, 0, 35)
	_add(track, 0, 75)
	_add(track, 4, 96)
	_add(track, 16, 113)
	_add(track, 36, 124, HW_NORMAL, Track.Surface.BOUE)
	_add(track, 65, 128, HW_NORMAL, Track.Surface.BOUE)
	_add(track, 95, 122)
	_add(track, 118, 106)
	_add(track, 133, 83)
	_add(track, 138, 55)
	_add(track, 134, 30)
	_add(track, 123, 10)
	_add(track, 112, 0)
	_add(track, 112, -25, HW_HAIRPIN)
	_add(track, 110, -40, HW_HAIRPIN)

	_add(track, 106, -48, HW_HAIRPIN)
	_add(track, 101, -53, HW_HAIRPIN)
	_add(track, 95, -55, HW_HAIRPIN)
	_add(track, 89, -52, HW_HAIRPIN)
	_add(track, 88, -43, HW_HAIRPIN)
	_add(track, 88, -12, HW_HAIRPIN)
	_add(track, 86, -3, HW_HAIRPIN)
	_add(track, 80, 3, HW_HAIRPIN)
	_add(track, 73, 5, HW_HAIRPIN)
	_add(track, 67, 2, HW_HAIRPIN)
	_add(track, 64, -6, HW_HAIRPIN)
	_add(track, 64, -45, HW_HAIRPIN)
	_add(track, 62, -52, HW_HAIRPIN)
	_add(track, 56, -57, HW_HAIRPIN)
	_add(track, 49, -59, HW_HAIRPIN)
	_add(track, 43, -56, HW_HAIRPIN)
	_add(track, 40, -48, HW_HAIRPIN)
	_add(track, 40, -12, HW_HAIRPIN)
	_add(track, 38, -3, HW_HAIRPIN)
	_add(track, 32, 3, HW_HAIRPIN)
	_add(track, 25, 5, HW_HAIRPIN)
	_add(track, 19, 2, HW_HAIRPIN)
	_add(track, 16, -6, HW_HAIRPIN)
	_add(track, 16, -48, HW_HAIRPIN)

	_add(track, 18, -68)
	_add(track, 34, -88)
	_add(track, 58, -104)
	_add(track, 82, -118, HW_NORMAL, Track.Surface.BOUE)
	_add(track, 54, -136, HW_NORMAL, Track.Surface.BOUE)
	_add(track, 12, -146, HW_NORMAL, Track.Surface.BOUE)
	_add(track, -35, -141)
	_add(track, -76, -125)
	_add(track, -106, -99)
	_add(track, -126, -66)
	_add(track, -133, -28)
	_add(track, -126, 10)
	_add(track, -110, 40)
	_add(track, -88, 62)
	_add(track, -62, 75)
	_add(track, -39, 77)
	_add(track, -21, 67)
	_add(track, -13, 50)
	_add(track, -17, 29)
	_add(track, -32, 13)
	_add(track, -48, -4)
	_add(track, -49, -22)
	_add(track, -39, -34)
	_add(track, -24, -39)
	_add(track, -10, -32)
	_add(track, 0, -20)

	return track

static func start_transform() -> PackedInt64Array:
	return PackedInt64Array([0, 0, 0, 0])

static func _add(track: Track, x: int, z: int, hw: int = HW_NORMAL, surface: int = Track.Surface.TERRE) -> void:
	var scaled_x: int = Fixed.div(Fixed.from_int(x * 2), Fixed.from_int(3))
	var scaled_z: int = Fixed.div(Fixed.from_int(z * 2), Fixed.from_int(3))
	track.add_point(scaled_x, 0, scaled_z, Fixed.from_int(hw), surface)
