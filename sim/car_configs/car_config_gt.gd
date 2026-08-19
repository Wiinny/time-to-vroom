# Roadster (id "gt", référence Forza Horizon) — la référence : du poids, du
# transfert de charge, tolérant, bon partout sans jamais dominer. Glisse
# façon Forza (PIVOT_AVANT) : l'arrière décroche, la voiture pivote autour
# de son avant, corrigeable à tout moment. Voir Paramétrage-Véhicules.md.
class_name CarConfigGt
extends CarConfig

func _init() -> void:
	vitesse_max_kmh = 180.0
	palier_accel_kmh = 110.0
	accel_basse_ms2 = 11.0
	accel_haute_ms2 = 3.5
	freinage_ms2 = 18.0
	decel_naturelle_ms2 = 12.0  # relevé depuis 5.0 (retour utilisateur : le roulage libre accélérateur relâché donnait une sensation de glace, pas de route)

	angle_braquage_max_deg = 34.0
	vitesse_braquage_deg_s = 180.0
	adherence_laterale_ms2 = 25.2  # ×1,8 depuis 14.0 (voir CLAUDE.md, chantier d'équilibrage adhérence)
	controle_aerien = 0.50

	type_glisse = TypeGlisse.PIVOT_AVANT
	perte_vitesse_glisse_pct_s = 6.0
