# Modèle de conduite. Toutes les grandeurs sont Q16.16 sauf mention
# contraire (les angles — yaw, angle_roues, angle_braquage_max — sont des
# unités d'angle BRUTES, PAS du Q16.16 : 65536 = un tour complet, voir
# core/fixed_math.gd et CarState.yaw). Voir core/fixed.gd pour les
# conventions mul()/div(), et sim/regles_communes.gd pour les constantes
# partagées entre véhicules.
#
# Convention d'orientation (inchangée) : yaw = 0 -> la voiture regarde vers
# +Z ; un braquage positif tourne vers +X (sens horaire vu de dessus).
#
# --- Arbitrages documentés (cahier des charges Paramétrage-Véhicules.md,
# qui autorise explicitement ce genre de décision documentée) ---
#
# 1. Modèle bicyclette petit-angle : Δψ = v · angle_roues / EMPATTEMENT.
#    Aucun empattement n'est fourni par le cahier des charges (EMPATTEMENT_M
#    = 2,5 m, partagé, dans regles_communes.gd) ; pas de tan() dans
#    FixedMath, l'approximation linéaire a ~12% d'erreur au braquage max,
#    monotone donc sans effet de bord.
# 2. Sous-virage (AUCUNE) : la vitesse latérale non corrigée par le budget
#    d'adhérence (au-delà du seuil adherence_laterale) draine une fraction
#    de la vitesse longitudinale ("scrub"), formule dérivée des champs
#    existants (aucun champ dédié dans le cahier des charges) :
#    scrub = min(excédent, adherence) × ReglesCommunes.coef_scrub.
#    Auto-limitée (jamais plus que la limite d'adhérence elle-même) et
#    auto-convergente (la demande chute en v² à mesure que la voiture
#    ralentit -> converge vers v = √(adherence·rayon), la vitesse de
#    passage limite du véhicule).
# 3. Rien dans le modèle ne rend nativement la glisse plus rapide que
#    l'adhérence : ReglesCommunes.coef_glisse (1,8) multiplie le budget
#    latéral en PIVOT_AVANT pendant une glisse activement engagée — sans
#    lui, aucun point de bascule glisse/adhérence n'existe (cible ~28 m,
#    cf. cahier des charges). PIVOT_AVANT a en plus un plancher permanent,
#    coef_glisse_passif (1,5 < 1,8, voir regles_communes.gd), actif même
#    SANS glisse engagée : retour utilisateur, sans lui la conduite
#    "normale" du Roadster tombait au même plafond strict que Needle/
#    Ironside mais sans leur filet de vitesse ("scrub", arbitrage 2),
#    ressenti comme une ligne droite forcée. Le plancher reste
#    délibérément sous coef_glisse pour que la glisse active conserve un
#    avantage net — sinon le bouton dérapage perdrait son intérêt
#    exactement dans la situation qui posait problème.
# 4. Drain de perte_vitesse_glisse proportionnel à la SATURATION du travers
#    (|lateral_speed|/budget), jamais un drain plat : un drain plat dès
#    qu'une glisse est "active" contredirait Halcyon (PERMANENTE n'a jamais
#    de sortie de glisse, donc perdrait de la vitesse même en ligne droite,
#    contre sa fiche explicite "toute la vitesse acquise reste").
# 5. SAUT_ARC ignore le budget d'adhérence pendant la phase ARC (manœuvre
#    scriptée, façon Mario Kart Wii) et est considéré comme pleinement
#    "saturé" (perte_vitesse_glisse s'applique à taux plein durant l'arc) —
#    c'est le seul moment où ce véhicule glisse, la fiche décrit
#    explicitement une perte de vitesse pendant l'arc.
# 6. Courbe d'accélération à palier : une RAMPE (lerp accel_basse->haute
#    entre 0 et palier_accel), pas une marche à discontinuité — "en cas de
#    doute, la référence la plus proche" (Roadster/Forza = couple
#    progressif), et compatible avec les fiches "courbe linéaire"
#    (accel_basse == accel_haute -> lerp constant).
# 7. Bouton d'engagement : la touche "dérapage" existante (maintenue = glisse
#    continue PIVOT_AVANT/PERMANENTE, front montant = déclenche le saut de
#    SAUT_ARC). Aucun champ ajouté à InputFrame -> le futur format de replay
#    n'est pas affecté par ce lot.
# 8. Écrêtage des murs inchangé (fin de fonction) : un grand arc SAUT_ARC
#    sur une piste étroite s'y fait écrêter brutalement. Assumé — Wasp est
#    "le véhicule le plus difficile à placer, et c'est voulu" ; une sortie
#    d'arc automatique au contact du mur serait une règle cachée de plus,
#    non déductible par le joueur.
# 9. Conséquence du modèle bicyclette : Δψ ∝ v, donc la voiture NE TOURNE
#    PLUS À L'ARRÊT (elle tournait à taux constant auparavant). Nécessaire
#    au modèle, pas une règle ajoutée délibérément — à valider manette en
#    main, en particulier pour la manœuvre de récupération après un
#    tête-à-queue ou contre un mur.
# 10. ReglesCommunes.coef_braquage_glisse (0,35) ralentit la convergence de
#     angle_roues pendant une glisse activement engagée (PIVOT) — retour
#     utilisateur : une glisse doit rester difficile à rediriger une fois
#     lancée, façon vraie voiture de drift (mais plus simple à contrôler).
#     Sans lui, angle_roues suivait le stick à pleine vitesse_braquage même
#     en glisse ; avec un budget d'adhérence élargi (coef_glisse/coef_
#     glisse_passif) qui écrête beaucoup moins qu'avant, ça se traduisait
#     par une rotation quasi instantanée au moindre mouvement de manette.
#
# --- Éléments de piste (Lot A, sim/element_effects.gd — voir CLAUDE.md,
# section « Éléments de piste » pour la matrice Lot A/Lot B complète) ---
#
# 11. Rayon de détection FIXE par type d'élément, pas une vraie zone à
#     longueur (TrackData ne stocke qu'un point par élément, pas de taille).
#     Approximation assumée : pour couvrir un tronçon, le créateur aligne
#     plusieurs marqueurs. Le vrai correctif (un champ "rayon" optionnel sur
#     l'élément) est un changement de format à part, pas traité ici.
# 12. Plusieurs zones qui se chevauchent ne s'additionnent JAMAIS : le
#     coefficient d'autorité le plus bas gagne (min), le bonus de grip le
#     plus haut gagne (max) — jamais un produit ou une somme, sinon aligner
#     deux marqueurs pour couvrir un virage un peu long créerait un arrêt
#     instantané accidentel. Les déclenchements ponctuels (boost, rampe,
#     plot, mortel/vide) se cumulent normalement s'ils sont déclenchés à des
#     instants différents — c'est un choix du créateur de piste, pas un bug.
# 13. route_aimantee est ADDITIF (budget += bonus fixe), jamais un
#     multiplicateur — même logique que la règle du boost ("poussée absolue
#     ... jamais un pourcentage") : un multiplicateur avantagerait qui a
#     déjà le plus d'adhérence, un bonus fixe est au contraire un
#     égalisateur (proportionnellement bien plus fort pour Halcyon que pour
#     Needle). Appliqué APRÈS le multiplicateur de glisse (étape 4) pour ne
#     pas doubler la mise pendant un drift, et AVANT le budget=0 en l'air
#     (un aimant ne fonctionne pas à mi-saut).
# 14. obstacle_mortel/vide sont un repli EXPLICITE (arrêt net + verrou de
#     direction temporaire), PAS une mort/réapparition : le roadmap de
#     CLAUDE.md liste encore "repop" comme non construit. Remplacer par un
#     vrai repop plus tard ne touche qu'un point d'appel
#     (CarSim.appliquer_penalite()), pas le mécanisme de détection.
class_name CarSim

