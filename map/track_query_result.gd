# Résultat réutilisable d'une requête Track.closest_point().
#
# Alloué une seule fois (par res://sim/world.gd) et rempli en place à chaque
# tick — jamais recréé dans la boucle de simulation.
class_name TrackQueryResult

var segment_index: int = 0
var height: int = 0           # Q16.16, hauteur de la piste au point projeté
var half_width: int = 0       # Q16.16, demi-largeur interpolée à ce point
var lateral_offset: int = 0   # Q16.16, signé : distance au centre, + = à droite du tracé
var closest_x: int = 0        # Q16.16, point projeté sur la ligne centrale
var closest_z: int = 0
var forward_x: int = 0           # Q16.16, tangente normalisée du segment
var forward_z: int = Fixed.ONE
var right_x: int = Fixed.ONE     # Q16.16, perpendiculaire normalisée (90° horaire de forward)
var right_z: int = 0
