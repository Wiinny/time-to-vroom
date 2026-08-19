# Constantes partagées par les 5 véhicules — tout ce qui n'est PAS une valeur
# de fiche individuelle (voir Paramétrage-Véhicules.md), y compris les
# arbitrages inventés faute de valeur fournie par le cahier des charges
# (voir sim/car_sim.gd, arbitrages en tête de fichier). Convertie une seule
# fois au chargement de la classe, jamais recalculée par tick.
#
# `const` GDScript n'accepte pas d'appel de fonction (Fixed.from_float est
# une méthode statique) : toute valeur qui en dépend est un `static var`
# avec initialiseur, évalué une fois. Les valeurs qui sont déjà une
# expression entière constante (Fixed.ONE / N) restent des `const`.
class_name ReglesCommunes

# --- Boost — identique pour les 5 véhicules (règle du cahier des charges) ---
# Poussée absolue : +45 km/h appliqués instantanément, jamais un pourcentage
# (avantagerait mécaniquement les véhicules déjà rapides).
static var boost_poussee: int = Fixed.from_float(45.0 / 3.6 / float(Horloge.TICKS_PAR_SECONDE))  # Q16.16 m/tick
# Décroissance du surplus de vitesse : 12 km/h PAR SECONDE, donc un TAUX —
# double conversion tick->seconde (/3.6/TICKS_PAR_SECONDE_CARRE), jamais une
# seule division par la cadence. Piège documenté dans CLAUDE.md : indexer ce
# taux sur decel_naturelle romprait l'équité (Halcyon garderait son surplus
# plus longtemps que les autres).
static var boost_decroissance: int = Fixed.from_float(12.0 / 3.6 / float(Horloge.TICKS_PAR_SECONDE_CARRE))  # Q16.16 m/tick, par tick

# --- Géométrie du modèle bicyclette (empattement absent du cahier des charges) ---
const EMPATTEMENT_M: float = 2.5
static var inv_empattement: int = Fixed.from_float(1.0 / EMPATTEMENT_M)  # Q16.16 1/m

# Convertit une accélération latérale (m/tick², "budget" — voir sim/car_sim.gd
# étape 4/5) en seuil de rotation comparable à un Δψ en unités d'angle brutes.
# Constante universelle (pas de dimension physique par véhicule), appliquée
# au budget COURANT à chaque tick — jamais bakée une fois sur `adherence`
# seul dans CarConfig, car le budget réel varie avec le multiplicateur de
# glisse (ReglesCommunes.coef_glisse).
static var rad_vers_brut: int = Fixed.from_float(65536.0 / TAU)

# --- Arbitrages (aucun champ @export ne les couvre, volontairement partagés
# plutôt que dupliqués dans les 5 fiches — voir sim/car_sim.gd) ---
static var coef_scrub: int = Fixed.from_float(1.0)          # perte de vitesse en sous-virage (AUCUNE)
static var coef_glisse: int = Fixed.from_float(1.8)         # multiplicateur de budget latéral en glisse activement engagée (PIVOT_AVANT, glisse_etat == PIVOT)
# Budget de base élargi pour PIVOT_AVANT même SANS glisse engagée (retour
# utilisateur : sans lui, la conduite "normale" du Roadster tombait à un
# plafond aussi strict que Needle/Ironside — mais sans leur filet de
# vitesse (coef_scrub), ce qui donnait l'impression d'un mur en ligne
# droite forcée). Volontairement < coef_glisse (1,5 < 1,8) : la glisse
# activement engagée doit rester strictement plus efficace, sinon le
# bouton dérapage perd tout intérêt exactement dans la situation qui pose
# problème (vérifié par tools/run_tests.gd::_test_glisse_raccourcit).
static var coef_glisse_passif: int = Fixed.from_float(1.5)
static var angle_pivot_max: int = int(round(20.0 / 360.0 * 65536.0))  # unités brutes, contribution du drift à l'angle effectif
static var tan_pivot_max: int = Fixed.from_float(0.364)     # tan(20°) — angle de travers max en PIVOT_AVANT, resserré depuis 35° (retour manette : trajectoire trop large par rapport au nez)
static var tan_arc: int = Fixed.from_float(0.47)            # tan(25°) — angle de travers en SAUT_ARC
# 0,33 s pour engager/dégager une glisse — dépend de la cadence (c'est un
# TAUX par tick), donc static var dérivée de Horloge plutôt qu'une fraction
# figée : Fixed.ONE/20 ne valait 0,33 s qu'à 60 Hz précisément.
static var TAUX_GLISSE_PAR_TICK: int = Fixed.ONE / (Horloge.TICKS_PAR_SECONDE / 3)
static var correction_arc: int = Fixed.from_float(0.15)     # modulation ±15 % du rayon de l'arc, à la marge du joueur
# Ralentit la convergence de l'angle des roues (state.angle_roues) pendant
# une glisse activement engagée (PIVOT_AVANT, glisse_etat == PIVOT) —
# retour utilisateur : une fois lancée, une glisse doit rester difficile à
# rediriger (à la manière d'une vraie voiture de drift, en plus simple à
# contrôler), pas suivre le stick aussi vite qu'en conduite normale. Sans
# ce facteur, angle_roues convergeait à vitesse_braquage plein régime même
# en glisse, ce que le budget d'adhérence élargi (coef_glisse/coef_glisse_
# passif) ne suffisait plus à masquer une fois relevé : la voiture
# traduisait alors quasi instantanément le moindre mouvement de manette en
# rotation, sans inertie. Ne s'applique jamais hors glisse (PIVOT_AVANT
# garde son braquage normal, réactif, quand il ne dérape pas).
static var coef_braquage_glisse: int = Fixed.from_float(0.35)
const SEUIL_BRAQUAGE_GLISSE: int = Fixed.ONE / 8              # braquage minimal pour engager une glisse
# Garde div/0 sous ce régime — pas une valeur de gameplay réglée à la
# manette, juste "négligeable" : exprimée en vitesse réelle (0,25 m/s) pour
# rester indépendante de la cadence plutôt qu'une fraction Q16.16 figée.
static var VITESSE_MIN_CAP: int = Fixed.ONE / 4 / Horloge.TICKS_PAR_SECONDE
