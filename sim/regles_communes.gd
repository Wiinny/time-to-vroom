class_name ReglesCommunes

static var boost_poussee: int = Fixed.from_float(45.0 / 3.6 / float(Horloge.TICKS_PAR_SECONDE))  
static var boost_decroissance: int = Fixed.from_float(12.0 / 3.6 / float(Horloge.TICKS_PAR_SECONDE_CARRE))  


const EMPATTEMENT_M: float = 2.5
static var inv_empattement: int = Fixed.from_float(1.0 / EMPATTEMENT_M)  # Q16.16 1/m

static var rad_vers_brut: int = Fixed.from_float(65536.0 / TAU)

static var coef_scrub: int = Fixed.from_float(1.0)         
static var coef_glisse: int = Fixed.from_float(1.8)         
static var coef_glisse_passif: int = Fixed.from_float(1.5)
static var angle_pivot_max: int = int(round(20.0 / 360.0 * 65536.0))  
static var tan_pivot_max: int = Fixed.from_float(0.364)  
static var tan_arc: int = Fixed.from_float(0.47)            
static var TAUX_GLISSE_PAR_TICK: int = Fixed.ONE / (Horloge.TICKS_PAR_SECONDE / 3)
static var correction_arc: int = Fixed.from_float(0.15)   
static var coef_braquage_glisse: int = Fixed.from_float(0.35)
const SEUIL_BRAQUAGE_GLISSE: int = Fixed.ONE / 8            
static var VITESSE_MIN_CAP: int = Fixed.ONE / 4 / Horloge.TICKS_PAR_SECONDE

const DEMI_LARGEUR_VEHICULE_M: float = 1.05
const REBOND_MUR: float = 0.08
static var demi_largeur_vehicule: int = Fixed.from_float(DEMI_LARGEUR_VEHICULE_M)
static var rebond_mur: int = Fixed.from_float(REBOND_MUR)
