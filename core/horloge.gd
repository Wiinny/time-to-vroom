# Seule source de la cadence de simulation — tout le reste du projet (bake()
# des CarConfig, ReglesCommunes, RaceState, TimeFormat, les bancs de mesure)
# référence ces constantes plutôt que d'écrire 100 en dur, pour ne jamais
# revivre le piège documenté dans CLAUDE.md (une conversion tick->seconde
# oubliée ou mal indexée après un changement de cadence).
#
# 100 Hz (pas 60) précisément parce que 1000 est divisible par 100 : un tick
# vaut alors 10 ms pile, sans arrondi — condition nécessaire pour que le
# chrono affiché soit exact au millième (voir CLAUDE.md, règle non
# négociable n°2).
class_name Horloge

const TICKS_PAR_SECONDE: int = 100
const TICKS_PAR_SECONDE_CARRE: int = TICKS_PAR_SECONDE * TICKS_PAR_SECONDE
const MS_PAR_TICK: int = 1000 / TICKS_PAR_SECONDE
