class_name ElementEffects

const RAYON_ZONE_M: float = 6.0  
const RAYON_PAD_M: float = 3.0    
const RAYON_PLOT_M: float = 2.0   
const RAYON_VIDE_M: float = 4.0   

const RALENTIT_PLAFOND_KMH: float = 95.0        
const RALENTIT_RESISTANCE_MS2: float = 14.0   

const BOUE_PLAFOND_KMH: float = 135.0
const BOUE_RESISTANCE_MS2: float = 7.0

const DEGRADE_AUTORITE: float = 0.45 

const AIMANT_BONUS_MS2: float = 10.0

const PLOT_PENALITE_KMH: float = 35.0 

const MORTEL_PENALITE_KMH: float = 250.0   
const MORTEL_AUTORITE: float = 0.15        
const MORTEL_CONTROLE_PERDU_S: float = 1.5  

const RAMPE_HAUTEUR_M: float = 1.2  )
const RAMPE_DUREE_S: float = 0.7    


static var rayon_zone: int = Fixed.from_float(RAYON_ZONE_M)
static var rayon_pad: int = Fixed.from_float(RAYON_PAD_M)
static var rayon_plot: int = Fixed.from_float(RAYON_PLOT_M)
static var rayon_vide: int = Fixed.from_float(RAYON_VIDE_M)

static var ralentit_plafond: int = Fixed.from_float(RALENTIT_PLAFOND_KMH / 3.6 / float(Horloge.TICKS_PAR_SECONDE))
static var ralentit_resistance: int = Fixed.from_float(RALENTIT_RESISTANCE_MS2 / float(Horloge.TICKS_PAR_SECONDE_CARRE))
static var boue_plafond: int = Fixed.from_float(BOUE_PLAFOND_KMH / 3.6 / float(Horloge.TICKS_PAR_SECONDE))
static var boue_resistance: int = Fixed.from_float(BOUE_RESISTANCE_MS2 / float(Horloge.TICKS_PAR_SECONDE_CARRE))
static var degrade_autorite: int = Fixed.from_float(DEGRADE_AUTORITE)
static var aimant_bonus: int = Fixed.from_float(AIMANT_BONUS_MS2 / float(Horloge.TICKS_PAR_SECONDE_CARRE))
static var plot_penalite: int = Fixed.from_float(PLOT_PENALITE_KMH / 3.6 / float(Horloge.TICKS_PAR_SECONDE))
static var mortel_penalite: int = Fixed.from_float(MORTEL_PENALITE_KMH / 3.6 / float(Horloge.TICKS_PAR_SECONDE))
static var mortel_autorite: int = Fixed.from_float(MORTEL_AUTORITE)
static var mortel_controle_perdu_ticks: int = int(round(MORTEL_CONTROLE_PERDU_S * float(Horloge.TICKS_PAR_SECONDE)))

static var rampe_duree_ticks: int = int(round(RAMPE_DUREE_S * float(Horloge.TICKS_PAR_SECONDE)))
static var rampe_vitesse_initiale: int = Fixed.from_float(4.0 * RAMPE_HAUTEUR_M / float(rampe_duree_ticks))
static var rampe_gravite: int = Fixed.from_float(8.0 * RAMPE_HAUTEUR_M / (float(rampe_duree_ticks) * float(rampe_duree_ticks)))

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
