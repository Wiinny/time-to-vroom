# Halcyon (id "hover", référence F-Zero) — l'anticipation : vitesse la plus
# élevée, mais elle se mérite. decel_naturelle à 0,5 est la ligne la plus
# importante de cette fiche : lever le pied ne fait presque rien, freiner
# non plus, toute la vitesse acquise reste — la seule façon de négocier un
# virage est de l'avoir préparé. Glisse PERMANENTE : pas de déclenchement ni
# de sortie, le vaisseau dérive en continu, braquer ne fait qu'infléchir une
# trajectoire qui suit toujours son inertie (voir sim/car_sim.gd, arbitrage
# 4 : le drain de perte_vitesse_glisse est proportionnel à la saturation du
# travers, donc nul en ligne droite malgré la glisse "permanente"). Seul
# véhicule à subir une déstabilisation après boost — assaisonnement, pas une
# punition, il reste pilotable. Voir Paramétrage-Véhicules.md.
class_name CarConfigHover
extends CarConfig

func _init() -> void:
	vitesse_max_kmh = 195.0
	palier_accel_kmh = 195.0  # courbe linéaire
	accel_basse_ms2 = 4.0
	accel_haute_ms2 = 4.0
	freinage_ms2 = 3.0
	decel_naturelle_ms2 = 0.5

	angle_braquage_max_deg = 26.0
	vitesse_braquage_deg_s = 70.0
	adherence_laterale_ms2 = 12.6  # ×1,8 depuis 7.0 (voir CLAUDE.md, chantier d'équilibrage adhérence)
	controle_aerien = 0.20

	type_glisse = TypeGlisse.PERMANENTE
	perte_vitesse_glisse_pct_s = 2.0

	boost_destab_duree_s = 0.8
	boost_destab_facteur = 0.35
