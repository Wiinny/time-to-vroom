# Instrument de mesure (pas un test qui échoue) : pour chaque véhicule,
# mesure le temps de passage d'un virage isolé de rayon croissant (10 à
# 60 m, pas de 5 m) et identifie le rayon où la glisse cesse d'être plus
# rapide que l'adhérence pure — le curseur d'équilibrage principal du jeu
# (cible du cahier des charges : ~28 m). Voir Paramétrage-Véhicules.md.
#   "$GODOT" --headless --path . --script res://tools/bench_rayon.gd
extends SceneTree

const HW: int = 5
const RAYONS: PackedInt32Array = [10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60]
const VITESSE_ENTREE_KMH: float = 140.0  # imposée, identique pour tous : isole le latéral pur (voir plus bas)
const LIMITE_TICKS: int = 5000
const ARC_STEPS: int = 10

# Piste OUVERTE (Track.est_ferme = false) : droite d'approche 150 m + arc
# 90° de rayon `rayon_m` + droite de sortie 60 m. Ouverte, pas une boucle
# compacte — sinon le segment de fermeture traverserait le virage et
# closest_point() y accrocherait la voiture (piège documenté en tête de
# map/track_hardcoded.gd, sur un tracé ouvert ce serait pire encore).
# Approche volontairement longue : à vitesse d'entrée imposée (140 km/h) le
# pilote freine de façon réactive (tools/bench_pilote.gd, pas de prédiction
# de distance de freinage) — une approche courte ne laisse pas le temps de
# ralentir avant le virage, quel que soit son rayon.
func _build_piste_virage(rayon_m: int) -> Dictionary:
	var track := Track.new()
	track.est_ferme = false
	track.add_point(0, 0, 0, Fixed.from_int(HW))

	var st: PackedInt64Array = TrackBuilder.ajouter_droite(track, 0, 0, 0, 150, HW, 0)
	var x: int = st[0]
	var z: int = st[1]
	var h: int = int(st[2])

	var i0: int = track.point_count() - 1  # dernier point de la droite d'approche
	st = TrackBuilder.ajouter_arc(track, x, z, h, rayon_m, 16384, HW, 0, ARC_STEPS)
	x = st[0]; z = st[1]; h = int(st[2])
	var i1: int = track.point_count() - 1  # dernier point de l'arc

	# Deux segments de sortie (pas un seul de 60 m) : sur une piste ouverte,
	# le DERNIER point ajouté ne crée aucun segment après lui — avec un seul
	# point de sortie, i1 serait donc l'index du tout dernier segment de
	# toute la piste, et « seg > i1 » ne deviendrait jamais vrai (bug réel
	# rencontré : la mesure ne se terminait jamais, même après avoir
	# visiblement quitté le virage). Deux segments garantissent qu'il existe
	# bien un segment i1+1 à dépasser une fois le virage franchi.
	st = TrackBuilder.ajouter_droite(track, x, z, h, 30, HW, 0)
	x = st[0]; z = st[1]; h = int(st[2])
	TrackBuilder.ajouter_droite(track, x, z, h, 30, HW, 0)
	return {"track": track, "i0": i0, "i1": i1}

# Chrono = premier tick où segment_index >= i0 (entrée dans le virage) ->
# premier tick où segment_index > i1 (sortie du virage). Pas RaceState :
# sa porte est conçue pour un tour fermé avec sémantique de ligne de départ
# (seuil de distance, sens de franchissement), inadaptée à un tronçon ouvert.
# `sortie` = vrai si la voiture a raclé le bord (>90% de la demi-largeur)
# plus de la moitié du temps passé dans le virage — un chrono obtenu en
# raclant la barrière ne mesure pas la tenue de route.
func _mesurer(vehicule_id: String, piste: Dictionary, utiliser_glisse: bool) -> Dictionary:
	var track: Track = piste["track"]
	var i0: int = piste["i0"]
	var i1: int = piste["i1"]

	var config: CarConfig = CarConfig.charger(vehicule_id)
	var world := World.new()
	world.setup(track, config, 0, 0, 0, 0)
	world.car_state.vit_z = Fixed.from_float(VITESSE_ENTREE_KMH / 3.6 / float(Horloge.TICKS_PAR_SECONDE))  # vitesse d'entrée imposée

	var pilote := BenchPilote.new(track, config, utiliser_glisse)
	var input := InputFrame.new()
	var query := TrackQueryResult.new()
	var seuil_bord: int = Fixed.mul(Fixed.from_int(HW), Fixed.from_float(0.9))

	var tick_debut: int = -1
	var tick_fin: int = -1
	var ticks_sur_arc: int = 0
	var ticks_au_bord: int = 0

	for i in range(LIMITE_TICKS):
		pilote.calculer(world.car_state, input)
		world.tick(input)
		track.closest_point(world.car_state.pos_x, world.car_state.pos_z, query)
		var seg: int = query.segment_index

		if tick_debut < 0 and seg >= i0:
			tick_debut = i
		if tick_debut >= 0 and tick_fin < 0 and seg > i1:
			tick_fin = i
			break
		if tick_debut >= 0 and tick_fin < 0:
			ticks_sur_arc += 1
			if Fixed.abs(query.lateral_offset) > seuil_bord:
				ticks_au_bord += 1

	if tick_fin < 0:
		return {"chrono": -1}
	var sortie: bool = ticks_sur_arc > 0 and ticks_au_bord * 2 > ticks_sur_arc
	return {"chrono": tick_fin - tick_debut, "sortie": sortie}

