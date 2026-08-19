# Assemble simulation et rendu. La simulation avance uniquement dans
# _physics_process (cadence fixe Horloge.TICKS_PAR_SECONDE, cf.
# project.godot) ; le rendu interpole dans _process via res://render/car_view.gd.
extends Node3D

# Une seule réallocation par minute de course pour les tampons
# d'enregistrement (voir _enregistrer()) — pas de append() par tick (zéro
# allocation en régime établi, cf. CLAUDE.md règle 4 ; techniquement hors de
# sim/, mais on applique la même discipline ici, c'est le chemin chaud du jeu).
const REC_CHUNK: int = 6000  # 60 s à 100 Hz
# Garde-fou du contre-rejeu de validation post-arrivée : au-delà, un run de
# 30 minutes gèlerait l'écran de fin le temps de tout rejouer. Le contre-
# rejeu reste un signal de debug/intégrité, jamais un blocage dur pour ce
# premier lot (voir _valider_replay()).
const VALIDATION_MAX_TICKS: int = 60000
const VALIDER_APRES_RUN: bool = true

# Identifiant piste pour ui/leaderboard.gd. TrackCatalog.BUILTIN_UID par
# défaut ; si une piste créée dans l'éditeur est chargée (voir _load_track
# ci-dessous), on dérive l'ID de son TrackData.uid (stable, généré une seule
# fois par ensure_uid() — voir map/track_data.gd) pour ne pas mélanger ses
# temps avec ceux de la piste codée en dur, ni les perdre si le fichier est
# renommé. Le véhicule vient du choix persisté par ui/vehicle_selection.gd
# (tous les véhicules partagent encore le même CarConfig, voir CLAUDE.md).
var _track_id: String = TrackCatalog.BUILTIN_UID

var _world: World = World.new()
var _input: InputFrame = InputFrame.new()  # réutilisé, jamais recréé par tick
var _track: Track
var _config: CarConfig
var _start: PackedInt64Array
var _elements: Array[Dictionary] = []  # purement affichage (render/track_elements_view.gd), voir _load_track()

var _car_view: CarView
var _camera: ChaseCamera
var _hud: Hud
var _pause_menu: PauseMenu
var _finish_menu: FinishMenu
var _paused: bool = false
var _run_over: bool = false  # course terminée OU temps écoulé

# --- Enregistrement du replay (voir replay/replay_data.gd) ---
# Log complet depuis le tick 0 de la scène (PAS depuis le premier input
# actif) : nécessaire pour qu'un fantôme rejoué plus tard puisse se
# pré-rouler jusqu'au même point de départ de chrono que l'original
# (voir _reset_ghost()).
var _rec_accel: PackedByteArray = PackedByteArray()
var _rec_frein: PackedByteArray = PackedByteArray()
var _rec_braquage: PackedByteArray = PackedByteArray()
var _rec_derapage: PackedByteArray = PackedByteArray()
var _rec_count: int = 0
var _rec_start_tick: int = -1  # index du tick où race_state.started est devenu vrai, -1 = pas encore

# --- Lecture d'un fantôme (second World, indépendant, tické en lockstep) ---
# _ghost_file mémorise le fichier actuellement chargé : la sélection
# (ui/ghost_selection.gd) est re-résolue à CHAQUE tentative (voir
# _resoudre_fantome()), mais s'il pointe toujours vers le même fichier
# (cas courant : "Rejouer" sans avoir battu son record), rien n'est
# reconstruit.
var _ghost_file: String = ""
var _ghost_replay: ReplayData = null
var _ghost_world: World = null
var _ghost_view: CarView = null
var _ghost_input: InputFrame = InputFrame.new()  # réutilisé, jamais recréé par tick
var _ghost_index: int = 0