static func tick(state: CarState, input: InputFrame, track: Track, config: CarConfig, query: TrackQueryResult) -> void:
	# En tout premier : un boost/une pénalité déclenché ce tick doit se
	# refléter dans tout le reste du calcul (v à l'étape suivante, le budget
	# à l'étape 4, etc.). Lit state.pos_x/pos_z tels qu'ils étaient à la FIN
	# du tick précédent — une latence uniforme d'un tick (10 ms), acceptable
	# et cohérente avec le reste du pipeline en simple passe.
	_appliquer_elements(state, track, config)

	var v: int = FixedMath.length_2d(state.vit_x, state.vit_z)
	var cout_saut_a_appliquer: int = 0

	# --- 1. Transitions de glisse ---
	var front_derapage: bool = input.derapage > 0 and not state.derapage_precedent
	if config.type_glisse == CarConfig.TypeGlisse.SAUT_ARC:
		if front_derapage and state.au_sol and state.glisse_etat == CarState.GlisseEtat.LIBRE:
			state.glisse_etat = CarState.GlisseEtat.SAUT
			state.glisse_sens = Fixed.sign(input.braquage) if Fixed.abs(input.braquage) > ReglesCommunes.SEUIL_BRAQUAGE_GLISSE else 0
			state.saut_ticks = config.saut_duree_ticks
			state.vit_y = config.saut_vitesse_initiale
			state.saut_gravite_courante = config.saut_gravite
			state.au_sol = false
			cout_saut_a_appliquer = config.cout_vitesse_saut
	elif config.type_glisse == CarConfig.TypeGlisse.PIVOT_AVANT:
		var braquage_engage: bool = input.derapage > 0 and Fixed.abs(input.braquage) > ReglesCommunes.SEUIL_BRAQUAGE_GLISSE
		state.glisse_etat = CarState.GlisseEtat.PIVOT if braquage_engage else CarState.GlisseEtat.LIBRE
	# AUCUNE / PERMANENTE : glisse_etat reste LIBRE en permanence.

	# --- 2. Angle de roues — convergence progressive, découplée de la rotation du yaw ---
	var autorite: int = Fixed.ONE
	if not state.au_sol:
		autorite = Fixed.mul(autorite, config.controle_aerien_coef)
	if state.boost_destab_ticks > 0:
		autorite = Fixed.mul(autorite, config.boost_destab_facteur_coef)
	# Éléments de piste : gardé (!= ONE / > 0) pour que le chemin sans
	# élément proche reste un `mul()` par ONE évité, pas juste neutre —
	# preuve supplémentaire que ce lot est inerte piste sans éléments.
	if state.elem_coef_autorite != Fixed.ONE:
		autorite = Fixed.mul(autorite, state.elem_coef_autorite)
	if state.controle_perdu_ticks > 0:
		autorite = Fixed.mul(autorite, ElementEffects.mortel_autorite)
	var cible_angle: int = Fixed.mul(Fixed.mul(config.angle_braquage_max, input.braquage), autorite)
	var vitesse_braquage_effective: int = config.vitesse_braquage
	if state.glisse_etat == CarState.GlisseEtat.PIVOT:
		vitesse_braquage_effective = Fixed.mul(vitesse_braquage_effective, ReglesCommunes.coef_braquage_glisse)
	state.angle_roues = _move_toward(state.angle_roues, cible_angle, vitesse_braquage_effective)

	# --- 3. Intensité de glisse (PIVOT_AVANT — modulable par direction + accélérateur) ---
	var cible_intensite: int = 0
	if state.glisse_etat == CarState.GlisseEtat.PIVOT:
		cible_intensite = Fixed.mul(input.braquage, Fixed.HALF + Fixed.mul(Fixed.HALF, input.accel))
	state.glisse_intensite = _move_toward(state.glisse_intensite, cible_intensite, ReglesCommunes.TAUX_GLISSE_PAR_TICK)
	if state.glisse_etat == CarState.GlisseEtat.ARC:
		state.glisse_intensite = state.glisse_sens * Fixed.ONE  # verrouillé, pas de convergence

	# --- 4. Demande de rotation Δψ ---
	var dpsi: int
	var budget: int = 0
	var budget_illimite: bool = false
	if state.glisse_etat == CarState.GlisseEtat.ARC:
		# input.braquage (Q16.16) × glisse_sens (-1/0/1 entier simple) : `*`
		# normal, jamais mul() — glisse_sens n'est pas une grandeur Q16.16
		# (même règle que Fixed.sign, cf. core/fixed.gd).
		var rayon_mod: int = Fixed.ONE - Fixed.mul(ReglesCommunes.correction_arc, input.braquage * state.glisse_sens)
		rayon_mod = Fixed.max(rayon_mod, Fixed.ONE / 4)  # garde : jamais de rayon quasi nul/négatif
		dpsi = state.glisse_sens * Fixed.div(Fixed.mul(v, config.arc_gain), rayon_mod)
		budget_illimite = true
	else:
		var angle_effectif: int = state.angle_roues
		if state.glisse_etat == CarState.GlisseEtat.PIVOT:
			angle_effectif += Fixed.mul(state.glisse_intensite, ReglesCommunes.angle_pivot_max)
		# mul(v, inv_empattement) est une grandeur Q16.16 GÉNÉRALE (pas une
		# fraction dans [-1,1]) : la multiplier par angle_effectif (unités
		# d'angle BRUTES, un entier simple potentiellement grand) doit passer
		# par `*` normal, pas mul() — sinon le résultat est divisé par 65536
		# de trop et le yaw ne tourne quasiment jamais (bug réel rencontré :
		# la voiture restait plaquée contre le premier mur, yaw figé à 0,
		# malgré un angle de roues proche du maximum).
		dpsi = Fixed.mul(v, ReglesCommunes.inv_empattement) * angle_effectif
		budget = config.adherence
		# Budget à DEUX niveaux pour PIVOT_AVANT (voir ReglesCommunes.
		# coef_glisse_passif) : glisse activement engagée -> coef_glisse
		# (1,8, le maximum) ; sinon -> coef_glisse_passif (1,5, un plancher
		# toujours meilleur que l'adhérence nue). Jamais le même niveau que
		# la glisse active, sinon la glisse ne tourne plus strictement plus
		# vite que la conduite normale dès que les deux dépassent leur
		# plafond respectif — exactement la situation qui posait problème
		# (voir _test_glisse_raccourcit) — et le bouton dérapage perd tout
		# intérêt. Le plancher, lui, évite que le Roadster retombe à un
		# plafond aussi strict que Needle/Ironside SANS leur filet de
		# vitesse ("scrub", arbitrage 2) — ce qui donnait l'impression d'un
		# mur en ligne droite forcée hors glisse.
		if state.glisse_etat == CarState.GlisseEtat.PIVOT:
			budget = Fixed.mul(budget, ReglesCommunes.coef_glisse)
		elif config.type_glisse == CarConfig.TypeGlisse.PIVOT_AVANT:
			budget = Fixed.mul(budget, ReglesCommunes.coef_glisse_passif)
		# route_aimantee : bonus ADDITIF (arbitrage 13), après le
		# multiplicateur de glisse ci-dessus, avant le budget=0 en l'air.
		budget += state.elem_bonus_grip
		if not state.au_sol:
			budget = 0

	# --- 5. Écrêtage par l'adhérence (garde div/0 à l'arrêt, cf. arbitrage 1) ---
	# dpsi_max dérive du budget COURANT (pas de config.adherence seul) : en
	# glisse, le budget est multiplié par coef_glisse, et cette même
	# multiplication doit s'appliquer à la courbure maximale pour que la
	# trajectoire se raccourcisse réellement (voir "Pourquoi le
	# raccourcissement est réel", pas seulement le drain/travers).
	var scrub: int = 0
	if not budget_illimite and v > ReglesCommunes.VITESSE_MIN_CAP:
		var budget_angulaire: int = Fixed.mul(budget, ReglesCommunes.rad_vers_brut)
		var dpsi_max: int = Fixed.div(budget_angulaire, v)
		if dpsi_max <= 0:
			dpsi = 0
		elif Fixed.abs(dpsi) > dpsi_max:
			if config.type_glisse == CarConfig.TypeGlisse.AUCUNE:
				var ratio_moins_un: int = Fixed.div(Fixed.abs(dpsi), dpsi_max) - Fixed.ONE
				scrub = Fixed.mul(Fixed.min(Fixed.mul(ratio_moins_un, budget), budget), ReglesCommunes.coef_scrub)
			dpsi = dpsi_max if dpsi > 0 else -dpsi_max

	# --- 6. Rotation du yaw — accumulateur fractionnaire, pas de biais gauche/droite ---
	state.yaw_frac += dpsi
	var entiers: int = state.yaw_frac >> 16
	state.yaw = (state.yaw + entiers) & (FixedMath.FULL_TURN - 1)
	state.yaw_frac -= entiers << 16

	# --- 7. Décomposition dans le NOUVEAU repère (après la rotation ci-dessus) ---
	var fwd_x: int = FixedMath.sin(state.yaw)
	var fwd_z: int = FixedMath.cos(state.yaw)
	var right_x: int = fwd_z
	var right_z: int = -fwd_x
	var forward_speed: int = Fixed.mul(state.vit_x, fwd_x) + Fixed.mul(state.vit_z, fwd_z)
	var lateral_speed: int = Fixed.mul(state.vit_x, right_x) + Fixed.mul(state.vit_z, right_z)

	# --- 8. Longitudinal ---
	var t: int = Fixed.clamp(Fixed.div(Fixed.abs(forward_speed), config.palier_accel), 0, Fixed.ONE)
	var accel_courbe: int = Fixed.lerp(config.accel_basse, config.accel_haute, t)
	forward_speed += Fixed.mul(accel_courbe, input.accel)
	forward_speed -= Fixed.mul(config.freinage, input.frein)

	# Saturation du travers : ARC est considéré pleinement engagé (seul
	# moment où ce véhicule glisse, cf. arbitrage 5) ; PIVOT/PERMANENTE
	# suivent le budget réel ; AUCUNE a perte_vitesse_glisse=0 dans toutes
	# les fiches, donc ce terme y est de toute façon sans effet.
	var saturation: int = 0
	if state.glisse_etat == CarState.GlisseEtat.ARC:
		saturation = Fixed.ONE
	elif not budget_illimite and budget > 0:
		saturation = Fixed.clamp(Fixed.div(Fixed.abs(lateral_speed), budget), 0, Fixed.ONE)

	var resist: int = Fixed.mul(config.decel_naturelle, Fixed.ONE - input.accel)
	resist += scrub
	resist += Fixed.mul(Fixed.mul(config.perte_glisse, saturation), Fixed.abs(forward_speed))
	# route_ralentit : plafond DOUX (voir sim/element_effects.gd) — une
	# résistance ne s'applique QU'AU-DESSUS du plafond de zone, jamais un
	# drain plat qui ferait caler certains véhicules à plein régime.
	if state.elem_plafond > 0 and Fixed.abs(forward_speed) > state.elem_plafond:
		resist += ElementEffects.ralentit_resistance

	if Fixed.abs(forward_speed) <= resist:
		forward_speed = 0
	else:
		forward_speed -= resist * Fixed.sign(forward_speed)
	forward_speed -= cout_saut_a_appliquer

	state.bonus_vitesse = Fixed.max(0, state.bonus_vitesse - ReglesCommunes.boost_decroissance)
	# Le plafond dur reste config.vitesse_max, JAMAIS abaissé à elem_plafond
	# ici : un clamp dur écrêterait la vitesse d'un coup dès le premier tick
	# d'entrée dans la zone (le "mur" que le plafond doux ci-dessus doit
	# justement éviter — bug réel rencontré : la résistance ci-dessus ne
	# faisait quasiment rien puisque ce clamp retombait instantanément sur
	# elem_plafond avant même qu'elle ait eu le temps d'agir). La
	# convergence vers le plafond de zone vient UNIQUEMENT de la résistance
	# ci-dessus, appliquée tick après tick — elle oscille en pratique tout
	# près du plafond (au-dessus -> résistance active -> repasse en dessous
	# -> résistance inactive -> l'accélération la fait remonter), jamais un
	# arrêt net.
	forward_speed = Fixed.clamp(forward_speed, -config.vitesse_max_marche_arriere, config.vitesse_max + state.bonus_vitesse)

	# --- 9. Latéral — budget de correction, PAS une fraction ---
	var lateral_cible: int = 0
	if state.glisse_etat == CarState.GlisseEtat.PIVOT:
		lateral_cible = -Fixed.mul(Fixed.mul(v, state.glisse_intensite), ReglesCommunes.tan_pivot_max)
	elif state.glisse_etat == CarState.GlisseEtat.ARC:
		lateral_cible = -state.glisse_sens * Fixed.mul(v, ReglesCommunes.tan_arc)

	var correction: int = lateral_speed - lateral_cible
	if not budget_illimite:
		correction = Fixed.clamp(correction, -budget, budget)
	lateral_speed -= correction

	# --- 10. Recomposition + vertical ---
	state.vit_x = Fixed.mul(forward_speed, fwd_x) + Fixed.mul(lateral_speed, right_x)
	state.vit_z = Fixed.mul(forward_speed, fwd_z) + Fixed.mul(lateral_speed, right_z)
	if not state.au_sol:
		# La gravité du saut EN COURS (Wasp SAUT_ARC ou une rampe), jamais
		# config.saut_gravite en dur : appliquer la gravité de Wasp à un
		# saut de rampe générique (ou l'inverse) donnerait un apex/une
		# durée faux (voir sim/car_state.gd::saut_gravite_courante).
		state.vit_y -= state.saut_gravite_courante

	# --- 11. Position ---
	state.pos_x += state.vit_x
	state.pos_z += state.vit_z
	state.pos_y += state.vit_y

	# --- 12. Requête piste ---
	track.closest_point(state.pos_x, state.pos_z, query)

	# --- 13. Résolution du sol (après la requête : hauteur du tick courant) ---
	if state.au_sol:
		state.pos_y = query.height
	else:
		state.saut_ticks -= 1
		if state.pos_y <= query.height or state.saut_ticks <= 0:
			state.pos_y = query.height
			state.vit_y = 0
			state.au_sol = true
			if state.glisse_etat == CarState.GlisseEtat.SAUT:
				var relance_arc: bool = input.derapage > 0 and state.glisse_sens != 0
				state.glisse_etat = CarState.GlisseEtat.ARC if relance_arc else CarState.GlisseEtat.LIBRE

	# --- 14. Murs — inchangé (cf. arbitrage 8) ---
	if Fixed.abs(query.lateral_offset) > query.half_width:
		var clamped: int = Fixed.clamp(query.lateral_offset, -query.half_width, query.half_width)
		state.pos_x = query.closest_x + Fixed.mul(query.right_x, clamped)
		state.pos_z = query.closest_z + Fixed.mul(query.right_z, clamped)

		var post_forward: int = Fixed.mul(state.vit_x, fwd_x) + Fixed.mul(state.vit_z, fwd_z)
		state.vit_x = Fixed.mul(post_forward, fwd_x)
		state.vit_z = Fixed.mul(post_forward, fwd_z)

	# --- 15. Timers ---
	if state.boost_destab_ticks > 0:
		state.boost_destab_ticks -= 1
	if state.controle_perdu_ticks > 0:
		state.controle_perdu_ticks -= 1
	state.derapage_precedent = input.derapage > 0

