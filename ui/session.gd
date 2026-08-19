# Autoload (nom "Session"). change_scene_to_file() ne prend pas de
# paramètres : ce relais minuscule fait passer un chemin de piste d'une
# scène à l'autre (menu éditeur -> éditeur, éditeur -> course). Jamais
# utilisé comme état durable — chaque lecteur le vide aussitôt après l'avoir
# lu.
#
# Le fantôme n'a plus sa place ici depuis ui/ghost_selection.gd : la
# sélection est durable et indexée par piste (elle doit survivre à un
# aller-retour, pas juste transiter une fois vers main.gd), donc un relais à
# usage unique ne convient plus.
extends Node

var pending_track_path: String = ""
