# Scène principale (application/run/main_scene). UI construite par code,
# comme le reste de ui/ et render/ dans ce projet. Structure alignée sur la
# maquette utilisateur (voir CLAUDE.md, section « Menus et remapping ») :
# aperçu 3D du véhicule sélectionné à gauche, liste de boutons à droite.
# Le choix du véhicule lui-même a déménagé dans ui/track_select.gd (bouton
# « Changer de véhicule ») : il n'y a plus de bouton Véhicule ici.
extends Control

const PREVIEW_SPIN_SPEED: float = 0.35  # rad/s, tourne-disque cosmétique
const BACKGROUND: Texture2D = preload("res://assets/ui/main_menu_background.png")

var _menu_root: VBoxContainer
var _preview_car: CarView
var _play_button: Button
var _settings: SettingsMenu
var _editor_menu: EditorMenu

func _ready() -> void:
	_build_ui()
	_play_button.grab_focus()

func _process(delta: float) -> void:
	if _preview_car != null:
		_preview_car.rotation.y += PREVIEW_SPIN_SPEED * delta

func _build_ui() -> void:
	var bg := TextureRect.new()
	bg.texture = BACKGROUND
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Léger voile commun pour garder le véhicule et les boutons lisibles sur
	# toutes les zones de la photo, sans masquer le garage demandé.
	var veil := ColorRect.new()
	veil.color = Color(0.02, 0.025, 0.035, 0.24)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(veil)

	var layout := HBoxContainer.new()
	layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(layout)

	_build_preview(layout)
	_build_menu(layout)

# Aperçu du véhicule sélectionné (VehicleSelection.selected_id, lu au
# _ready() de CarView) dans un SubViewport dédié — même modèle que la
# silhouette en jeu, juste isolé dans sa propre scène 3D miniature.
func _build_preview(layout: HBoxContainer) -> void:
	var container := SubViewportContainer.new()
	container.stretch = true
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(container)

	var viewport := SubViewport.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.own_world_3d = true  # isole ce monde 3D miniature de tout autre SubViewport
	viewport.transparent_bg = true
	container.add_child(viewport)

	var world_env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.0, 0.0, 0.0, 0.0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(1.0, 0.78, 0.58)
	environment.ambient_light_energy = 1.15
	world_env.environment = environment
	viewport.add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45.0, -30.0, 0.0)
	sun.light_color = Color(1.0, 0.82, 0.65)
	sun.light_energy = 1.4
	viewport.add_child(sun)

	var camera := Camera3D.new()
	viewport.add_child(camera)
	# look_at() lit global_transform : appelé avant add_child() sur un nœud
	# orphelin, il n'a aucun effet (la caméra garde son orientation par
	# défaut, -Z) — toujours ajouter au SceneTree avant de l'appeler.
	camera.position = Vector3(4.8, 2.25, 5.8)
	camera.look_at(Vector3(0.0, 0.65, 0.0), Vector3.UP)

	_preview_car = CarView.new()
	viewport.add_child(_preview_car)
	# CarView._process() interpole entre deux échantillons sample() pour le
	# rendu en jeu (voir render/car_view.gd) — ici il n'y a jamais de
	# sample(), donc rien à interpoler ; on désactive pour piloter la
	# rotation "tourne-disque" nous-mêmes sans que _process() l'écrase.
	_preview_car.set_process(false)

func _build_menu(layout: HBoxContainer) -> void:
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(390.0, 0.0)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.025, 0.03, 0.04, 0.88)
	panel_style.border_color = Color(0.92, 0.48, 0.16, 0.75)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(12)
	panel_style.content_margin_left = 34.0
	panel_style.content_margin_right = 34.0
	panel_style.content_margin_top = 30.0
	panel_style.content_margin_bottom = 30.0
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	_menu_root = VBoxContainer.new()
	_menu_root.custom_minimum_size = Vector2(320.0, 0.0)
	_menu_root.add_theme_constant_override("separation", 6)
	panel.add_child(_menu_root)

	var title := Label.new()
	title.text = "TIME TO VROOM"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(1.0, 0.67, 0.30))
	_menu_root.add_child(title)

	var spacer := Control.new()
	spacer.custom_minimum_size.y = 14.0
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_root.add_child(spacer)

	_play_button = _add_menu_button(_menu_root, "Jouer", _on_play_pressed)
	_add_disabled_button(_menu_root, "Multijoueur")
	_add_menu_button(_menu_root, "Créer une course", _on_editor_pressed)
	_add_menu_button(_menu_root, "Paramètres", _on_settings_pressed)
	_add_menu_button(_menu_root, "Quitter le jeu", _on_quit_pressed)

	_settings = SettingsMenu.new()
	_settings.hide()
	_settings.closed.connect(_on_settings_closed)
	add_child(_settings)

	_editor_menu = EditorMenu.new()
	_editor_menu.hide()
	_editor_menu.closed.connect(_on_editor_menu_closed)
	add_child(_editor_menu)

func _add_menu_button(parent: VBoxContainer, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0.0, 48.0)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

# Fonctionnalités définies plus tard (voir CLAUDE.md, « Ce qu'il ne faut pas
# faire » : pas de site/backend avant que le jeu soit bon hors ligne) —
# présent dans la mise en page, désactivé, comme le bouton "Publier" de
# l'éditeur de piste.
func _add_disabled_button(parent: VBoxContainer, text: String) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0.0, 48.0)
	button.disabled = true
	button.tooltip_text = "Bientôt disponible"
	parent.add_child(button)

func _on_play_pressed() -> void:
	get_tree().change_scene_to_file("res://ui/track_select.tscn")

func _on_editor_pressed() -> void:
	_menu_root.hide()
	_editor_menu.show()
	_editor_menu.focus_first()

func _on_editor_menu_closed() -> void:
	_editor_menu.hide()
	_menu_root.show()
	_play_button.grab_focus()

func _on_settings_pressed() -> void:
	_menu_root.hide()
	_settings.show()
	_settings.focus_first()

func _on_settings_closed() -> void:
	_settings.hide()
	_menu_root.show()
	_play_button.grab_focus()

func _on_quit_pressed() -> void:
	get_tree().quit()
