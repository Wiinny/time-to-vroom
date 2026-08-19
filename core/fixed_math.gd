# Fonctions transcendantes en virgule fixe, pour res://sim/ et res://map/.
# Interdiction absolue d'appeler sin(), cos(), sqrt(), atan2(), pow() ici :
# tout passe par des tables précalculées (res://core/fixed_tables.gd, générée
# par tools/gen_tables.gd) ou des approximations entières.
class_name FixedMath

const OCTANT_TURN: int = 8192   # 65536 / 8  (45°)
const QUARTER_TURN: int = 16384  # 65536 / 4  (90°)
const HALF_TURN: int = 32768
const FULL_TURN: int = 65536
const TABLE_STEP: int = FULL_TURN / 1024  # entrées de FixedTables.SIN, cf. tools/gen_tables.gd

# angle : Q16.16 où 65536 représente un tour complet (au lieu de radians —
# évite toute normalisation en flottant sur les grands angles accumulés).
static func sin(angle: int) -> int:
	var a: int = angle & (FULL_TURN - 1)
	var index: int = a / TABLE_STEP
	var frac_units: int = a - index * TABLE_STEP
	var t: int = (frac_units << Fixed.SHIFT) / TABLE_STEP
	var v0: int = FixedTables.SIN[index]
	var v1: int = FixedTables.SIN[(index + 1) % FixedTables.TABLE_SIZE]
	return Fixed.lerp(v0, v1, t)

static func cos(angle: int) -> int:
	# Appel qualifié : un appel nu "sin(...)" ici résout vers le sin()
	# global (flottant) de GDScript plutôt que FixedMath.sin, faute de quoi
	# le résultat serait tronqué à 0 en silence.
	return FixedMath.sin(angle + QUARTER_TURN)

# Racine carrée entière par méthode de Newton. v est Q16.16 non-négatif.
static func sqrt(v: int) -> int:
	if v <= 0:
		return 0
	var n: int = v * Fixed.ONE
	var x: int = n
	var y: int = (x + 1) / 2
	while y < x:
		x = y
		y = (x + n / x) / 2
	return x

static func length_2d(x: int, z: int) -> int:
	return FixedMath.sqrt(Fixed.mul(x, x) + Fixed.mul(z, z))

# Approximation polynomiale d'atan (minimax, erreur max ~0.28°), évaluée par
# octant puis recomposée par symétrie. Renvoie un angle Q16.16 dans [0, 65536).
static func _octant_atan(z: int) -> int:
	# z est Q16.16 dans [0, ONE]. Coefficients ci-dessous déjà mis à l'échelle
	# de radians vers nos unités d'angle (65536 / 2π). Renvoie un angle dans
	# [0, OCTANT_TURN].
	var linear: int = Fixed.mul(Fixed.from_int(OCTANT_TURN), z)
	var p1: int = Fixed.mul(z, z - Fixed.ONE)
	var inner: int = Fixed.from_int(2552) + Fixed.mul(Fixed.from_int(692), z)
	var corr: int = Fixed.mul(p1, inner)
	return (linear - corr) >> Fixed.SHIFT

static func atan2(y: int, x: int) -> int:
	var abs_x: int = Fixed.abs(x)
	var abs_y: int = Fixed.abs(y)
	var base: int
	if abs_x == 0 and abs_y == 0:
		return 0
	if abs_y <= abs_x:
		var z: int = Fixed.div(abs_y, abs_x)
		base = _octant_atan(z)
	else:
		var z2: int = Fixed.div(abs_x, abs_y)
		base = QUARTER_TURN - _octant_atan(z2)

	if x >= 0 and y >= 0:
		return base
	if x < 0 and y >= 0:
		return HALF_TURN - base
	if x < 0 and y < 0:
		return HALF_TURN + base
	return FULL_TURN - base
