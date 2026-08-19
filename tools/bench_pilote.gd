# Contrôleur automatique déterministe, entièrement en virgule fixe (aucun
# float dans la géométrie/décision — les chronos mesurés par
# tools/bench_equilibrage.gd et tools/bench_rayon.gd doivent être
# reproductibles au tick près, d'une exécution et d'une machine à l'autre,
# voir Paramétrage-Véhicules.md).
#
# Direction : poursuite d'un point cible (pure pursuit) devant la voiture.
# Vitesse : dérivée du braquage COURANT déjà commandé par la direction, pas
# d'une estimation séparée de la courbure de la piste à venir.
#
# Piège rencontré et écarté : une première version estimait le rayon local
# via deux sondes géométriques (deux appels closest_point + différence de
# tangentes) à plusieurs distances devant la voiture. Sur une piste
# procédurale (map/track_builder.gd), qui est une POLYLIGNE, cette
# estimation était bruitée (une sonde peut tomber pile sur un segment plat
# et manquer un virage, ou l'inverse), et surtout AVEUGLE à la fin d'un
# virage déjà engagé si la projection "droit devant le cap courant" dépasse
# la sortie du virage — la voiture relançait alors à pleine accélération
# EN PLEIN VIRAGE et percutait le mur de sortie, s'y retrouvant piégée
# indéfiniment (closest_point() recalculant le même point de bord à chaque
# tick). Dériver la vitesse du braquage déjà commandé par la poursuite de
# point est auto-cohérent par construction : tant que la direction demande
# de tourner pour suivre la piste, la vitesse reste bridée — impossible de
# "perdre" un virage déjà engagé. Bénéfice secondaire : un seul
# closest_point() par tick au lieu de neuf, bien plus rapide.
#
# Deux politiques : ADHERENCE (dérapage jamais pressé) et GLISSE (dérapage
# pressé dès que le braquage commandé dépasse un seuil). Il n'existe pas de
# définition d'"optimal" sans joueur humain — celle retenue ici est
# opérationnelle : le meilleur chrono des deux politiques, par véhicule
# (voir les deux bancs). Pour bench_rayon.gd, la politique gagnante EST le
# résultat cherché : le rayon où GLISSE cesse de gagner est le point de
# bascule.
class_name BenchPilote

const DISTANCE_VISEE_BASE_M: int = 8
const FACTEUR_ANTICIPATION_TICKS: int = 60  # 0,6 s — distance de visée additionnelle = v × ce facteur
const RAYON_REFERENCE_M: int = 18  # rayon "type" servant à dériver une vitesse de virage sûre depuis le braquage commandé

static var marge_vitesse: int = Fixed.from_float(0.85)      # marge de sécurité sous la limite d'adhérence théorique
static var seuil_braquage_glisse: int = Fixed.ONE / 3        # au-delà, la politique GLISSE engage le dérapage

var _track: Track
var _config: CarConfig
var _utiliser_glisse: bool
var _v_lim_reference: int  # calculé une fois : vitesse sûre à RAYON_REFERENCE_M pour CE véhicule
var _query: TrackQueryResult = TrackQueryResult.new()  # alloué une fois, réutilisé à chaque appel

func _init(track: Track, config: CarConfig, utiliser_glisse: bool) -> void:
	_track = track
	_config = config
	_utiliser_glisse = utiliser_glisse
	_v_lim_reference = Fixed.mul(FixedMath.sqrt(Fixed.mul(config.adherence, Fixed.from_int(RAYON_REFERENCE_M))), marge_vitesse)

# Remplit `input` en place (comme sim/world.gd, un seul InputFrame réutilisé
# par l'appelant plutôt qu'une allocation par tick).
func calculer(state: CarState, input: InputFrame) -> void:
	var v: int = FixedMath.length_2d(state.vit_x, state.vit_z)
	var fwd_x: int = FixedMath.sin(state.yaw)
	var fwd_z: int = FixedMath.cos(state.yaw)

	# --- Direction : poursuite d'un point cible devant la voiture ---
	var extra_visee_m: int = Fixed.mul(v, Fixed.from_int(FACTEUR_ANTICIPATION_TICKS)) >> 16
	var distance_visee_m: int = DISTANCE_VISEE_BASE_M + extra_visee_m
	var sonde_x: int = state.pos_x + Fixed.mul(fwd_x, Fixed.from_int(distance_visee_m))
	var sonde_z: int = state.pos_z + Fixed.mul(fwd_z, Fixed.from_int(distance_visee_m))
	_track.closest_point(sonde_x, sonde_z, _query)

	var cible_x: int = _query.closest_x - state.pos_x
	var cible_z: int = _query.closest_z - state.pos_z
	var cap_voulu: int = FixedMath.atan2(cible_x, cible_z)
	var erreur: int = (cap_voulu - state.yaw) & (FixedMath.FULL_TURN - 1)
	if erreur > FixedMath.HALF_TURN:
		erreur -= FixedMath.FULL_TURN
	input.braquage = Fixed.clamp(Fixed.div(Fixed.from_int(erreur), Fixed.from_int(FixedMath.QUARTER_TURN)), -Fixed.ONE, Fixed.ONE)

	# --- Vitesse : dérivée du braquage qui vient d'être commandé ---
	var intensite_virage: int = Fixed.abs(input.braquage)
	var v_cible: int = Fixed.lerp(_config.vitesse_max, _v_lim_reference, intensite_virage)

	if v > v_cible:
		input.frein = Fixed.ONE
		input.accel = 0
	else:
		input.accel = Fixed.ONE
		input.frein = 0

	# --- Politique de glisse ---
	input.derapage = Fixed.ONE if (_utiliser_glisse and intensite_virage > seuil_braquage_glisse) else 0
