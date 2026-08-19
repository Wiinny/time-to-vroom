# Instrument de mesure (pas un test qui échoue) : chronomètre les 5
# véhicules sur une piste de référence "délibérément moyenne" et affiche
# l'écart entre eux. Objectif du cahier des charges (Paramétrage-Véhicules.md) :
# les 5 chronos doivent tenir dans une fourchette de quelques pour cent.
#   "$GODOT" --headless --path . --script res://tools/bench_equilibrage.gd
extends SceneTree

const HW: int = 5
const LIMITE_TICKS: int = 10000  # garde-fou, 100 s — largement suffisant pour ~1 km (les tours réussis prennent 30-40 s)

# Moitié A du circuit : chaque entrée est une droite {longueur_m, hw} ou un
# arc {rayon_m, delta_angle, steps, hw}. Rejouée deux fois à l'identique
# (voir _build_reference_track) — fermeture par symétrie centrale, PAS par
# résolution géométrique : si la somme des delta_angle vaut exactement 180°
# (32768 unités), rejouer la même séquence depuis la position/cap de fin
# ramène exactement au point de départ, même cap. Inclut une zone à demi-
# largeur réduite (5 m -> 3 m sur 40 m) en approximation d'une zone de plots
# (obstacle_ralentit, non simulé — voir l'avertissement imprimé au lancement).
const PROGRAMME_MOITIE: Array = [
	{"type": "droite", "longueur": 90, "hw": HW},
	{"type": "arc", "rayon": 45, "delta": 16384, "steps": 10, "hw": HW},   # virage rapide, 90° droite
	{"type": "droite", "longueur": 30, "hw": HW},
	{"type": "arc", "rayon": 14, "delta": 32768, "steps": 14, "hw": HW},   # épingle, 180° droite
	{"type": "droite", "longueur": 35, "hw": HW},
	{"type": "arc", "rayon": 32, "delta": -16384, "steps": 10, "hw": HW},  # grand virage de compensation, 90° gauche
	{"type": "droite", "longueur": 40, "hw": 3},   # zone de plots (approximation) : rétrécissement
	{"type": "droite", "longueur": 45, "hw": HW},  # retour à la largeur normale
	{"type": "arc", "rayon": 20, "delta": 16384, "steps": 8, "hw": HW},    # chicane, 90° droite
	{"type": "arc", "rayon": 20, "delta": -16384, "steps": 8, "hw": HW},   # chicane, 90° gauche
	{"type": "droite", "longueur": 25, "hw": HW},
]

func _build_half(track: Track, x0: int, z0: int, h0: int) -> PackedInt64Array:
	var x: int = x0
	var z: int = z0
	var h: int = h0
	var st: PackedInt64Array
	for entree in PROGRAMME_MOITIE:
		if entree["type"] == "droite":
			st = TrackBuilder.ajouter_droite(track, x, z, h, entree["longueur"], entree["hw"], 0)
		else:
			st = TrackBuilder.ajouter_arc(track, x, z, h, entree["rayon"], entree["delta"], entree["hw"], 0, entree["steps"])
		x = st[0]; z = st[1]; h = int(st[2])
	return PackedInt64Array([x, z, h])

func _somme_angles_moitie() -> int:
	var somme: int = 0
	for entree in PROGRAMME_MOITIE:
		if entree["type"] == "arc":
			somme += entree["delta"]
	return somme

func _longueur_droites_m() -> int:
	var somme: int = 0
	for entree in PROGRAMME_MOITIE:
		if entree["type"] == "droite":
			somme += entree["longueur"]
	return somme

# Longueur d'arc = rayon × angle_radians — calcul en float, UNIQUEMENT pour
# l'affichage (Fixed.to_float est explicitement réservé au rendu/debug ;
# n'influence aucune trajectoire ni aucun chrono).
func _longueur_arcs_m() -> float:
	var somme: float = 0.0
	for entree in PROGRAMME_MOITIE:
		if entree["type"] == "arc":
			var angle_rad: float = abs(entree["delta"]) * TAU / 65536.0
			somme += float(entree["rayon"]) * angle_rad
	return somme

func _build_reference_track() -> Track:
	var track := Track.new()
	track.add_point(0, 0, 0, Fixed.from_int(HW))  # P0 — ligne de départ/arrivée

	var somme: int = _somme_angles_moitie()
	assert(somme == 32768, "bench_equilibrage: la moitié A doit tourner de 180° pile (obtenu %d)" % somme)

	var apres_a: PackedInt64Array = _build_half(track, 0, 0, 0)
	var apres_b: PackedInt64Array = _build_half(track, apres_a[0], apres_a[1], int(apres_a[2]))

	var cap_final: int = int(apres_b[2]) & (FixedMath.FULL_TURN - 1)
	print("Fermeture de la boucle par symétrie centrale : erreur (%.3f, %.3f) m, cap final %d (attendu 0)" % [Fixed.to_float(apres_b[0]), Fixed.to_float(apres_b[1]), cap_final])

	_verifier_proximite_segments(track)
	return track

