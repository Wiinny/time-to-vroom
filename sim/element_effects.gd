# Constantes des effets de zone/contact des éléments de piste (Lot A — voir
# CLAUDE.md, section « Éléments de piste »). Même discipline que
# sim/regles_communes.gd : `const` en unités humaines, `static var` baké une
# seule fois vers le Q16.16/les ticks. Toute la LOGIQUE reste dans
# sim/car_sim.gd (celui-ci n'est qu'un tableau de constantes), pour ne pas
# créer de dépendance croisée CarSim <-> ElementEffects — même séparation
# que ReglesCommunes/CarSim.
#
# Valeurs de départ ancrées sur les fourchettes déjà réglées des 5 véhicules
# (vitesse_max 175-195 km/h, accel_basse 4.0-13.5, decel_naturelle 0.5-12.0,
# adherence_laterale 12.6-36.0 m/s², vitesse_braquage 70-400°/s,
# controle_aerien 0.20-0.90) — À AJUSTER MANETTE EN MAIN, comme toutes les
# valeurs de gameplay (voir CLAUDE.md, « Ce qu'il ne faut pas faire »).
# Volontairement PAS de nombre par véhicule : la différenciation par
# véhicule émerge des stats déjà réglées de chaque fiche (voir
# docs/matrice-vehicules.md pour le détail élément par élément), pas de
# constantes dupliquées 5 fois ici.
class_name ElementEffects

# --- Rayons de détection (Q16.16 mètres) ---
# Un élément n'a qu'un point dans TrackData (pas de taille) : une "zone" est
# donc approximée par un disque de rayon fixe par type — pour couvrir un
# tronçon, le créateur aligne plusieurs marqueurs. Le vrai correctif (un
# champ "rayon" optionnel sur l'élément, rétrocompatible) est un changement
# de format à part, volontairement pas traité dans ce lot.
#
# Garde-fou NON NÉGOCIABLE (verrouillé par tools/run_tests.gd) : à
# vitesse_max + boost (Halcyon, 195+45 km/h), la voiture avance 0,667 m par
# tick — un rayon sous 2,0 m (3x cette distance) se ferait traverser sans
# jamais être détecté par l'échantillonnage ponctuel ci-dessous.
const RAYON_ZONE_M: float = 6.0   # route_ralentit / route_degrade_controles / route_aimantee — > DEFAULT_HALF_WIDTH (5.0) de l'éditeur, un marqueur couvre la piste
const RAYON_PAD_M: float = 3.0    # boost / rampe — = SELECTION_RADIUS de l'éditeur, un pad qu'on vise
const RAYON_PLOT_M: float = 2.0   # obstacle_ralentit / obstacle_mortel — 3x le plancher anti-traversée
const RAYON_VIDE_M: float = 4.0   # vide — un trou, plus grand qu'un plot

# --- route_ralentit : plafond doux, pas un mur de vitesse ---
# Plafond doux (pas un clamp brutal) : une résistance ne s'applique qu'AU-
# DESSUS du plafond, jamais un drain plat qui ferait caler certains véhicules
# (à pleine résistance sans plafond, Halcyon — accel_basse 4.0 — ne
# retrouverait jamais l'équilibre et s'arrêterait, ce qui est le comportement
# de "vide", pas de "ralentit"). Chaque véhicule converge vers CE plafond,
# l'approche est progressive, personne ne cale.
const RALENTIT_PLAFOND_KMH: float = 95.0        # ~moitié de la fourchette 175-195
const RALENTIT_RESISTANCE_MS2: float = 14.0     # entre freinage_ms2 min (3.0) et max (18.0)

# --- route_degrade_controles : autorité de direction réduite ---
const DEGRADE_AUTORITE: float = 0.45  # entre boost_destab_facteur d'Halcyon (0.35) et controle_aerien du Roadster (0.50)

# --- route_aimantee : bonus ADDITIF, jamais un multiplicateur ---
# Additif comme la règle du boost ("poussée absolue... jamais un
# pourcentage") : un multiplicateur avantagerait davantage qui a déjà le
# plus d'adhérence (Needle, 36.0) — un bonus fixe est au contraire un
# égalisateur, proportionnellement bien plus fort pour la moins adhérente
# (Halcyon, 12.6 -> +79 % contre +28 % pour Needle).
const AIMANT_BONUS_MS2: float = 10.0

# --- obstacle_ralentit : pénalité ponctuelle au contact ---
const PLOT_PENALITE_KMH: float = 35.0  # < le gain du boost (45) : un plot coûte moins qu'un boost ne rapporte

