# Format de fichier de replay — sauvegardé/chargé via ResourceSaver/
# ResourceLoader vers user://replays/<nom>.tres (voir replay/replay_store.gd),
# même patron que map/track_data.gd pour les pistes. Un Resource Godot natif
# (versionné, typé), pas un format maison à parser.
#
# Un replay est le log d'inputs COMPLET d'un run terminé, depuis le tick 0
# de la scène (PAS depuis le premier input actif) — nécessaire pour rejouer
# un fantôme aligné sur le chrono du joueur (voir main.gd, qui pré-remplit
# le monde du fantôme jusqu'à start_tick avant de l'avancer en lockstep).
# Les crans sont stockés tels que capturés par res://replay/input_crans.gd —
# jamais reconvertis en Q16.16 avant sauvegarde, pour rester compacts
# (PackedByteArray, ~4 octets/tick) et pour que la lecture repasse par
# EXACTEMENT le même chemin de conversion que l'enregistrement.
#
# Champs volontairement absents de « Données à enregistrer pour chaque
# run » (CLAUDE.md) : mods actifs, temps aux checkpoints, version de la
# piste, version du jeu, joueur — aucun n'existe encore ailleurs dans le
# projet, seront ajoutés quand ces systèmes existeront.
#
# Trou connu : TrackData n'a pas de numéro de révision de contenu — un
# replay enregistré avant une modification de la piste désynchronise
# silencieusement (le tracé aura changé sous les pieds du fantôme). Garde
# minimale côté appelant (main.gd) : comparer replay.track_uid à la piste
# chargée, ignorer avec un avertissement si différent. Un vrai correctif
# attend une révision de piste dans TrackData, hors scope ici.
class_name ReplayData
extends Resource

@export var format_version: int = 1

@export var track_uid: String = ""
@export var vehicle_id: String = ""
@export var finish_ms: int = 0
@export var date: String = ""

# Hash déterministe de l'état final (CarState.compute_hash()) — sert à
# valider qu'un rejeu du log ci-dessous reproduit exactement le même
# résultat (voir main.gd, contre-rejeu de validation à l'arrivée).
@export var hash_final: int = 0

# Index du premier tick où le chrono du joueur a démarré (RaceState.started,
# voir sim/race_state.gd) — le fantôme déroule silencieusement les ticks
# [0, start_tick) avant la course pour rester aligné sur le chrono, plutôt
# que de rejouer son propre temps d'attente initial en même temps que celui
# du joueur (voir main.gd).
@export var start_tick: int = 0

# Un octet par tick, dans l'ordre d'enregistrement. accel/frein/derapage :
# le cran brut (InputCrans.QUANT_UNI, [0, 255]). braquage : décalé de
# +InputCrans.BIAIS_BRAQUAGE pour tenir dans un octet non signé — voir
# InputCrans.bi_to_octet()/octet_to_bi().
@export var accel_crans: PackedByteArray = PackedByteArray()
@export var frein_crans: PackedByteArray = PackedByteArray()
@export var braquage_crans: PackedByteArray = PackedByteArray()
@export var derapage_crans: PackedByteArray = PackedByteArray()

func tick_count() -> int:
	return accel_crans.size()

# Tolérant aux fichiers corrompus/tronqués (même discipline que Controls/
# Leaderboard) : un replay incohérent doit être ignoré par l'appelant,
# jamais planter en pleine course.
func est_coherent() -> bool:
	var n: int = tick_count()
	if n <= 0:
		return false
	if frein_crans.size() != n or braquage_crans.size() != n or derapage_crans.size() != n:
		return false
	if start_tick < 0 or start_tick > n:
		return false
	return true

# Décode le tick `index` dans un InputFrame RÉUTILISÉ (zéro allocation) —
# `out` est fourni par l'appelant, jamais recréé ici. Vivre dans ReplayData
# (pas dans main.gd) rend le décodage testable sans scène.
func remplir_input(index: int, out: InputFrame) -> void:
	out.accel = InputCrans.cran_to_fixed_uni(accel_crans[index])
	out.frein = InputCrans.cran_to_fixed_uni(frein_crans[index])
	out.braquage = InputCrans.cran_to_fixed_bi(InputCrans.octet_to_bi(braquage_crans[index]))
	out.derapage = InputCrans.cran_to_fixed_uni(derapage_crans[index])