# Contrôle grossier (hors boucle de tick, donc autorisé) : deux points non
# adjacents trop proches indiquent un risque de croisement de segments —
# piège documenté en tête de map/track_hardcoded.gd (closest_point() peut
# alors accrocher le mauvais segment et éjecter la voiture).
func _verifier_proximite_segments(track: Track) -> void:
	var n: int = track.point_count()
	var seuil: int = Fixed.from_int(2 * HW)
	var seuil_sq: int = Fixed.mul(seuil, seuil)
	for i in range(n):
		for k in range(i + 2, n):
			if i == 0 and k == n - 1:
				continue  # adjacents par la boucle
			var dx: int = track.point_x[k] - track.point_x[i]
			var dz: int = track.point_z[k] - track.point_z[i]
			var d_sq: int = Fixed.mul(dx, dx) + Fixed.mul(dz, dz)
			if d_sq < seuil_sq:
				print("AVERTISSEMENT : points %d et %d à moins de %.1f m l'un de l'autre — risque de croisement de segments" % [i, k, Fixed.to_float(seuil)])

func _mesurer(vehicule_id: String, track: Track, utiliser_glisse: bool) -> Dictionary:
	var config: CarConfig = CarConfig.charger(vehicule_id)
	var world := World.new()
	world.setup(track, config, 0, 0, 0, 0)
	var pilote := BenchPilote.new(track, config, utiliser_glisse)
	var input := InputFrame.new()

	for i in range(LIMITE_TICKS):
		pilote.calculer(world.car_state, input)
		world.tick(input)
		if world.race_state.finished or world.race_state.timed_out:
			break

	return {"chrono": world.race_state.finish_ms, "termine": world.race_state.finished}

# "Optimal" sans joueur humain = le meilleur des deux politiques (voir
# tools/bench_pilote.gd) — définition opérationnelle retenue pour ce lot.
func _meilleur_chrono(vehicule_id: String, track: Track) -> Dictionary:
	var r_adh: Dictionary = _mesurer(vehicule_id, track, false)
	var r_gli: Dictionary = _mesurer(vehicule_id, track, true)
	var adh_gagne: bool = r_adh["termine"] and (not r_gli["termine"] or r_adh["chrono"] <= r_gli["chrono"])
	if adh_gagne:
		return {"chrono": r_adh["chrono"], "politique": "adherence"}
	elif r_gli["termine"]:
		return {"chrono": r_gli["chrono"], "politique": "glisse"}
	return {"chrono": -1, "politique": "AUCUNE (n'a pas terminé)"}

func _initialize() -> void:
	var track: Track = _build_reference_track()

	var longueur_droites: int = _longueur_droites_m()
	var longueur_arcs: float = _longueur_arcs_m()
	var longueur_totale: float = float(longueur_droites) * 2.0 + longueur_arcs * 2.0
	var fraction_droite: float = float(longueur_droites) * 2.0 / longueur_totale * 100.0

	print("")
	print("Piste de référence : %.0f m, %.0f%% de ligne droite, un tour" % [longueur_totale, fraction_droite])
	print("Non simulé sur cette piste : rampes (altitude sans effet sur le chrono, cf. sim/car_sim.gd),")
	print("plots (approximés par un rétrécissement de piste, pas un vrai obstacle), route dégradée (absente).")
	print("")

	var ids: PackedStringArray = ["gt", "formula", "superbike", "street_bike", "hover"]
	var noms: Dictionary = {"gt": "Roadster", "formula": "Needle", "superbike": "Ironside", "street_bike": "Wasp", "hover": "Halcyon"}
	var chronos: Array[float] = []

	print("Véhicule     Chrono        Politique   Vit. moyenne")
	for id in ids:
		var resultat: Dictionary = _meilleur_chrono(id, track)
		var nom: String = noms[id]
		if resultat["chrono"] < 0:
			print("%-12s AUCUN CHRONO (n'a pas terminé en %d ticks)" % [nom, LIMITE_TICKS])
			continue
		var chrono_ms: int = resultat["chrono"]
		var chrono_s: float = float(chrono_ms) / 1000.0
		chronos.append(chrono_s)
		var vitesse_moy_kmh: float = (longueur_totale / chrono_s) * 3.6
		print("%-12s %-13s %-11s %.1f km/h" % [nom, TimeFormat.format_ms(chrono_ms), resultat["politique"], vitesse_moy_kmh])

	if chronos.size() == 0:
		print("")
		print("Aucun véhicule n'a terminé — impossible de calculer un écart.")
		quit(0)
		return

	var somme: float = 0.0
	for c in chronos:
		somme += c
	var moyenne: float = somme / chronos.size()

	var somme_sq_ecarts: float = 0.0
	var mini: float = chronos[0]
	var maxi: float = chronos[0]
	for c in chronos:
		somme_sq_ecarts += (c - moyenne) * (c - moyenne)
		mini = minf(mini, c)
		maxi = maxf(maxi, c)
	var ecart_type: float = sqrt(somme_sq_ecarts / chronos.size())
	var amplitude: float = maxi - mini

	print("")
	print("Moyenne %.3f s   écart-type %.3f s (%.1f%%)   amplitude %.3f s (%.1f%%)" % [
		moyenne, ecart_type, ecart_type / moyenne * 100.0, amplitude, amplitude / moyenne * 100.0
	])
	quit(0)