func _ready() -> void:
	_load_track()
	_config = CarConfig.charger(VehicleSelection.selected_id)

	var track_mesh := TrackMesh.new()
	track_mesh.build(_track)
	add_child(track_mesh)

	var elements_view := TrackElementsView.new()
	elements_view.build(_elements)
	add_child(elements_view)

	_car_view = CarView.new()
	add_child(_car_view)

	_camera = ChaseCamera.new()
	add_child(_camera)
	_camera.current = true

	_hud = Hud.new()
	add_child(_hud)

	_pause_menu = PauseMenu.new()
	_pause_menu.hide()
	_pause_menu.resumed.connect(_on_pause_resumed)
	_pause_menu.restarted.connect(_on_pause_restarted)
	_pause_menu.quit_requested.connect(_on_pause_quit)
	add_child(_pause_menu)

	_finish_menu = FinishMenu.new()
	_finish_menu.hide()
	_finish_menu.replayed.connect(_on_finish_replayed)
	_finish_menu.quit_requested.connect(_on_pause_quit)
	_finish_menu.save_ghost_requested.connect(_on_save_ghost_requested)
	add_child(_finish_menu)

	_reset_run()
	_camera.set_target(_car_view)

# Charge la piste posée par editor/track_editor.gd via l'autoload Session
# ("Jouer cette piste"), sinon retombe sur le circuit codé en dur (flux
# normal depuis "Jouer" dans le menu principal).
func _load_track() -> void:
	if Session.pending_track_path != "":
		var path: String = Session.pending_track_path
		Session.pending_track_path = ""
		var data: TrackData = TrackData.load_from_path(path)
		if data != null and data.point_count() >= 2:
			_track = data.to_track()
			_start = data.start_transform()
			_track_id = data.uid
			_elements = data.elements
			return

	_track = TrackHardcoded.build()
	_start = TrackHardcoded.start_transform()
	_track_id = TrackCatalog.BUILTIN_UID
	_elements = []  # la piste intégrée n'a pas d'éléments posés

# Résout la sélection courante (ui/ghost_selection.gd) vers un fichier de
# replay et reconstruit le fantôme SEULEMENT si ce fichier a changé depuis la
# dernière tentative — appelée à chaque _reset_ghost(), donc à chaque
# "Rejouer"/raccourci "reinitialiser"/redémarrage depuis la pause. C'est ce
# court-circuit qui permet d'enchaîner les tentatives sans repasser par un
# menu : en mode PERSO, battre son record change le fichier résolu, donc la
# tentative suivante reconstruit automatiquement le fantôme sur ce nouveau
# record ; sans record battu, le fichier ne change pas et rien n'est relu.
#
# Touche le disque (ReplayStore.load_file) : volontairement cantonné à cet
# appel de reset, jamais à _physics_process (règle non négociable n°4, zéro
# allocation dans la boucle de simulation).
func _resoudre_fantome() -> void:
	# GhostSelection ne fait que du stockage (pas de dépendance à un autre
	# autoload, voir son en-tête) : l'orchestration Leaderboard + VehicleSelection
	# + GhostResolver vit ici, pas dans l'autoload.
	var file: String = GhostResolver.resolve(
		GhostSelection.selection(_track_id), Leaderboard.runs(_track_id),
		VehicleSelection.selected_id, []
	)
	if file == _ghost_file:
		return
	_ghost_file = file
	_liberer_fantome()
	if file == "":
		return

	var replay: ReplayData = ReplayStore.load_file(file)
	if replay == null:
		return
	# Garde minimale contre une piste modifiée depuis (TrackData n'a pas de
	# numéro de révision, voir replay/replay_data.gd) : un replay dont la
	# piste ne correspond plus est ignoré plutôt que rejoué désynchronisé.
	if replay.track_uid != _track_id:
		push_warning("main.gd: replay %s ne correspond pas à la piste chargée, fantôme ignoré" % file)
		return

	_ghost_replay = replay
	_ghost_world = World.new()
	_ghost_view = CarView.new()
	# Réglés AVANT add_child() : CarView._ready() les lit une seule fois.
	_ghost_view.vehicle_id_override = replay.vehicle_id
	_ghost_view.alpha = 0.45
	add_child(_ghost_view)

