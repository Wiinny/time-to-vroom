# Needle (id "formula", référence Trackmania) — exécution pure : inertie
# quasi nulle, réponse instantanée, adhérence maximale. Ne peut pas
# s'incliner brusquement (vitesse_braquage très haute mais rayon de virage
# serré impossible à négocier vite) : pour un virage serré, il FAUT ralentir.
# Pas de glisse (AUCUNE) : dépasser l'adhérence produit un sous-virage avec
# perte de vitesse (voir sim/car_sim.gd, arbitrage 2), jamais un dérapage.
# Voir Paramétrage-Véhicules.md.
class_name CarConfigFormula
extends CarConfig

func _init() -> void:
	vitesse_max_kmh = 185.0
	palier_accel_kmh = 185.0  # courbe linéaire : accel_basse == accel_haute, pas de vrai palier
	accel_basse_ms2 = 7.5
	accel_haute_ms2 = 7.5
	# freinage_ms2 STRICTEMENT supérieur à decel_naturelle_ms2 : la poussée du
	# frein (étape 8 de sim/car_sim.gd) et la résistance naturelle qui
	# s'applique dans le MÊME tick (decel_naturelle, freinage relâché) sont
	# tous les deux appliqués sans jamais accumuler d'un tick à l'autre si
	# leurs magnitudes sont égales — les deux poussées s'annulent pile à zéro
	# à chaque tick. Avec 8.0/8.0 (bug réel rencontré, confirmé par script
	# jetable), Needle restait figé à vitesse exactement nulle sous frein
	# seul, incapable de passer en marche arrière — les 4 autres véhicules
	# ont tous un écart net entre ces deux valeurs (ex. Roadster 18/12) et
	# n'ont jamais ce problème. 10.0 garde Needle sous Superbike (12.0),
	# cohérent avec ses valeurs plus légères que les autres véhicules à
	# moteur ; ajustable à la manette si le retour au freinage ne convient pas.
	freinage_ms2 = 10.0
	decel_naturelle_ms2 = 8.0

	angle_braquage_max_deg = 30.0
	vitesse_braquage_deg_s = 400.0
	adherence_laterale_ms2 = 36.0  # ×1,8 depuis 20.0 (voir CLAUDE.md, chantier d'équilibrage adhérence)
	controle_aerien = 0.90

	type_glisse = TypeGlisse.AUCUNE
	perte_vitesse_glisse_pct_s = 0.0
