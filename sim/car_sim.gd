class_name CarSim

static func tick(state: CarState, input: InputFrame, track: Track, config: CarConfig, query: TrackQueryResult) -> void:
	_appliquer_elements(state, track, config)

	var v: int = FixedMath.length_2d(state.vit_x, state.vit_z)
	var cout_saut_a_appliquer: int = 0

	var sens_deplacement: int = Fixed.sign(Fixed.mul(state.vit_x, FixedMath.sin(state.yaw)) + Fixed.mul(state.vit_z, FixedMath.cos(state.yaw)))
	if sens_deplacement == 0:
		sens_deplacement = 1  

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

	var autorite: int = Fixed.ONE
	if not state.au_sol:
		autorite = Fixed.mul(autorite, config.controle_aerien_coef)
	if state.boost_destab_ticks > 0:
		autorite = Fixed.mul(autorite, config.boost_destab_facteur_coef)
	if state.elem_coef_autorite != Fixed.ONE:
		autorite = Fixed.mul(autorite, state.elem_coef_autorite)
	if state.controle_perdu_ticks > 0:
		autorite = Fixed.mul(autorite, ElementEffects.mortel_autorite)
	var cible_angle: int = Fixed.mul(Fixed.mul(config.angle_braquage_max, input.braquage), autorite)
	var vitesse_braquage_effective: int = config.vitesse_braquage
	if state.glisse_etat == CarState.GlisseEtat.PIVOT:
		vitesse_braquage_effective = Fixed.mul(vitesse_braquage_effective, ReglesCommunes.coef_braquage_glisse)
	state.angle_roues = _move_toward(state.angle_roues, cible_angle, vitesse_braquage_effective)

	var cible_intensite: int = 0
	if state.glisse_etat == CarState.GlisseEtat.PIVOT:
		cible_intensite = Fixed.mul(input.braquage, Fixed.HALF + Fixed.mul(Fixed.HALF, input.accel))
	state.glisse_intensite = _move_toward(state.glisse_intensite, cible_intensite, ReglesCommunes.TAUX_GLISSE_PAR_TICK)
	if state.glisse_etat == CarState.GlisseEtat.ARC:
		state.glisse_intensite = state.glisse_sens * Fixed.ONE 

	var dpsi: int
	var budget: int = 0
	var budget_illimite: bool = false
	if state.glisse_etat == CarState.GlisseEtat.ARC:
		var rayon_mod: int = Fixed.ONE - Fixed.mul(ReglesCommunes.correction_arc, input.braquage * state.glisse_sens)
		rayon_mod = Fixed.max(rayon_mod, Fixed.ONE / 4)
		dpsi = state.glisse_sens * Fixed.div(Fixed.mul(v, config.arc_gain), rayon_mod)
		budget_illimite = true
	else:
		var angle_effectif: int = state.angle_roues
		if state.glisse_etat == CarState.GlisseEtat.PIVOT:
			angle_effectif += Fixed.mul(state.glisse_intensite, ReglesCommunes.angle_pivot_max)
		dpsi = Fixed.mul(v, ReglesCommunes.inv_empattement) * angle_effectif * sens_deplacement
		budget = config.adherence
		if state.glisse_etat == CarState.GlisseEtat.PIVOT:
			budget = Fixed.mul(budget, ReglesCommunes.coef_glisse)
		elif config.type_glisse == CarConfig.TypeGlisse.PIVOT_AVANT:
			budget = Fixed.mul(budget, ReglesCommunes.coef_glisse_passif)
		budget += state.elem_bonus_grip
		if not state.au_sol:
			budget = 0

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

	state.yaw_frac += dpsi
	var entiers: int = state.yaw_frac >> 16
	state.yaw = (state.yaw + entiers) & (FixedMath.FULL_TURN - 1)
	state.yaw_frac -= entiers << 16

	var fwd_x: int = FixedMath.sin(state.yaw)
	var fwd_z: int = FixedMath.cos(state.yaw)
	var right_x: int = fwd_z
	var right_z: int = -fwd_x
	var forward_speed: int = Fixed.mul(state.vit_x, fwd_x) + Fixed.mul(state.vit_z, fwd_z)
	var lateral_speed: int = Fixed.mul(state.vit_x, right_x) + Fixed.mul(state.vit_z, right_z)

	var t: int = Fixed.clamp(Fixed.div(Fixed.abs(forward_speed), config.palier_accel), 0, Fixed.ONE)
	var accel_courbe: int = Fixed.lerp(config.accel_basse, config.accel_haute, t)
	forward_speed += Fixed.mul(accel_courbe, input.accel)
	forward_speed -= Fixed.mul(config.freinage, input.frein)

	var saturation: int = 0
	if state.glisse_etat == CarState.GlisseEtat.ARC:
		saturation = Fixed.ONE
	elif not budget_illimite and budget > 0:
		saturation = Fixed.clamp(Fixed.div(Fixed.abs(lateral_speed), budget), 0, Fixed.ONE)

	var resist: int = Fixed.mul(config.decel_naturelle, Fixed.ONE - input.accel)
	resist += scrub
	resist += Fixed.mul(Fixed.mul(config.perte_glisse, saturation), Fixed.abs(forward_speed))
	if state.elem_plafond > 0 and Fixed.abs(forward_speed) > state.elem_plafond:
		resist += ElementEffects.ralentit_resistance
	if query.initialized and query.surface_kind == Track.Surface.BOUE and Fixed.abs(forward_speed) > ElementEffects.boue_plafond:
		resist += ElementEffects.boue_resistance

	if Fixed.abs(forward_speed) <= resist:
		forward_speed = 0
	else:
		forward_speed -= resist * Fixed.sign(forward_speed)
	forward_speed -= cout_saut_a_appliquer

	state.bonus_vitesse = Fixed.max(0, state.bonus_vitesse - ReglesCommunes.boost_decroissance)
	forward_speed = Fixed.clamp(forward_speed, -config.vitesse_max_marche_arriere, config.vitesse_max + state.bonus_vitesse)

	var lateral_cible: int = 0
	if state.glisse_etat == CarState.GlisseEtat.PIVOT:
		lateral_cible = -Fixed.mul(Fixed.mul(v, state.glisse_intensite), ReglesCommunes.tan_pivot_max)
	elif state.glisse_etat == CarState.GlisseEtat.ARC:
		lateral_cible = -state.glisse_sens * Fixed.mul(v, ReglesCommunes.tan_arc)

	var correction: int = lateral_speed - lateral_cible
	if not budget_illimite:
		correction = Fixed.clamp(correction, -budget, budget)
	lateral_speed -= correction

	state.vit_x = Fixed.mul(forward_speed, fwd_x) + Fixed.mul(lateral_speed, right_x)
	state.vit_z = Fixed.mul(forward_speed, fwd_z) + Fixed.mul(lateral_speed, right_z)
	if not state.au_sol:
		state.vit_y -= state.saut_gravite_courante

	state.pos_x += state.vit_x
	state.pos_z += state.vit_z
	state.pos_y += state.vit_y

	track.closest_point_near(state.pos_x, state.pos_z, query)

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

	var limite_laterale: int = Fixed.max(Fixed.ONE / 4, query.half_width - ReglesCommunes.demi_largeur_vehicule)
	if Fixed.abs(query.lateral_offset) > limite_laterale:
		var clamped: int = Fixed.clamp(query.lateral_offset, -limite_laterale, limite_laterale)
		state.pos_x = query.closest_x + Fixed.mul(query.right_x, clamped)
		state.pos_z = query.closest_z + Fixed.mul(query.right_z, clamped)

		var piste_forward: int = Fixed.mul(state.vit_x, query.forward_x) + Fixed.mul(state.vit_z, query.forward_z)
		var piste_lateral: int = Fixed.mul(state.vit_x, query.right_x) + Fixed.mul(state.vit_z, query.right_z)
		var cote: int = Fixed.sign(query.lateral_offset)
		if piste_lateral * cote > 0:
			piste_lateral = -Fixed.mul(piste_lateral, ReglesCommunes.rebond_mur)
		state.vit_x = Fixed.mul(piste_forward, query.forward_x) + Fixed.mul(piste_lateral, query.right_x)
		state.vit_z = Fixed.mul(piste_forward, query.forward_z) + Fixed.mul(piste_lateral, query.right_z)

	if state.boost_destab_ticks > 0:
		state.boost_destab_ticks -= 1
	if state.controle_perdu_ticks > 0:
		state.controle_perdu_ticks -= 1
	state.derapage_precedent = input.derapage > 0

