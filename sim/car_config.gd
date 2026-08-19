# Paramètres de conduite, un jeu par véhicule (voir sim/car_configs/*.gd —
# une classe GDScript par véhicule, PAS des .tres : décision explicite pour
# ne pas exposer les valeurs comme un fichier de données éditable en texte
# brut à côté de l'exécutable). Les champs @export sont en unités humaines
# (km/h, m/s², degrés, degrés/s, %/s) pour être lisibles et réglables à la
# manette dans l'inspecteur Godot — c'est le seul endroit du projet où on
# ajuste le feeling.
#
# bake() convertit ces valeurs une seule fois (au chargement, jamais dans la
# boucle de tick) vers les grandeurs Q16.16 "par tick" que sim/car_sim.gd
# utilise réellement. Fixed.from_float() n'est légal qu'ici. Les défauts du
# script ci-dessous sont la fiche Roadster — c'est le repli sûr de
# CarConfig.charger() (véhicule inconnu) et la config testée par
# tools/run_tests.gd::_build_test_world().
#
# Correspondance de nommage (arbitrage — le cahier des charges nomme un
# champ "vitesse_max", déjà pris par le champ baké ci-dessous) : suffixe
# d'unité sur les @export (_kmh/_ms2/_deg/_deg_s/_pct_s), nom nu sur le
# champ baké correspondant.
class_name CarConfig
extends Resource

# Ne jamais réordonner ni insérer un membre au milieu : bien que les 5
# configs soient des classes GDScript (pas des .tres sérialisés), un champ
# int brut comparé ailleurs au cast de cet enum resterait un piège si
# l'ordre changeait silencieusement une valeur déjà réglée à la manette.
enum TypeGlisse { AUCUNE, PIVOT_AVANT, SAUT_ARC, PERMANENTE }

# --- Longitudinal ---
@export var vitesse_max_kmh: float = 180.0
@export var vitesse_max_marche_arriere_kmh: float = 60.0  # absent du cahier des charges, la marche arrière existe déjà
@export var palier_accel_kmh: float = 110.0
@export var accel_basse_ms2: float = 11.0
@export var accel_haute_ms2: float = 3.5
@export var freinage_ms2: float = 18.0
@export var decel_naturelle_ms2: float = 12.0  # remplace trainee + frottement_roulement (voir bake())

# --- Latéral ---
@export var angle_braquage_max_deg: float = 34.0
@export var vitesse_braquage_deg_s: float = 180.0
@export var adherence_laterale_ms2: float = 25.2  # ×1,8 depuis la fiche cahier des charges (14.0) — voir CLAUDE.md, chantier d'équilibrage adhérence
@export var controle_aerien: float = 0.50  # 0-1, autorité de direction en l'air

# --- Glisse ---
@export var type_glisse: TypeGlisse = TypeGlisse.PIVOT_AVANT
@export var perte_vitesse_glisse_pct_s: float = 6.0
@export var rayon_glisse_m: float = 0.0  # SAUT_ARC uniquement, 0 = sans objet

# --- Saut (Wasp uniquement, tout à 0 ailleurs) ---
@export var hauteur_saut_m: float = 0.0
@export var duree_saut_s: float = 0.0
@export var cout_vitesse_saut_kmh: float = 0.0

# --- Boost (règles communes dans sim/regles_communes.gd ; ceci ne règle que
# la déstabilisation, propre à chaque véhicule) ---
@export var boost_destab_duree_s: float = 0.0
@export var boost_destab_facteur: float = 1.0  # 0-1, autorité conservée pendant la déstabilisation (1 = aucun effet)

# ============================================================ grandeurs bakées ==
# "par tick" (cadence Horloge.TICKS_PAR_SECONDE, cf. core/horloge.gd). Q16.16
# sauf mention contraire.

var vitesse_max: int = 0
var vitesse_max_marche_arriere: int = 0
var palier_accel: int = 0
var accel_basse: int = 0
var accel_haute: int = 0
var freinage: int = 0
var decel_naturelle: int = 0
var adherence: int = 0
var controle_aerien_coef: int = 0
var perte_glisse: int = 0
var arc_gain: int = 0  # dérivé : 0 si rayon_glisse_m <= 0 (dégrade SAUT_ARC en AUCUNE, voir car_sim.gd)
var saut_vitesse_initiale: int = 0
var saut_gravite: int = 0
var cout_vitesse_saut: int = 0
var boost_destab_facteur_coef: int = 0

# Unités d'angle BRUTES (PAS du Q16.16 — même convention que CarState.yaw /
# FixedMath, où 65536 unités = un tour complet). angle_braquage_max est une
# POSITION angulaire (pas de /Horloge.TICKS_PAR_SECONDE) ; vitesse_braquage
# est un TAUX (/Horloge.TICKS_PAR_SECONDE, comme l'ancien taux_braquage_par_tick).
var angle_braquage_max: int = 0
var vitesse_braquage: int = 0

# Entiers simples (compteurs de ticks), pas Q16.16.
var saut_duree_ticks: int = 0
var boost_destab_ticks: int = 0

