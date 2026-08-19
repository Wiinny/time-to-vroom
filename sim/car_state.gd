# État pur d'une voiture simulée. Que des int/bool (Q16.16 sauf mention
# contraire), plus un PackedByteArray préalloué (elements_dans, dimensionné
# paresseusement une fois par piste, jamais recréé par tick). Un seul objet,
# créé une fois, muté en place à chaque tick — jamais recréé, zéro
# allocation (voir CLAUDE.md, règle 4).
class_name CarState

# Machine à états de glisse (sim/car_sim.gd) : LIBRE = pas de glisse en
# cours ; SAUT = phase aérienne du petit saut (SAUT_ARC, Wasp) avant que
# l'arc ne commence ; ARC = glisse à rayon fixe non guidée (SAUT_ARC) ;
# PIVOT = glisse continue modulable (PIVOT_AVANT). AUCUNE et PERMANENTE
# n'utilisent jamais que LIBRE.
enum GlisseEtat { LIBRE, SAUT, ARC, PIVOT }

var pos_x: int = 0
var pos_y: int = 0
var pos_z: int = 0

var vit_x: int = 0   # m/tick, Q16.16
var vit_z: int = 0   # m/tick, Q16.16
var vit_y: int = 0   # m/tick, Q16.16 — vitesse verticale (saut, SAUT_ARC uniquement)

var yaw: int = 0            # unités d'angle brutes [0, 65536) — PAS du Q16.16, voir FixedMath
var yaw_frac: int = 0       # Q16.16 — reste fractionnaire de l'accumulation du yaw (évite un
                             # biais de troncature asymétrique gauche/droite, Fixed.mul arrondit vers -∞)
var angle_roues: int = 0    # unités d'angle brutes signées — angle de braquage courant,
                             # converge vers la cible à vitesse_braquage (découplé de yaw)

var au_sol: bool = true

var glisse_etat: int = GlisseEtat.LIBRE
var glisse_sens: int = 0        # -1/0/1, verrouillé à l'engagement (utile pendant la phase SAUT,
                                 # où glisse_intensite vaut encore 0 mais la direction est déjà choisie)
var glisse_intensite: int = 0   # Q16.16 signé [-1, 1] — commande de dérive, converge progressivement

var saut_ticks: int = 0             # ticks restants de la phase aérienne
var derapage_precedent: bool = false  # front montant du bouton dérapage -> déclenche le saut

var bonus_vitesse: int = 0      # m/tick, Q16.16 — surplus de plafond dû au boost, décroît à taux fixe
var boost_destab_ticks: int = 0 # ticks restants de perte d'autorité après un boost

# Gravité du SAUT EN COURS (Q16.16, m/tick²) — SAUT_ARC (Wasp) ou une rampe
# (sim/element_effects.gd), jamais une constante figée dans l'étape 10 de
# CarSim.tick() : appliquer la gravité PROPRE à Wasp à un saut de rampe
# générique (ou l'inverse) donnerait un apex/une durée faux.
var saut_gravite_courante: int = 0

# --- Éléments de piste (Lot A, voir CLAUDE.md « Éléments de piste ») ---
# Drapeau "dans la zone de cet élément au tick précédent", un octet par
# élément de la piste courante — dimensionné paresseusement par
# CarSim._appliquer_elements() (jamais ici : reset() ne connaît pas le
# nombre d'éléments de la piste), utilisé pour ne déclencher un effet
# ponctuel (boost, rampe, plot, mortel/vide) qu'à l'ENTRÉE dans la zone, pas
# à chaque tick passé dedans.
var elements_dans: PackedByteArray = PackedByteArray()
var controle_perdu_ticks: int = 0  # ticks restants de perte d'autorité après obstacle_mortel/vide

# Réécrits à CHAQUE tick par CarSim._appliquer_elements() (jamais persistés
# entre deux ticks, contrairement aux champs ci-dessus) — valeurs neutres
# par défaut pour qu'un tick sans élément proche reste bit-identique à avant
# ce lot.
var elem_coef_autorite: int = Fixed.ONE  # multiplicateur d'autorité de direction (route_degrade_controles)
var elem_bonus_grip: int = 0             # bonus additif de budget latéral, Q16.16 m/tick² (route_aimantee)
var elem_plafond: int = 0                # plafond de vitesse de zone, Q16.16 m/tick, 0 = aucun (route_ralentit)

func reset(x: int, y: int, z: int, initial_yaw: int) -> void:
	pos_x = x
	pos_y = y
	pos_z = z
	vit_x = 0
	vit_z = 0
	vit_y = 0
	yaw = initial_yaw
	yaw_frac = 0
	angle_roues = 0
	au_sol = true
	glisse_etat = GlisseEtat.LIBRE
	glisse_sens = 0
	glisse_intensite = 0
	saut_ticks = 0
	derapage_precedent = false
	bonus_vitesse = 0
	boost_destab_ticks = 0
	saut_gravite_courante = 0
	elements_dans.fill(0)  # sûr même sur un tableau de taille 0 (piste sans éléments)
	controle_perdu_ticks = 0
	elem_coef_autorite = Fixed.ONE
	elem_bonus_grip = 0
	elem_plafond = 0

# Hash déterministe de l'état, pour la validation de replay (voir
# replay/replay_data.gd) et les tests de non-régression
# (tools/run_tests.gd::REFERENCE_HASH). Extrait de l'ancien
# tools/run_tests.gd::_hash_state() — MÊME liste de champs, même ordre.
# Volontairement PAS les champs ajoutés depuis (controle_perdu_ticks,
# saut_gravite_courante, elements_dans, elem_*) : les ajouter changerait
# REFERENCE_HASH et retirerait la preuve bon marché que cette extraction
# est neutre. elem_* sont de toute façon de pures dérivées, recalculées
# from scratch à chaque tick (CarSim._appliquer_elements()) ; les deux
# autres sont un vrai trou de couverture, à combler dans un lot séparé avec
# régénération explicite du hash.
func compute_hash(tick: int) -> int:
	var h: int = FixedHash.start()
	h = FixedHash.combine(h, tick)
	h = FixedHash.combine(h, pos_x)
	h = FixedHash.combine(h, pos_y)
	h = FixedHash.combine(h, pos_z)
	h = FixedHash.combine(h, vit_x)
	h = FixedHash.combine(h, vit_z)
	h = FixedHash.combine(h, vit_y)
	h = FixedHash.combine(h, yaw)
	h = FixedHash.combine(h, yaw_frac)
	h = FixedHash.combine(h, angle_roues)
	h = FixedHash.combine(h, glisse_etat)
	h = FixedHash.combine(h, glisse_sens)
	h = FixedHash.combine(h, glisse_intensite)
	h = FixedHash.combine(h, saut_ticks)
	h = FixedHash.combine(h, 1 if au_sol else 0)
	h = FixedHash.combine(h, 1 if derapage_precedent else 0)
	h = FixedHash.combine(h, bonus_vitesse)
	h = FixedHash.combine(h, boost_destab_ticks)
	return h
