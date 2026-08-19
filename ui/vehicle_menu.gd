# Menu déroulant de choix du véhicule, ancré juste au-dessus du bouton
# "Changer de véhicule" de ui/track_select.gd (seul appelant) — remplace
# l'ancien overlay plein écran sur demande explicite (maquette utilisateur) :
# le reste de l'écran (leaderboard, aperçu, liste des pistes) reste visible
# derrière, aucun assombrissement. Cliquer un véhicule sélectionne ET ferme
# (comportement dropdown) ; cliquer ailleurs sur l'écran ou Échap ferme sans
# rien changer.
class_name VehicleMenu
extends Control

signal closed

var _rows_container: VBoxContainer
var _panel: PanelContainer
var _anchor_button: Button = null
var _buttons_by_id: Dictionary = {}  # vehicle id -> Button, reconstruit à chaque _refresh()

func _ready() -> void:
	_build_ui()

# À appeler avant .show() — mémorise le bouton au-dessus duquel s'ancrer. Le
# positionnement réel se fait dans focus_first(), une fois affiché : même
# piège que ui/ghost_menu.gd (voir CLAUDE.md, piège PRESET_FULL_RECT) — un
# Control cette taille/position calculée avant d'être affiché ne se
# recalcule pas tout seul plus tard.
func open_above(button: Button) -> void:
	_anchor_button = button

func focus_first() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size
	_refresh()
	_position_panel()
	# Focus sur le véhicule RÉELLEMENT sélectionné, pas sur la première ligne
	# (Roadster) — sinon l'anneau de focus clavier de Godot (toujours visible
	# sur la ligne focus, indépendant du texte vert ci-dessous) restait figé
	# sur Roadster à chaque ouverture, en contradiction avec la sélection
	# réelle affichée par un autre véhicule en vert.
	var current: Button = _buttons_by_id.get(VehicleSelection.selected_id)
	if current != null:
		current.grab_focus()

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Capte les clics n'importe où sur l'écran pour fermer le menu — sans
	# assombrir (pas de ColorRect ici, contrairement aux overlays plein
	# écran comme ui/ghost_menu.gd) : le reste de l'écran doit rester net.
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_background_input)

	_panel = PanelContainer.new()
	# mouse_filter par défaut (STOP) : un clic sur le panneau ne doit pas
	# aussi déclencher _on_background_input() (fermeture) — comportement de
	# base de Godot pour des Control imbriqués, pas besoin de le forcer.
	add_child(_panel)

	_rows_container = VBoxContainer.new()
	_rows_container.add_theme_constant_override("separation", 0)
	_panel.add_child(_rows_container)

# Position/taille calculées directement sur le bouton ancre et le viewport —
# jamais via des ancrages Godot (voir le piège documenté dans CLAUDE.md).
func _position_panel() -> void:
	if _anchor_button == null:
		return
	var btn_pos: Vector2 = _anchor_button.global_position
	var btn_size: Vector2 = _anchor_button.size
	var panel_height: float = _panel.get_combined_minimum_size().y
	_panel.size = Vector2(btn_size.x, panel_height)
	_panel.position = Vector2(btn_pos.x, btn_pos.y - panel_height)

func _on_background_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		closed.emit()

# Échap ferme ce panneau, même convention que partout ailleurs dans le jeu
# (voir ui/editor_menu.gd, ui/settings_menu.gd, ui/ghost_menu.gd,
# ui/track_select.gd) même si ce n'est pas un écran "Retour" à proprement
# parler. Le garde `visible` est nécessaire : ce nœud reste dans l'arbre
# (show()/hide()) même caché.
func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		closed.emit()
		get_viewport().set_input_as_handled()

func _refresh() -> void:
	# remove_child() AVANT queue_free(), pas juste queue_free() seul : ce
	# dernier diffère la suppression réelle à la fin du frame, donc
	# _position_panel() (appelée juste après _refresh()) mesurerait encore
	# les anciennes lignes EN PLUS des nouvelles — hauteur calculée trop
	# grande, un espace vide restait sous "Halcyon" (bug constaté : correct
	# à la première ouverture, décalé aux suivantes, quand il y a vraiment
	# d'anciennes lignes à nettoyer). Même piège déjà rencontré et corrigé
	# pour la CarView du fantôme dans main.gd::_liberer_fantome().
	for child in _rows_container.get_children():
		_rows_container.remove_child(child)
		child.queue_free()
	_buttons_by_id.clear()

	for i in range(VehicleRoster.VEHICLES.size()):
		var entry: Dictionary = VehicleRoster.VEHICLES[i]
		if i > 0:
			_rows_container.add_child(HSeparator.new())

		var button := Button.new()
		button.text = entry["nom"]
		button.custom_minimum_size = Vector2(0.0, 48.0)
		button.pressed.connect(_on_vehicle_pressed.bind(entry["id"]))
		_rows_container.add_child(button)
		_buttons_by_id[entry["id"]] = button

func _on_vehicle_pressed(id: String) -> void:
	VehicleSelection.select(id)
	closed.emit()