func bake() -> void:
	# Grandeur "par tick" en sortie (vitesse cible, seuil de vitesse) : une
	# seule conversion tick->seconde, /Horloge.TICKS_PAR_SECONDE.
	vitesse_max = Fixed.from_float(vitesse_max_kmh / 3.6 / float(Horloge.TICKS_PAR_SECONDE))
	vitesse_max_marche_arriere = Fixed.from_float(vitesse_max_marche_arriere_kmh / 3.6 / float(Horloge.TICKS_PAR_SECONDE))
	var palier_kmh: float = palier_accel_kmh if palier_accel_kmh > 0.0 else vitesse_max_kmh
	palier_accel = Fixed.from_float(palier_kmh / 3.6 / float(Horloge.TICKS_PAR_SECONDE))

	# Accélération m/s² : DEUX conversions tick->seconde (l'intégration
	# accel->vitesse, plus la vitesse elle-même déjà "par tick") ->
	# /Horloge.TICKS_PAR_SECONDE_CARRE.
	accel_basse = Fixed.from_float(accel_basse_ms2 / float(Horloge.TICKS_PAR_SECONDE_CARRE))
	accel_haute = Fixed.from_float(accel_haute_ms2 / float(Horloge.TICKS_PAR_SECONDE_CARRE))
	freinage = Fixed.from_float(freinage_ms2 / float(Horloge.TICKS_PAR_SECONDE_CARRE))
	decel_naturelle = Fixed.from_float(decel_naturelle_ms2 / float(Horloge.TICKS_PAR_SECONDE_CARRE))
	adherence = Fixed.from_float(adherence_laterale_ms2 / float(Horloge.TICKS_PAR_SECONDE_CARRE))
	# Pas de conversion en unités d'angle ici : le budget latéral réel varie
	# au runtime (multiplié par ReglesCommunes.coef_glisse en glisse), donc
	# la conversion se fait à chaque tick sur le budget courant, pas une
	# seule fois ici sur `adherence` seul — voir sim/car_sim.gd, étape 5.

	# Position angulaire (pas un taux) : PAS de /Horloge.TICKS_PAR_SECONDE.
	angle_braquage_max = int(round(angle_braquage_max_deg / 360.0 * 65536.0))
	# Taux angulaire : /Horloge.TICKS_PAR_SECONDE, comme l'ancien taux_braquage_par_tick.
	vitesse_braquage = int(round(vitesse_braquage_deg_s / 360.0 * 65536.0 / float(Horloge.TICKS_PAR_SECONDE)))

	# Sans dimension temporelle.
	controle_aerien_coef = Fixed.from_float(controle_aerien)
	boost_destab_facteur_coef = Fixed.from_float(boost_destab_facteur)

	# Taux par seconde -> /Horloge.TICKS_PAR_SECONDE.
	perte_glisse = Fixed.from_float(perte_vitesse_glisse_pct_s / 100.0 / float(Horloge.TICKS_PAR_SECONDE))

	arc_gain = Fixed.from_float(65536.0 / TAU / rayon_glisse_m) if rayon_glisse_m > 0.0 else 0

	if duree_saut_s > 0.0:
		saut_duree_ticks = int(round(duree_saut_s * float(Horloge.TICKS_PAR_SECONDE)))
		# Parabole d'apex hauteur_saut_m à T/2 TICKS (pas secondes) : vitesse
		# initiale 4h/T, gravité 8h/T² — T déjà en ticks, donc AUCUNE division
		# supplémentaire par Horloge.TICKS_PAR_SECONDE(_CARRE) ici (elle est
		# déjà "consommée" par T).
		# h et T sur-déterminent g (qui ne vaut donc pas 9,81 — arcade assumé :
		# vérifié Wasp = 0,6m/0,45s -> g ≈ 23,7 m/s²).
		var t_ticks: float = float(saut_duree_ticks)
		saut_vitesse_initiale = Fixed.from_float(4.0 * hauteur_saut_m / t_ticks)
		saut_gravite = Fixed.from_float(8.0 * hauteur_saut_m / (t_ticks * t_ticks))
	else:
		saut_duree_ticks = 0
		saut_vitesse_initiale = 0
		saut_gravite = 0
	cout_vitesse_saut = Fixed.from_float(cout_vitesse_saut_kmh / 3.6 / float(Horloge.TICKS_PAR_SECONDE))

	boost_destab_ticks = int(round(boost_destab_duree_s * float(Horloge.TICKS_PAR_SECONDE)))

# Résout la config d'un véhicule par son id (ui/vehicle_roster.gd). Les 5
# configs sont des classes GDScript (sim/car_configs/car_config_*.gd), pas
# des .tres — décision explicite pour ne pas exposer les valeurs comme un
# fichier de données éditable en texte brut à côté de l'exécutable. Même
# tolérance aux pannes que Controls/VehicleSelection/Leaderboard : id
# inconnu -> repli sur le véhicule par défaut, jamais de crash.
static func charger(vehicule_id: String) -> CarConfig:
	var id: String = vehicule_id
	if VehicleRoster.find(id).is_empty():
		id = VehicleRoster.default_id()
	match id:
		"gt":
			return CarConfigGt.new()
		"formula":
			return CarConfigFormula.new()
		"superbike":
			return CarConfigSuperbike.new()
		"street_bike":
			return CarConfigStreetBike.new()
		"hover":
			return CarConfigHover.new()
		_:
			return CarConfig.new()  # filet de sécurité, ne devrait jamais être atteint
