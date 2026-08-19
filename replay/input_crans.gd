# Seule source de vérité pour la quantification des inputs — sortie de
# main.gd pour être testable isolément et partagée entre l'enregistrement
# d'un replay et sa lecture (voir replay/replay_data.gd). Deux moitiés bien
# séparées :
#   - *_to_cran() : lit un float du singleton Input (souris/manette/clavier),
#     hors de sim/, jamais appelée pendant la lecture d'un replay.
#   - cran_to_fixed_*() : convertit un cran (entier déjà quantifié) en
#     Q16.16, float-free — c'est CE contrat qui doit rester identique entre
#     enregistrement et lecture pour qu'un replay soit bit-exact.
class_name InputCrans

const QUANT_UNI: int = 255   # crans pour accélérateur / frein / dérapage, [0, 1]
const QUANT_BI: int = 127    # crans pour le braquage, [-1, 1]

# Décalage pour stocker un braquage signé [-127, 127] dans un octet non
# signé (PackedByteArray) : [-127, 127] -> [0, 254], 255 inutilisé.
const BIAIS_BRAQUAGE: int = QUANT_BI

static func uni_to_cran(value: float) -> int:
	return int(round(clampf(value, 0.0, 1.0) * float(QUANT_UNI)))

static func bi_to_cran(value: float) -> int:
	return int(round(clampf(value, -1.0, 1.0) * float(QUANT_BI)))

# Reprises à l'identique de l'ancien main.gd::_quantize_uni/_quantize_bi —
# ne pas "simplifier" l'expression, l'arrondi de Fixed.div fait partie du
# comportement actuel (donc du hash de régression).
static func cran_to_fixed_uni(cran: int) -> int:
	return Fixed.div(Fixed.from_int(cran), Fixed.from_int(QUANT_UNI))

static func cran_to_fixed_bi(cran: int) -> int:
	return Fixed.div(Fixed.from_int(cran), Fixed.from_int(QUANT_BI))

static func bi_to_octet(cran: int) -> int:
	return cran + BIAIS_BRAQUAGE

static func octet_to_bi(octet: int) -> int:
	return octet - BIAIS_BRAQUAGE