static func _move_toward(current: int, target: int, max_delta: int) -> int:
	if current < target:
		return Fixed.min(current + max_delta, target)
	elif current > target:
		return Fixed.max(current - max_delta, target)
	return current

static func declencher_boost(state: CarState, config: CarConfig) -> void:
	var v: int = FixedMath.length_2d(state.vit_x, state.vit_z)
	var dir_x: int
	var dir_z: int
	if v > ReglesCommunes.VITESSE_MIN_CAP:
		dir_x = Fixed.div(state.vit_x, v)
		dir_z = Fixed.div(state.vit_z, v)
	else:
		dir_x = FixedMath.sin(state.yaw)
		dir_z = FixedMath.cos(state.yaw)
	state.vit_x += Fixed.mul(ReglesCommunes.boost_poussee, dir_x)
	state.vit_z += Fixed.mul(ReglesCommunes.boost_poussee, dir_z)
	var nouvelle_vitesse: int = FixedMath.length_2d(state.vit_x, state.vit_z)
	state.bonus_vitesse = Fixed.max(0, nouvelle_vitesse - config.vitesse_max)
	if config.boost_destab_ticks > 0:
		state.boost_destab_ticks = config.boost_destab_ticks

static func declencher_rampe(state: CarState) -> void:
	state.vit_y = ElementEffects.rampe_vitesse_initiale
	state.saut_gravite_courante = ElementEffects.rampe_gravite
	state.saut_ticks = ElementEffects.rampe_duree_ticks
	state.au_sol = false

static func appliquer_penalite(state: CarState, penalite: int) -> void:
	var v: int = FixedMath.length_2d(state.vit_x, state.vit_z)
	if v > ReglesCommunes.VITESSE_MIN_CAP:
		var nouvelle_vitesse: int = Fixed.max(0, v - penalite)
		var facteur: int = Fixed.div(nouvelle_vitesse, v)
		state.vit_x = Fixed.mul(state.vit_x, facteur)
		state.vit_z = Fixed.mul(state.vit_z, facteur)
	state.bonus_vitesse = 0

static func _appliquer_elements(state: CarState, track: Track, config: CarConfig) -> void:
	state.elem_coef_autorite = Fixed.ONE
	state.elem_bonus_grip = 0
	state.elem_plafond = 0

	var n: int = track.element_count()
	if n == 0:
		return  

	if state.elements_dans.size() != n:  
		state.elements_dans.resize(n)
		state.elements_dans.fill(0)

	for i in range(n):
		var kind: int = track.elem_kind[i]
		var rayon: int = ElementEffects.rayons[kind]
		if rayon <= 0:
			state.elements_dans[i] = 0  
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
				pass  
