# Ironside (id "superbike", référence Bécane Bowser, Mario Kart Wii) —
# l'engagement : lourde, braquage lent, adhérence élevée, ne glisse pas
# (AUCUNE, même sous-virage à seuil que Needle — voir sim/car_sim.gd,
# arbitrage 2). Le geste est l'anticipation du point d'entrée : la
# vitesse_braquage très basse est le cœur de son identité — ce n'est pas
# qu'elle tourne peu, c'est qu'elle met du temps à COMMENCER à tourner.
# Voir Paramétrage-Véhicules.md.
class_name CarConfigSuperbike
extends CarConfig

func _init() -> void:
	vitesse_max_kmh = 185.0
	palier_accel_kmh = 120.0
	accel_basse_ms2 = 11.5
	accel_haute_ms2 = 3.0
	freinage_ms2 = 12.0
	decel_naturelle_ms2 = 5.0

	angle_braquage_max_deg = 32.0
	vitesse_braquage_deg_s = 110.0
	adherence_laterale_ms2 = 30.6  # ×1,8 depuis 17.0 (voir CLAUDE.md, chantier d'équilibrage adhérence)
	controle_aerien = 0.25

	type_glisse = TypeGlisse.AUCUNE
	perte_vitesse_glisse_pct_s = 0.0