# Détruit le fantôme actuellement chargé (véhicule différent résolu, ou plus
# aucun fantôme sélectionné). _camera ne vise jamais _ghost_view (elle suit
# _car_view, le véhicule du joueur — voir _ready()), donc aucune référence
# pendante côté caméra. remove_child() AVANT queue_free() est nécessaire, pas
# juste prudent : queue_free() diffère la destruction à la fin du frame, donc
# sans ce retrait immédiat de l'arbre, l'ancienne CarView continuerait à être
# rendue (silhouette figée) pendant le même frame où la nouvelle apparaît.
func _liberer_fantome() -> void:
	_ghost_replay = null
	_ghost_world = null
	if _ghost_view != null:
		remove_child(_ghost_view)
		_ghost_view.queue_free()
		_ghost_view = null

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _run_over:
		# Course terminée/temps écoulé : FinishMenu est déjà affiché, la pause
		# n'a pas de sens par-dessus (bug corrigé : Échap ouvrait le panneau
		# pause DERRIÈRE l'écran de fin). Échap ici équivaut à "Quitter".
		_on_pause_quit()
	else:
		_set_paused(not _paused)

func _set_paused(paused: bool) -> void:
	_paused = paused
	_pause_menu.visible = _paused
	if _paused:
		_pause_menu.focus_first()

func _on_pause_resumed() -> void:
	_set_paused(false)

func _on_pause_restarted() -> void:
	_set_paused(false)
	_reset_run()

# Partagé par PauseMenu.quit_requested et FinishMenu.quit_requested : "Quitter"
# ramène à l'écran de sélection de piste, pas au menu principal — on vient
# d'y choisir cette piste, c'est là qu'on veut revenir.
func _on_pause_quit() -> void:
	get_tree().change_scene_to_file("res://ui/track_select.tscn")

func _on_finish_replayed() -> void:
	_reset_run()

# "Enregistrer ce fantôme" de ui/finish_menu.gd — un run qui n'est PAS un
# nouveau record ne remplace rien automatiquement (voir _resoudre_fantome()),
# donc sans ce bouton il resterait introuvable ailleurs que dans l'historique
# brut du leaderboard.
func _on_save_ghost_requested(replay_file: String) -> void:
	Leaderboard.set_pinned(_track_id, replay_file, true)

func _reset_run() -> void:
	# _start est déjà en Q16.16 (voir TrackData.start_transform() et
	# TrackHardcoded.start_transform(), même contrat) : pas de Fixed.from_int()
	# ici, sans quoi une piste TrackData dont le point de départ n'est pas à
	# l'origine apparaîtrait à une position multipliée par 65536 (bug réel
	# rencontré, invisible sur TrackHardcoded seulement parce que ses valeurs
	# sont à zéro).
	_world.setup(
		_track, _config,
		int(_start[0]), int(_start[1]), int(_start[2]),
		int(_start[3])
	)
	_car_view.sample(_world.car_state)
	_car_view.sample(_world.car_state)  # deux échantillons identiques : pas de lerp parasite au premier rendu
	_run_over = false
	_finish_menu.hide()
	_rec_count = 0
	_rec_start_tick = -1
	_reset_ghost()

# Réinitialise le fantôme en même temps que le joueur (redémarrage manuel ou
# raccourci) : sinon il continuerait sa course précédente pendant que le
# joueur repart de zéro. Résout d'abord la sélection courante (voir
# _resoudre_fantome() — c'est ce qui permet à un nouveau record de remplacer
# automatiquement le fantôme d'une tentative à l'autre), puis pré-roule
# silencieusement jusqu'à replay.start_tick (le tick où le CHRONO ORIGINAL du
# fantôme avait démarré) pour rester aligné sur le "zéro" du joueur — voir le
# contexte du plan de ce lot : sans ce pré-roulement, le temps d'attente
# initial du fantôme (potentiellement plusieurs secondes) se cumule avec
# celui du joueur et les deux véhicules dérivent l'un par rapport à l'autre.
func _reset_ghost() -> void:
	_resoudre_fantome()
	if _ghost_replay == null:
		return
	_ghost_world.setup(
		_track, CarConfig.charger(_ghost_replay.vehicle_id),
		int(_start[0]), int(_start[1]), int(_start[2]),
		int(_start[3])
	)
	_ghost_index = 0
	# echantillonner=false : le pré-roulement peut représenter plusieurs
	# secondes de ticks, échantillonner à chacun ne servirait qu'à être
	# aussitôt écrasé par l'échantillon suivant. Le double sample() ci-dessous,
	# APRÈS la boucle (pas avant, piège trouvé en revue : ici il ne serait
	# écrasé par aucun sample() ultérieur), fournit l'anti-lerp pour le
	# premier vrai rendu.
	while _ghost_index < _ghost_replay.start_tick:
		_tick_ghost_frame(false)
	_ghost_view.sample(_ghost_world.car_state)
	_ghost_view.sample(_ghost_world.car_state)  # même anti-lerp que le joueur

