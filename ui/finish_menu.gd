# Écran de fin de course (Rejouer / Quitter). Instancié caché par main.gd,
# jamais sa propre scène — même patron que ui/pause_menu.gd.
class_name FinishMenu
extends CanvasLayer

signal replayed
signal quit_requested
signal save_ghost_requested(replay_file: String)

var _title_label: Label
var _time_label: Label
var _record_label: Label
var _replay_button: Button
var _save_ghost_button: Button
var _replay_file: String = ""

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.75)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(260.0, 0.0)
	vbox.add_theme_constant_override("separation", 12)
	center.add_child(vbox)

	_title_label = Label.new()
	_title_label.text = "Course terminée"
	_title_label.add_theme_font_size_override("font_size", 32)
	vbox.add_child(_title_label)

	_time_label = Label.new()
	_time_label.add_theme_font_size_override("font_size", 24)
	vbox.add_child(_time_label)

	_record_label = Label.new()
	vbox.add_child(_record_label)

	_save_ghost_button = Button.new()
	_save_ghost_button.hide()
	_save_ghost_button.pressed.connect(_on_save_ghost_pressed)
	vbox.add_child(_save_ghost_button)

	_replay_button = Button.new()
	_replay_button.text = "Rejouer"
	_replay_button.pressed.connect(func() -> void: replayed.emit())
	vbox.add_child(_replay_button)

	var quit_button := Button.new()
	quit_button.text = "Quitter"
	quit_button.pressed.connect(func() -> void: quit_requested.emit())
	vbox.add_child(quit_button)

# time_ms : temps de ce run, en millisecondes (interpolé au sous-tick, voir
# sim/race_state.gd). is_new_record : true si ce run vient de battre (ou
# d'établir) le record. best_ms : meilleur temps enregistré après ce run
# (donc égal à time_ms si is_new_record). replay_file : nom du fichier
# sauvegardé par main.gd::_sauvegarder_replay() ("" si l'écriture a échoué).
func show_result(time_ms: int, is_new_record: bool, best_ms: int, replay_file: String) -> void:
	_title_label.text = "Course terminée"
	_time_label.text = "Temps : %s" % TimeFormat.format_ms(time_ms)
	_replay_file = replay_file
	if is_new_record:
		_record_label.text = "Nouveau record !"
	else:
		_record_label.text = "Record : %s" % TimeFormat.format_ms(best_ms)
	# Un nouveau record devient déjà le fantôme "mon record" automatiquement
	# à la tentative suivante (voir replay/ghost_resolver.gd) : ce bouton ne
	# sert qu'à garder volontairement un run qui n'en est pas un.
	_save_ghost_button.visible = not is_new_record and replay_file != ""
	_save_ghost_button.disabled = false
	_save_ghost_button.text = "Enregistrer ce fantôme"
	show()

# Limite de 30 minutes atteinte sans franchir la ligne d'arrivée : échec,
# rien n'est envoyé à ui/leaderboard.gd (donc aucun replay à proposer).
func show_timeout() -> void:
	_title_label.text = "Temps écoulé"
	_time_label.text = "Limite de %s atteinte" % TimeFormat.format_ms(RaceState.TIME_LIMIT_MS)
	_record_label.text = "Course non terminée"
	_replay_file = ""
	_save_ghost_button.hide()
	show()

func focus_first() -> void:
	_replay_button.grab_focus()

func _on_save_ghost_pressed() -> void:
	save_ghost_requested.emit(_replay_file)
	_save_ghost_button.disabled = true
	_save_ghost_button.text = "Fantôme enregistré"