func _meilleur(vehicule_id: String, piste: Dictionary) -> Dictionary:
	var r_adh: Dictionary = _mesurer(vehicule_id, piste, false)
	var r_gli: Dictionary = _mesurer(vehicule_id, piste, true)
	var adh_valide: bool = r_adh["chrono"] >= 0
	var gli_valide: bool = r_gli["chrono"] >= 0
	if adh_valide and (not gli_valide or r_adh["chrono"] <= r_gli["chrono"]):
		return {"chrono": r_adh["chrono"], "politique": "a", "sortie": r_adh.get("sortie", false)}
	elif gli_valide:
		return {"chrono": r_gli["chrono"], "politique": "g", "sortie": r_gli.get("sortie", false)}
	return {"chrono": -1, "politique": "", "sortie": false}

func _initialize() -> void:
	var ids: PackedStringArray = ["gt", "formula", "superbike", "street_bike", "hover"]
	var noms: Dictionary = {"gt": "Roadster", "formula": "Needle", "superbike": "Ironside", "street_bike": "Wasp", "hover": "Halcyon"}

	print("Vitesse d'entrée imposée : %.0f km/h — temps de passage du virage, en ticks" % VITESSE_ENTREE_KMH)
	print("(a) = politique adhérence gagnante, (g) = politique glisse gagnante, * = a raclé le bord plus de la moitié du virage")
	print("")

	var entete: String = "%-10s" % "Véhicule"
	for r in RAYONS:
		entete += "%8s" % ("R=%d" % r)
	print(entete)

	var resultats: Dictionary = {}  # id -> Array[Dictionary], un par rayon
	for id in ids:
		var ligne_resultats: Array = []
		var ligne: String = "%-10s" % noms[id]
		for r in RAYONS:
			var piste: Dictionary = _build_piste_virage(r)
			var res: Dictionary = _meilleur(id, piste)
			ligne_resultats.append(res)
			if res["chrono"] < 0:
				ligne += "%8s" % "-"
			else:
				var marque: String = res["politique"]
				if res.get("sortie", false):
					marque += "*"
				ligne += "%8s" % ("%d%s" % [res["chrono"], marque])
		resultats[id] = ligne_resultats
		print(ligne)

	print("")
	print("Point de bascule glisse/adhérence (cible ≈ 28 m) — levier de réglage : perte_vitesse_glisse")
	print("par véhicule, et ReglesCommunes.coef_glisse globalement (sans lui, aucune bascule n'existe) :")
	for id in ids:
		var liste: Array = resultats[id]
		var dernier_glisse: int = -1
		for i in range(liste.size()):
			var res: Dictionary = liste[i]
			if res["chrono"] >= 0 and res["politique"] == "g":
				dernier_glisse = i
		if dernier_glisse < 0:
			print("  %s : sans objet (la glisse ne gagne jamais sur la plage testée)" % noms[id])
		elif dernier_glisse + 1 >= RAYONS.size():
			print("  %s : la glisse gagne sur toute la plage testée (jusqu'à %d m)" % [noms[id], RAYONS[dernier_glisse]])
		else:
			print("  %s : entre %d et %d m" % [noms[id], RAYONS[dernier_glisse], RAYONS[dernier_glisse + 1]])

	quit(0)