func _physics_process(_delta: float) -> void:
	if _paused:
		return

	# Doit fonctionner même course terminée (_run_over) : vérifié AVANT ce
	# garde, pas après — sinon le raccourci clavier/manette ne redémarrait
	# jamais une fois arrivé ou le temps écoulé, contrairement au bouton
	# "Rejouer" de FinishMenu qui, lui, passe par _on_finish_replayed().
	if Input.is_action_just_pressed("reinitialiser"):
		_reset_run()
		return

	if _run_over:
		return

	var cran_accel: int = InputCrans.uni_to_cran(Input.get_action_strength("accelerer"))
	var cran_frein: int = InputCrans.uni_to_cran(Input.get_action_strength("freiner"))
	# Inversé par rapport à l'intuition (droite - gauche) : la caméra de
	# poursuite (render/chase_camera.gd) regarde vers +Z, et avec un "haut"
	# +Y, le vecteur "droite" que Godot calcule pour elle (produit vectoriel
	# avant x haut) pointe vers -X — alors que sim/car_sim.gd fait tourner un
	# braquage positif vers +X. Sans cette inversion, la touche droite fait
	# visuellement tourner la voiture à gauche à l'écran, et inversement.
	var steer_raw: float = Input.get_action_strength("gauche") - Input.get_action_strength("droite")
	var cran_braquage: int = InputCrans.bi_to_cran(steer_raw)
	var cran_derapage: int = InputCrans.uni_to_cran(Input.get_action_strength("derapage"))

	_input.accel = InputCrans.cran_to_fixed_uni(cran_accel)
	_input.frein = InputCrans.cran_to_fixed_uni(cran_frein)
	_input.braquage = InputCrans.cran_to_fixed_bi(cran_braquage)
	_input.derapage = InputCrans.cran_to_fixed_uni(cran_derapage)

	_enregistrer(cran_accel, cran_frein, cran_braquage, cran_derapage)

	_world.tick(_input)
	_car_view.sample(_world.car_state)
	if _rec_start_tick < 0 and _world.race_state.started:
		_rec_start_tick = _rec_count - 1
	_tick_ghost()
	_hud.update(_world.car_state, _world.race_state.current_elapsed)

	if _world.race_state.finished:
		_run_over = true
		var finish_ms: int = _world.race_state.finish_ms
		var vehicle_id: String = VehicleSelection.selected_id
		var hash_final: int = _world.state_hash()
		var replay_file: String = _sauvegarder_replay(finish_ms, vehicle_id, hash_final)
		var is_record: bool = Leaderboard.submit_time(_track_id, vehicle_id, finish_ms, replay_file, hash_final)
		var best: int = Leaderboard.best_time_ms(_track_id, vehicle_id)
		_finish_menu.show_result(finish_ms, is_record, best, replay_file)
		_finish_menu.focus_first()
	elif _world.race_state.timed_out:
		_run_over = true
		_finish_menu.show_timeout()
		_finish_menu.focus_first()