# --- obstacle_mortel / vide : repli explicite en attendant un vrai système
# de réapparition ("repop", encore non construit — voir CLAUDE.md, État
# actuel). PAS une mort/réapparition : un arrêt nourri + un verrou de
# direction temporaire. Remplacer par un vrai repop plus tard ne touche
# qu'un seul point d'appel (CarSim.appliquer_penalite()). ---
const MORTEL_PENALITE_KMH: float = 250.0     # > 195+45 : arrêt garanti pour absolument tous les véhicules, jamais de marche arrière
const MORTEL_AUTORITE: float = 0.15          # sous le pire du jeu (Halcyon, controle_aerien 0.20)
const MORTEL_CONTROLE_PERDU_S: float = 1.5   # ~2x la déstabilisation post-boost d'Halcyon (0.8 s)

# --- rampe : lancement générique, réutilise la physique de saut existante
# (state.au_sol / vit_y / gravité, jusqu'ici seule Wasp — SAUT_ARC — la
# peuplait) sans jamais utiliser la gravité PROPRE à Wasp (state.
# saut_gravite_courante distingue les deux, voir sim/car_state.gd). ---
const RAMPE_HAUTEUR_M: float = 1.2   # 2x le petit saut de Wasp (0.6 m)
const RAMPE_DUREE_S: float = 0.7     # 1.55x celle de Wasp (0.45 s)

# ============================================================ grandeurs bakées ==

static var rayon_zone: int = Fixed.from_float(RAYON_ZONE_M)
static var rayon_pad: int = Fixed.from_float(RAYON_PAD_M)
static var rayon_plot: int = Fixed.from_float(RAYON_PLOT_M)
static var rayon_vide: int = Fixed.from_float(RAYON_VIDE_M)

static var ralentit_plafond: int = Fixed.from_float(RALENTIT_PLAFOND_KMH / 3.6 / float(Horloge.TICKS_PAR_SECONDE))
static var ralentit_resistance: int = Fixed.from_float(RALENTIT_RESISTANCE_MS2 / float(Horloge.TICKS_PAR_SECONDE_CARRE))
static var degrade_autorite: int = Fixed.from_float(DEGRADE_AUTORITE)
static var aimant_bonus: int = Fixed.from_float(AIMANT_BONUS_MS2 / float(Horloge.TICKS_PAR_SECONDE_CARRE))
static var plot_penalite: int = Fixed.from_float(PLOT_PENALITE_KMH / 3.6 / float(Horloge.TICKS_PAR_SECONDE))
static var mortel_penalite: int = Fixed.from_float(MORTEL_PENALITE_KMH / 3.6 / float(Horloge.TICKS_PAR_SECONDE))
static var mortel_autorite: int = Fixed.from_float(MORTEL_AUTORITE)
static var mortel_controle_perdu_ticks: int = int(round(MORTEL_CONTROLE_PERDU_S * float(Horloge.TICKS_PAR_SECONDE)))

# Même parabole que CarConfig.bake() (h et T sur-déterminent g, T déjà en
# ticks donc aucune division supplémentaire par Horloge.TICKS_PAR_SECONDE
# ici). L'enchaînement static var -> static var au sein d'une même classe
# est initialisé dans l'ordre déclaré (vérifié empiriquement via un script
# headless jetable, cf. méthode documentée dans CLAUDE.md), donc rampe_duree_
# ticks est bien disponible pour les deux lignes suivantes.
static var rampe_duree_ticks: int = int(round(RAMPE_DUREE_S * float(Horloge.TICKS_PAR_SECONDE)))
static var rampe_vitesse_initiale: int = Fixed.from_float(4.0 * RAMPE_HAUTEUR_M / float(rampe_duree_ticks))
static var rampe_gravite: int = Fixed.from_float(8.0 * RAMPE_HAUTEUR_M / (float(rampe_duree_ticks) * float(rampe_duree_ticks)))

# Rayon de détection par type (Q16.16), indexé par ElementRoster.Kind — 0
# pour tout type sans effet en Lot A (route_normale, ligne_depart_arrivee,
# et les types Lot B : barriere, mur, obstacle_bloquant, checkpoint, inconnu).
static var rayons: PackedInt64Array = _build_rayons()
static var rayons_sq: PackedInt64Array = _build_rayons_sq()

static func _build_rayons() -> PackedInt64Array:
	var r := PackedInt64Array()
	r.resize(ElementRoster.Kind.size())
	r[ElementRoster.Kind.ROUTE_RALENTIT] = rayon_zone
	r[ElementRoster.Kind.ROUTE_DEGRADE_CONTROLES] = rayon_zone
	r[ElementRoster.Kind.ROUTE_AIMANTEE] = rayon_zone
	r[ElementRoster.Kind.OBSTACLE_RALENTIT] = rayon_plot
	r[ElementRoster.Kind.OBSTACLE_MORTEL] = rayon_plot
	r[ElementRoster.Kind.VIDE] = rayon_vide
	r[ElementRoster.Kind.RAMPE] = rayon_pad
	r[ElementRoster.Kind.BOOST] = rayon_pad
	return r

static func _build_rayons_sq() -> PackedInt64Array:
	var r := PackedInt64Array()
	r.resize(ElementRoster.Kind.size())
	for i in range(r.size()):
		r[i] = Fixed.mul(rayons[i], rayons[i])
	return r