# Fait converger `current` vers `target` par pas d'au plus `max_delta`
# (toujours positif) — Fixed ne fournit pas de move_toward entier.
static func _move_toward(current: int, target: int, max_delta: int) -> int:
	if current < target:
		return Fixed.min(current + max_delta, target)
	elif current > target:
		return Fixed.max(current - max_delta, target)
	return current

# Déclenche un boost : poussée absolue dans la direction de la TRAJECTOIRE
# (pas de l'orientation — prendre un boost en dérapage projette donc vers
# l'extérieur, conséquence assumée par le cahier des charges), décroissance
# à taux fixe (voir ReglesCommunes.boost_decroissance, JAMAIS indexée sur
# decel_naturelle), déstabilisation temporaire de l'autorité de direction
# (via l'angle CIBLE des roues, pas la vitesse de convergence — le véhicule
# garde de l'autorité, cf. étape 2 ci-dessus).
#
# Appelée par _appliquer_elements() à l'entrée dans un élément "boost" de
# piste (Lot A, voir CLAUDE.md « Éléments de piste ») — la transmission des
# éléments de map/track_data.gd vers sim/ existe désormais (Track.elem_*).
static func declencher_boost(state: CarState, config: CarConfig) -> void:
	var v: int = FixedMath.length_2d(state.vit_x, state.vit_z)
	var dir_x: int
	var dir_z: int
	if v > ReglesCommunes.VITESSE_MIN_CAP:
		dir_x = Fixed.div(state.vit_x, v)
		dir_z = Fixed.div(state.vit_z, v)
	else:
		# À l'arrêt il n'y a pas de trajectoire à suivre : repli sur l'orientation.
		dir_x = FixedMath.sin(state.yaw)
		dir_z = FixedMath.cos(state.yaw)
	state.vit_x += Fixed.mul(ReglesCommunes.boost_poussee, dir_x)
	state.vit_z += Fixed.mul(ReglesCommunes.boost_poussee, dir_z)
	var nouvelle_vitesse: int = FixedMath.length_2d(state.vit_x, state.vit_z)
	state.bonus_vitesse = Fixed.max(0, nouvelle_vitesse - config.vitesse_max)
	if config.boost_destab_ticks > 0:
		state.boost_destab_ticks = config.boost_destab_ticks

