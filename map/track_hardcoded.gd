class_name TrackHardcoded

const HW_NORMAL: int = 5
const HW_HAIRPIN: int = 4

static func build() -> Track:
	var track: Track = Track.new()

	var x: int = 0
	var z: int = 0
	var h: int = 0  # cap 0 = +Z ("nord")

	track.add_point(x, 0, z, Fixed.from_int(HW_NORMAL))  # P0 — ligne de départ

	var st: PackedInt64Array
	st = TrackBuilder.ajouter_droite(track, x, z, h, 60, HW_NORMAL, 0)
	x = st[0]; z = st[1]; h = int(st[2])

	# Virage large n°1 : 90° à droite, rayon 24 m, légère montée.
	st = TrackBuilder.ajouter_arc(track, x, z, h, 24, 16384, HW_NORMAL, 1, 8)
	x = st[0]; z = st[1]; h = int(st[2])

	st = TrackBuilder.ajouter_droite(track, x, z, h, 40, HW_NORMAL, 2)
	x = st[0]; z = st[1]; h = int(st[2])

	# Virage large n°2 : 90° à droite, rayon 24 m, redescente.
	st = TrackBuilder.ajouter_arc(track, x, z, h, 24, 16384, HW_NORMAL, 1, 8)
	x = st[0]; z = st[1]; h = int(st[2])

	st = TrackBuilder.ajouter_droite(track, x, z, h, 20, HW_HAIRPIN, 0)
	x = st[0]; z = st[1]; h = int(st[2])

	# Chicane resserrée (droite 90° puis gauche 90°, rayon 9 m) : reste tout
	# près du virage n°2 mais bien plus bas (z ~= 22-31, contre 60-84 pour le
	# virage n°2), donc jamais à moins d'une largeur de piste de lui.
	st = TrackBuilder.ajouter_arc(track, x, z, h, 9, 16384, HW_HAIRPIN, 0, 6)
	x = st[0]; z = st[1]; h = int(st[2])
	st = TrackBuilder.ajouter_arc(track, x, z, h, 9, -16384, HW_HAIRPIN, 0, 6)
	x = st[0]; z = st[1]; h = int(st[2])

	# Retour : longue ligne droite vers le sud, largement sous le reste du
	# circuit (z négatif), puis deux virages à droite et une ligne droite
	# vers l'ouest pour amener la piste du côté opposé au départ.
	st = TrackBuilder.ajouter_droite(track, x, z, h, 32, HW_NORMAL, 0)
	x = st[0]; z = st[1]; h = int(st[2])

	st = TrackBuilder.ajouter_arc(track, x, z, h, 20, 16384, HW_NORMAL, 0, 8)
	x = st[0]; z = st[1]; h = int(st[2])

	st = TrackBuilder.ajouter_droite(track, x, z, h, 20, HW_NORMAL, 0)
	x = st[0]; z = st[1]; h = int(st[2])

	# Virage de fermeture (90° à droite, rayon 30 m) : calculé pour finir
	# exactement sur P0 avec le même cap qu'au départ — la boucle se referme
	# sans segment de raccord ni croisement.
	TrackBuilder.ajouter_arc(track, x, z, h, 30, 16384, HW_NORMAL, 0, 10)

	return track

static func start_transform() -> PackedInt64Array:
	# [x, y, z, cap] du point de départ en Q16.16 (cap en unités FixedMath,
	# 65536 = un tour) — même contrat que TrackData.start_transform(), pour
	# res://main.gd. Tout est à zéro ici, donc la valeur ne change pas avec
	# ce contrat ; c'est l'appelant qui ne doit plus reconvertir (piège
	# rencontré : main.gd appliquait Fixed.from_int() sur une position déjà
	# Q16.16 venant de TrackData, décalant la voiture à une position
	# multipliée par 65536 — invisible ici seulement parce que 0 * 65536 = 0).
	return PackedInt64Array([0, 0, 0, 0])
