# Entrée d'un tick de simulation. Les valeurs sont déjà quantifiées (256
# crans) par res://main.gd avant d'entrer dans la simulation — c'est ce cran
# entier qui sera enregistré dans le replay, pour que le rejeu soit exact.
class_name InputFrame

var accel: int = 0      # Q16.16, [0, Fixed.ONE]
var frein: int = 0      # Q16.16, [0, Fixed.ONE]
var braquage: int = 0   # Q16.16, [-Fixed.ONE, Fixed.ONE] (+ = vers la droite)
var derapage: int = 0   # Q16.16, [0, Fixed.ONE] — utilisé en tout-ou-rien (> 0 = maintenu)