# Lancement générique de rampe (élément de piste "rampe", Lot A) : réutilise
# la physique de saut déjà en place (state.au_sol / vit_y / gravité,
# jusqu'ici seule peuplée par SAUT_ARC de Wasp) avec une gravité/vitesse
# initiale PROPRES à la rampe (sim/element_effects.gd), jamais celles du
# véhicule — un Roadster qui saute sur une rampe ne doit pas hériter d'une
# gravité pensée pour le petit saut de 0,6 m de Wasp (mauvais apex, mauvaise
# durée). Ne touche JAMAIS glisse_etat : le laisser à SAUT détournerait la
# machine à états de SAUT_ARC (déclenche un ARC à l'atterrissage) pour un
# véhicule qui n'a pas forcément ce type de glisse. Appelée par
# _appliquer_elements(), gardée par state.au_sol côté appelant (pas de
# relance en l'air).
static func declencher_rampe(state: CarState) -> void:
	state.vit_y = ElementEffects.rampe_vitesse_initiale
	state.saut_gravite_courante = ElementEffects.rampe_gravite
	state.saut_ticks = ElementEffects.rampe_duree_ticks
	state.au_sol = false

# Pénalité ponctuelle de vitesse (obstacle_ralentit léger, obstacle_mortel/
# vide sévère — voir ElementEffects) : réduit la vitesse le long de la
# TRAJECTOIRE courante, même logique que declencher_boost — un impact
# ralentit, il ne fait jamais reculer (state.vit_x/vit_z gardent leur signe,
# seule leur magnitude diminue). Annule aussi un éventuel surplus de boost
# en cours (bonus_vitesse) : un plafond relevé par un boost ne doit pas
# survivre à un impact.
static func appliquer_penalite(state: CarState, penalite: int) -> void:
	var v: int = FixedMath.length_2d(state.vit_x, state.vit_z)
	if v > ReglesCommunes.VITESSE_MIN_CAP:
		var nouvelle_vitesse: int = Fixed.max(0, v - penalite)
		var facteur: int = Fixed.div(nouvelle_vitesse, v)
		state.vit_x = Fixed.mul(state.vit_x, facteur)
		state.vit_z = Fixed.mul(state.vit_z, facteur)
	state.bonus_vitesse = 0

