# Helpers de construction procédurale de piste (droites et arcs), en virgule
# fixe — aucun sin()/cos() flottant natif, pour que la géométrie soit
# identique d'une machine à l'autre (elle influence directement les résultats
# de run via les bords de piste). Extrait de map/track_hardcoded.gd (qui
# délègue maintenant ici) pour être réutilisable sans duplication par
# tools/bench_equilibrage.gd et tools/bench_rayon.gd.
class_name TrackBuilder

# Avance tout droit sur `length_m` mètres depuis (x0, z0, h0) et ajoute le
# point d'arrivée à la piste. Renvoie [x1, z1, h0] (le cap ne change pas).
static func ajouter_droite(track: Track, x0: int, z0: int, h0: int, length_m: int, hw: int, y: int) -> PackedInt64Array:
	var dx: int = Fixed.mul(FixedMath.sin(h0), Fixed.from_int(length_m))
	var dz: int = Fixed.mul(FixedMath.cos(h0), Fixed.from_int(length_m))
	var x1: int = x0 + dx
	var z1: int = z0 + dz
	track.add_point(x1, Fixed.from_int(y), z1, Fixed.from_int(hw))
	return PackedInt64Array([x1, z1, h0])

# Balaie un arc de rayon `radius_m` et d'angle signé `delta_angle` (unités
# d'angle brutes, + = virage à droite) depuis (x0, z0, h0), en ajoutant
# `steps` points intermédiaires. Renvoie [x_fin, z_fin, cap_fin].
static func ajouter_arc(track: Track, x0: int, z0: int, h0: int, radius_m: int, delta_angle: int, hw: int, y: int, steps: int) -> PackedInt64Array:
	var r: int = Fixed.from_int(radius_m)
	var fwd0_x: int = FixedMath.sin(h0)
	var fwd0_z: int = FixedMath.cos(h0)
	var right0_x: int = fwd0_z
	var right0_z: int = -fwd0_x
	var s: int = 1 if delta_angle >= 0 else -1
	var y_fixed: int = Fixed.from_int(y)
	var hw_fixed: int = Fixed.from_int(hw)

	var last: PackedInt64Array = PackedInt64Array([x0, z0, h0])
	for k in range(1, steps + 1):
		var theta: int = int(delta_angle * k / steps)
		var abs_theta: int = theta if theta >= 0 else -theta
		var forward_disp: int = Fixed.mul(r, FixedMath.sin(abs_theta))
		var right_disp: int = s * Fixed.mul(r, Fixed.ONE - FixedMath.cos(abs_theta))
		var x: int = x0 + Fixed.mul(forward_disp, fwd0_x) + Fixed.mul(right_disp, right0_x)
		var z: int = z0 + Fixed.mul(forward_disp, fwd0_z) + Fixed.mul(right_disp, right0_z)
		track.add_point(x, y_fixed, z, hw_fixed)
		last = PackedInt64Array([x, z, (h0 + theta) & (FixedMath.FULL_TURN - 1)])
	return last
