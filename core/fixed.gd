# Arithmétique en virgule fixe Q16.16 (facteur d'échelle 65536).
# Toute la simulation (res://sim/, res://map/) doit passer par cette classe :
# aucun float ne doit influencer un calcul dont dépend le résultat d'un run.
#
# Conventions d'arrondi (à ne jamais mélanger pour une même grandeur) :
#   - mul() utilise >> : arrondi vers -infini (y compris sur les négatifs).
#   - div() utilise / (division entière GDScript) : troncature vers zéro.
#
# mul(a, b) suppose que a ET b sont deux grandeurs Q16.16 (ou que l'un des
# deux est un entier "brut" qu'on veut multiplier par une fraction Q16.16 —
# le résultat reste alors à l'échelle de l'entier brut, pas de Q16.16).
# Pour multiplier une grandeur Q16.16 par un entier simple sans échelle
# (compteur de ticks, signe -1/0/1 de Fixed.sign, etc.), utiliser
# l'opérateur * normal, jamais mul() : mul() diviserait le résultat par
# 65536 en trop.
class_name Fixed

const SHIFT: int = 16
const ONE: int = 1 << SHIFT
const HALF: int = ONE >> 1

# Multiplication de deux valeurs Q16.16. Le produit intermédiaire tient sur
# 64 bits pour l'amplitude de valeurs utilisée dans ce projet (positions en
# mètres, vitesses en m/tick), pas de dépassement à surveiller ici.
static func mul(a: int, b: int) -> int:
	return (a * b) >> SHIFT

static func div(a: int, b: int) -> int:
	return (a << SHIFT) / b

static func from_int(i: int) -> int:
	return i << SHIFT

# Rendu / debug uniquement — jamais dans un calcul de simulation.
static func to_float(v: int) -> float:
	return float(v) / float(ONE)

# Chargement de configuration uniquement (res://sim/car_config.gd) — jamais
# dans un calcul par tick.
static func from_float(f: float) -> int:
	return int(round(f * float(ONE)))

static func clamp(v: int, lo: int, hi: int) -> int:
	if v < lo:
		return lo
	if v > hi:
		return hi
	return v

static func abs(v: int) -> int:
	return -v if v < 0 else v

# Renvoie -1, 0 ou 1 : entier simple, pas une valeur Q16.16.
static func sign(v: int) -> int:
	if v > 0:
		return 1
	if v < 0:
		return -1
	return 0

# t est une valeur Q16.16 dans [0, ONE].
static func lerp(a: int, b: int, t: int) -> int:
	return a + mul(b - a, t)

static func min(a: int, b: int) -> int:
	return a if a < b else b

static func max(a: int, b: int) -> int:
	return a if a > b else b