# Détection des éléments de piste (Lot A). Réécrit les champs transitoires
# de state à CHAQUE tick (neutres par défaut : un tick loin de tout élément
# reste bit-identique à avant ce lot), applique les effets ponctuels à
# l'ENTRÉE dans un élément (front montant sur state.elements_dans, arbitrage
# 12 pour l'anti-cumul des zones), détection XZ uniquement (arbitrage 11).
# Aucune allocation par tick : state.elements_dans est dimensionné une fois
# par (voiture, piste), jamais recréé ; les tableaux track.elem_* sont
# chargés une fois au chargement de la piste (map/track_data.gd::to_track()).
static func _appliquer_elements(state: CarState, track: Track, config: CarConfig) -> void:
	state.elem_coef_autorite = Fixed.ONE
	state.elem_bonus_grip = 0
	state.elem_plafond = 0

	var n: int = track.element_count()
	if n == 0:
		return  # piste sans éléments (TrackHardcoded, bancs de mesure...) : totalement inerte

	if state.elements_dans.size() != n:  # une fois par (voiture, piste), jamais par tick
		state.elements_dans.resize(n)
		state.elements_dans.fill(0)

	for i in range(n):
		var kind: int = track.elem_kind[i]
		var rayon: int = ElementEffects.rayons[kind]
		if rayon <= 0:
			state.elements_dans[i] = 0  # type sans effet Lot A (mur, checkpoint, route normale...)
			continue

		var dx: int = state.pos_x - track.elem_x[i]
		var dz: int = state.pos_z - track.elem_z[i]
		var dedans: bool = Fixed.mul(dx, dx) + Fixed.mul(dz, dz) <= ElementEffects.rayons_sq[kind]
		var entree: bool = dedans and state.elements_dans[i] == 0
		state.elements_dans[i] = 1 if dedans else 0
		if not dedans:
			continue

		match kind:
			ElementRoster.Kind.ROUTE_RALENTIT:
				state.elem_plafond = ElementEffects.ralentit_plafond if state.elem_plafond <= 0 else Fixed.min(state.elem_plafond, ElementEffects.ralentit_plafond)
			ElementRoster.Kind.ROUTE_DEGRADE_CONTROLES:
				state.elem_coef_autorite = Fixed.min(state.elem_coef_autorite, ElementEffects.degrade_autorite)
			ElementRoster.Kind.ROUTE_AIMANTEE:
				state.elem_bonus_grip = Fixed.max(state.elem_bonus_grip, ElementEffects.aimant_bonus)
			ElementRoster.Kind.OBSTACLE_RALENTIT:
				if entree:
					appliquer_penalite(state, ElementEffects.plot_penalite)
			ElementRoster.Kind.BOOST:
				if entree:
					declencher_boost(state, config)
			ElementRoster.Kind.RAMPE:
				if entree and state.au_sol:
					declencher_rampe(state)
			ElementRoster.Kind.OBSTACLE_MORTEL, ElementRoster.Kind.VIDE:
				if entree:
					appliquer_penalite(state, ElementEffects.mortel_penalite)
					state.controle_perdu_ticks = ElementEffects.mortel_controle_perdu_ticks
			_:
				pass  # route_normale, ligne_depart_arrivee : no-op assumé (arbitrage 14 pour mortel/vide, pas ici)