# Écrit un cran par tampon, en croissant par blocs de REC_CHUNK plutôt que
# par append() (voir la constante). braquage est décalé en octet non signé
# ici (InputCrans.bi_to_octet) : c'est la représentation stockée dans
# ReplayData, pas le cran signé brut.
func _enregistrer(cran_accel: int, cran_frein: int, cran_braquage: int, cran_derapage: int) -> void:
	if _rec_count == _rec_accel.size():
		var nouvelle_taille: int = _rec_count + REC_CHUNK
		_rec_accel.resize(nouvelle_taille)
		_rec_frein.resize(nouvelle_taille)
		_rec_braquage.resize(nouvelle_taille)
		_rec_derapage.resize(nouvelle_taille)
	_rec_accel[_rec_count] = cran_accel
	_rec_frein[_rec_count] = cran_frein
	_rec_braquage[_rec_count] = InputCrans.bi_to_octet(cran_braquage)
	_rec_derapage[_rec_count] = cran_derapage
	_rec_count += 1

# Construit et sauvegarde le ReplayData de ce run. Renvoie le nom de fichier
# ("" si la sauvegarde a échoué — ne bloque jamais l'écran de fin).
func _sauvegarder_replay(finish_ms: int, vehicle_id: String, hash_final: int) -> String:
	var replay := ReplayData.new()
	replay.track_uid = _track_id
	replay.vehicle_id = vehicle_id
	replay.finish_ms = finish_ms
	replay.date = Time.get_datetime_string_from_system()
	replay.hash_final = hash_final
	replay.start_tick = maxi(_rec_start_tick, 0)
	replay.accel_crans = _rec_accel.slice(0, _rec_count)
	replay.frein_crans = _rec_frein.slice(0, _rec_count)
	replay.braquage_crans = _rec_braquage.slice(0, _rec_count)
	replay.derapage_crans = _rec_derapage.slice(0, _rec_count)

	var file: String = ReplayStore.save(replay)
	if file != "" and VALIDER_APRES_RUN:
		_valider_replay(replay)
	return file

# Contre-rejeu de validation : rejoue le replay qu'on vient d'enregistrer
# dans un World jetable et compare le hash final. Signal de debug/intégrité
# uniquement pour ce premier lot — un désaccord indiquerait un bug de
# déterminisme, mais ne bloque jamais la soumission au leaderboard (voir
# CLAUDE.md, la validation des replays est le fondement du système, donc ce
# contre-rejeu vaut la peine d'exister même sans action bloquante pour
# l'instant).
func _valider_replay(replay: ReplayData) -> void:
	if replay.tick_count() > VALIDATION_MAX_TICKS:
		return
	var world_test := World.new()
	var config_test: CarConfig = CarConfig.charger(replay.vehicle_id)
	world_test.setup(_track, config_test, int(_start[0]), int(_start[1]), int(_start[2]), int(_start[3]))
	var input_test := InputFrame.new()
	for i in range(replay.tick_count()):
		replay.remplir_input(i, input_test)
		world_test.tick(input_test)
	if world_test.state_hash() != replay.hash_final:
		push_warning("main.gd: contre-rejeu du replay ne correspond pas au hash enregistré (déterminisme suspect)")

# Avance le fantôme d'un tick, une fois le chrono du JOUEUR démarré (sinon
# le fantôme resterait figé sur son point de départ pendant que le joueur
# poireaute avant son premier input — mais si le joueur agit tout de suite,
# les deux démarrent ensemble). Ne fait rien si aucun fantôme n'est chargé.
func _tick_ghost() -> void:
	if _ghost_replay == null or not _world.race_state.started:
		return
	_tick_ghost_frame()

# Un seul tick du monde fantôme — utilisé aussi bien par le pré-roulement
# silencieux (_reset_ghost(), echantillonner=false) que par _tick_ghost() en
# cours de course (echantillonner=true, défaut). S'arrête tout seul une fois
# le log épuisé (fige la dernière pose), jamais d'erreur.
func _tick_ghost_frame(echantillonner: bool = true) -> void:
	if _ghost_index >= _ghost_replay.tick_count():
		return
	_ghost_replay.remplir_input(_ghost_index, _ghost_input)
	_ghost_world.tick(_ghost_input)
	_ghost_index += 1
	if echantillonner:
		_ghost_view.sample(_ghost_world.car_state)
