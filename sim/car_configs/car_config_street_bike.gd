# Wasp (id "street_bike", référence moto légère Mario Kart Wii) — la
# nervosité : légère, accélère fort partout, plafonne bas. Glisse SAUT_ARC :
# petit saut puis dérapage engagé à rayon largement fixe (rayon_glisse_m),
# le joueur doit viser le virage AVANT de déclencher — correction en cours
# de glisse très limitée. Le saut permet de franchir un obstacle au sol,
# mais ce bénéfice dépend d'éléments de piste non simulés (voir
# sim/car_sim.gd, en-tête « Blocages » du plan) : pour l'instant c'est un
# coût pur (cout_vitesse_saut_kmh). Voir Paramétrage-Véhicules.md — le
# cahier des charges interdit explicitement tout seuil du type
# « N sauts en M secondes » : le coût continu suffit.
class_name CarConfigStreetBike
extends CarConfig

func _init() -> void:
	vitesse_max_kmh = 175.0
	palier_accel_kmh = 175.0  # courbe linéaire
	accel_basse_ms2 = 13.5
	accel_haute_ms2 = 13.5
	freinage_ms2 = 18.0
	decel_naturelle_ms2 = 8.0

	angle_braquage_max_deg = 36.0
	vitesse_braquage_deg_s = 400.0
	adherence_laterale_ms2 = 23.4  # ×1,8 depuis 13.0 (voir CLAUDE.md, chantier d'équilibrage adhérence)
	controle_aerien = 0.85

	type_glisse = TypeGlisse.SAUT_ARC
	perte_vitesse_glisse_pct_s = 4.0
	rayon_glisse_m = 22.0

	hauteur_saut_m = 0.6
	duree_saut_s = 0.45
	cout_vitesse_saut_kmh = 8.0
