# Détection de franchissement de la ligne d'arrivée. Déterministe (Q16.16
# uniquement, cf. core/fixed.gd) : la porte est calculée une fois depuis un
# segment de la piste — le PREMIER (point 0 -> point 1) si track.est_ferme
# (circuit : départ et arrivée confondus), le DERNIER si la piste est point à
# point (départ et arrivée physiquement distincts, voir map/track.gd) — puis
# chaque tick projette la position avant/après sur sa tangente pour détecter
# un passage.
#
# Un seul objet, créé une fois par res://sim/world.gd, muté en place — jamais
# recréé par tick.
class_name RaceState

const DEPARTED_THRESHOLD: int = 3 << 16  # Fixed.from_int(3), 3 m
const TIME_LIMIT_TICKS: int = Horloge.TICKS_PAR_SECONDE * 60 * 30  # 30 minutes pile
const TIME_LIMIT_MS: int = TIME_LIMIT_TICKS * Horloge.MS_PAR_TICK

var finished: bool = false
var finish_ms: int = 0  # temps de course en ms, interpolé au sous-tick (relatif au premier input)
var timed_out: bool = false
var started: bool = false  # true dès le premier input du joueur
var current_elapsed: int = 0  # temps de course courant, 0 tant que started == false

var _p0_x: int = 0
var _p0_z: int = 0
var _tangent_x: int = 0
var _tangent_z: int = Fixed.ONE
var _half_width: int = 0
var _departed: bool = false
var _needs_departure: bool = true  # voir setup()/reset()
var _start_tick: int = 0

# Calcule la géométrie de la porte d'arrivée — même calcul que
# Track.closest_point() pour le segment concerné (voir map/track.gd).
func setup(track: Track) -> void:
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
	# Sur un circuit, la porte EST le point d'apparition : sans attendre un
	# éloignement de DEPARTED_THRESHOLD, le tick 0 déclencherait une arrivée
	# immédiate (le joueur apparaît littéralement sur la ligne). Sur une piste
	# point à point, départ et arrivée sont physiquement éloignés — exiger cet
	# éloignement produirait l'effet inverse : la voiture reste tout le run du
	# côté "avant" négatif de cette porte-là (elle ne s'en approche qu'à la
	# toute fin), donc _departed ne passerait jamais à true avant le
	# franchissement lui-même, et aucune arrivée ne pourrait jamais se
	# déclencher.
	_needs_departure = track.est_ferme

func reset() -> void:
	finished = false
	finish_ms = 0
	timed_out = false
	started = false
	current_elapsed = 0
	_departed = not _needs_departure
	_start_tick = 0

# Appelée une fois par tick de simulation, avec la position avant/après ce
# tick et si l'input de ce tick est actif (accélérateur, frein ou braquage —
# voir sim/world.gd). Le chrono ne démarre qu'au premier input actif : tant
# que le joueur n'a rien pressé, cette fonction ne fait rien (current_elapsed
# reste à 0). Ne fait rien non plus une fois la course terminée ou le temps
# écoulé (l'un et l'autre ne redeviennent false qu'via reset()).
func tick(prev_x: int, prev_z: int, cur_x: int, cur_z: int, tick_number: int, input_active: bool) -> void:
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

	var prev_rel_x: int = prev_x - _p0_x
	var prev_rel_z: int = prev_z - _p0_z
	var cur_rel_x: int = cur_x - _p0_x
	var cur_rel_z: int = cur_z - _p0_z

	var prev_forward: int = Fixed.mul(prev_rel_x, _tangent_x) + Fixed.mul(prev_rel_z, _tangent_z)
	var cur_forward: int = Fixed.mul(cur_rel_x, _tangent_x) + Fixed.mul(cur_rel_z, _tangent_z)

	if not _departed:
		if cur_forward > DEPARTED_THRESHOLD:
			_departed = true
		return  # pas encore parti : jamais d'arrivée valide ce tick (évite le faux positif du tick 0)

	# Franchissement en sens inverse (prev_forward >= 0 et cur_forward < 0) :
	# ne correspond à aucune des branches ci-dessous, donc ignoré sans effet
	# de bord — c'est voulu, il ne doit jamais compter comme une arrivée.
	if prev_forward > 0 or cur_forward <= 0:
		return

	# prev_forward <= 0 < cur_forward : franchissement dans le bon sens.
	# Vérifie que ça se passe bien dans la largeur de la porte, pas au large.
	var right_x: int = _tangent_z
	var right_z: int = -_tangent_x
	var prev_lateral: int = Fixed.mul(prev_rel_x, right_x) + Fixed.mul(prev_rel_z, right_z)
	var cur_lateral: int = Fixed.mul(cur_rel_x, right_x) + Fixed.mul(cur_rel_z, right_z)

	var denom: int = cur_forward - prev_forward  # > 0 ici (cur_forward > 0 >= prev_forward)
	var t: int = Fixed.div(-prev_forward, denom)
	var lateral_at_crossing: int = prev_lateral + Fixed.mul(cur_lateral - prev_lateral, t)

	if Fixed.abs(lateral_at_crossing) <= _half_width:
		finished = true
		# Interpolation au sous-tick : `prev` est la position au tick
		# (current_elapsed - 1), `cur` au tick current_elapsed — la ligne a
		# été franchie entre les deux, à la fraction `t`. elapsed_fixed est
		# donc un nombre de ticks Q16.16 (pas une fraction [-1,1]) ; le
		# multiplier par MS_PAR_TICK (brut, 10) via Fixed.mul() est ici le
		# cas VOULU où le résultat doit redescendre à l'échelle brute (des ms
		# entières), pas rester en Q16.16 — à ne pas confondre avec le piège
		# documenté dans CLAUDE.md (Fixed.mul() d'une grandeur Q16.16
		# générale par un scalaire brut quand on veut au contraire GARDER
		# l'échelle Q16.16, comme pour dpsi dans sim/car_sim.gd).
		var elapsed_fixed: int = (current_elapsed - 1) * Fixed.ONE + t
		finish_ms = Fixed.mul(elapsed_fixed, Horloge.MS_PAR_TICK)
