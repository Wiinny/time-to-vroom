extends Control

var _root_layout: VBoxContainer
var _search_edit: LineEdit

var _leaderboard_list: VBoxContainer

var _preview_viewport: SubViewport
var _preview_camera: Camera3D
var _preview_mesh: MeshInstance3D
var _personal_best_label: Label

var _track_list: VBoxContainer
var _track_button_group: ButtonGroup
var _track_row_by_uid: Dictionary = {} 
var _group_option: OptionButton
var _expanded_collection: String = ""  

enum GroupMode {
	TOUTES, COLLECTIONS, CREATEUR, DATE_AJOUT, DATE_CREATION, DIFFICULTE,
	DUREE, VEHICULE, NOTE, TITRE, MES_PISTES, RECEMMENT_JOUEES,
}
var _group_mode: int = GroupMode.TOUTES

var _vehicle_menu: VehicleMenu
var _collections_menu: CollectionsMenu
var _ghost_menu: GhostMenu
var _play_button: Button
var _ghost_button: Button
var _vehicle_button: Button

var _all_tracks: Array[Dictionary] = []
var _selected: Dictionary = {} 

func _ready() -> void:
	_build_ui()
	_all_tracks = TrackCatalog.list_tracks()
	_refresh_catalog()
	if not _selected.is_empty() and _track_row_by_uid.has(_selected["uid"]):
		(_track_row_by_uid[_selected["uid"]] as Button).grab_focus()

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_track_button_group = ButtonGroup.new()

	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.08)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_root_layout = VBoxContainer.new()
	_root_layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root_layout.add_theme_constant_override("separation", 10)
	add_child(_root_layout)

	_build_top_bar(_root_layout)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	_root_layout.add_child(body)

	_build_leaderboard_column(body)
	_build_preview_column(body)
	_build_track_list_column(body)

	_build_bottom_bar(_root_layout)

	_vehicle_menu = VehicleMenu.new()
	_vehicle_menu.hide()
	_vehicle_menu.closed.connect(_on_vehicle_menu_closed)
	add_child(_vehicle_menu)

	_collections_menu = CollectionsMenu.new()
	_collections_menu.hide()
	_collections_menu.closed.connect(_on_collections_menu_closed)
	add_child(_collections_menu)

	_ghost_menu = GhostMenu.new()
	_ghost_menu.hide()
	_ghost_menu.closed.connect(_on_ghost_menu_closed)
	add_child(_ghost_menu)


func _build_top_bar(parent: VBoxContainer) -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 16)
	parent.add_child(bar)

	var profile := HBoxContainer.new()
	profile.add_theme_constant_override("separation", 8)
	bar.add_child(profile)

	var avatar := ColorRect.new()
	avatar.color = Color(0.3, 0.3, 0.35)
	avatar.custom_minimum_size = Vector2(48.0, 48.0)
	profile.add_child(avatar)

	var profile_labels := VBoxContainer.new()
	profile.add_child(profile_labels)

	var profile_title := Label.new()
	profile_title.text = "Profil Joueur"
	profile_title.add_theme_font_size_override("font_size", 16)
	profile_labels.add_child(profile_title)

	var profile_sub := Label.new()
	profile_sub.text = "(défini plus tard)"
	profile_sub.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	profile_labels.add_child(profile_sub)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(spacer)

	var search_label := Label.new()
	search_label.text = "Rechercher :"
	bar.add_child(search_label)

	_search_edit = LineEdit.new()
	_search_edit.custom_minimum_size = Vector2(220.0, 0.0)
	_search_edit.text_changed.connect(_on_search_changed)
	bar.add_child(_search_edit)

	var group_label := Label.new()
	group_label.text = "Regrouper par :"
	bar.add_child(group_label)

	_group_option = OptionButton.new()
	_group_option.fit_to_longest_item = false
	_group_option.clip_text = true
	_group_option.custom_minimum_size = Vector2(200.0, 0.0)
	_group_option.add_item("Toutes les pistes")
	_group_option.add_item("Collections")
	_group_option.add_item("Par créateur")
	_group_option.add_item("Par date d'ajout")
	_group_option.add_item("Par date de création (bientôt disponible)")
	_group_option.set_item_disabled(GroupMode.DATE_CREATION, true)
	_group_option.add_item("Par difficulté (bientôt disponible)")
	_group_option.set_item_disabled(GroupMode.DIFFICULTE, true)
	_group_option.add_item("Par durée")
	_group_option.add_item("Par véhicule")
	_group_option.add_item("Par note reçue (bientôt disponible)")
	_group_option.set_item_disabled(GroupMode.NOTE, true)
	_group_option.add_item("Par titre")
	_group_option.add_item("Mes pistes")
	_group_option.add_item("Pistes récemment jouées")
	_group_option.item_selected.connect(_on_group_changed)
	bar.add_child(_group_option)


func _build_leaderboard_column(parent: HBoxContainer) -> void:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(360.0, 0.0)
	col.add_theme_constant_override("separation", 8)
	parent.add_child(col)

	var mode := OptionButton.new()
	mode.fit_to_longest_item = false
	mode.clip_text = true
	mode.custom_minimum_size = Vector2(200.0, 0.0)
	mode.add_item("Leaderboard local")
	mode.add_item("Leaderboard mondial (bientôt disponible)")
	mode.set_item_disabled(1, true)
	mode.add_item("Leaderboard national (bientôt disponible)")
	mode.set_item_disabled(2, true)
	mode.add_item("Leaderboard amis (bientôt disponible)")
	mode.set_item_disabled(3, true)
	mode.select(0)
	col.add_child(mode)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)

	_leaderboard_list = VBoxContainer.new()
	_leaderboard_list.add_theme_constant_override("separation", 4)
	_leaderboard_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_leaderboard_list)

func _refresh_leaderboard() -> void:
	for child in _leaderboard_list.get_children():
		child.queue_free()

	if _selected.is_empty():
		return

	var entries: Array[Dictionary] = Leaderboard.runs(_selected["uid"])
	if entries.is_empty():
		var empty := Label.new()
		empty.text = "Aucun temps sur cette piste"
		empty.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		_leaderboard_list.add_child(empty)
		return

	var top: Array[Dictionary] = entries.slice(0, mini(10, entries.size()))
	for i in range(top.size()):
		_leaderboard_list.add_child(_build_run_row(i + 1, top[i]))

func _build_run_row(rank: int, entry: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var rank_label := Label.new()
	rank_label.text = "%d" % rank
	rank_label.custom_minimum_size = Vector2(22.0, 0.0)
	row.add_child(rank_label)

	var vehicle: Dictionary = VehicleRoster.find(entry.get("vehicule", ""))
	var dot := ColorRect.new()
	dot.color = vehicle.get("couleur", Color(0.5, 0.5, 0.5))
	dot.custom_minimum_size = Vector2(14.0, 14.0)
	row.add_child(dot)

	var label := Label.new()
	label.text = "Vous — %s — Temps : %s" % [vehicle.get("nom", "?"), TimeFormat.format_ms(int(entry["ms"]))]
	row.add_child(label)

	return row


func _build_preview_column(parent: HBoxContainer) -> void:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(380.0, 0.0)
	col.add_theme_constant_override("separation", 8)
	parent.add_child(col)

	var viewport_container := SubViewportContainer.new()
	viewport_container.stretch = true
	viewport_container.custom_minimum_size = Vector2(380.0, 240.0)
	col.add_child(viewport_container)

	_preview_viewport = SubViewport.new()
	_preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_preview_viewport.own_world_3d = true 
	viewport_container.add_child(_preview_viewport)

	var world_env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.5, 0.7, 0.9)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(1, 1, 1)
	environment.ambient_light_energy = 0.7
	world_env.environment = environment
	_preview_viewport.add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60.0, -30.0, 0.0)
	_preview_viewport.add_child(sun)

	_preview_camera = Camera3D.new()
	_preview_viewport.add_child(_preview_camera)

	var pb_title := Label.new()
	pb_title.text = "Votre record personnel"
	pb_title.add_theme_font_size_override("font_size", 18)
	col.add_child(pb_title)

	_personal_best_label = Label.new()
	col.add_child(_personal_best_label)

func _refresh_preview() -> void:
	if _preview_mesh != null:
		_preview_mesh.queue_free()
		_preview_mesh = null

	if _selected.is_empty():
		return

	var track: Track = _track_for_selection(_selected)
	if track == null:
		return

	_preview_mesh = TrackMesh.new()
	_preview_mesh.build(track)
	_preview_viewport.add_child(_preview_mesh)
	_frame_track(_preview_camera, track)

func _track_for_selection(entry: Dictionary) -> Track:
	if entry.get("builtin", false):
		return TrackCatalog.build_builtin(entry.get("uid", TrackCatalog.BUILTIN_UID))
	var data: TrackData = TrackData.load_from_path(entry["path"])
	return data.to_track() if data != null else null

func _frame_track(camera: Camera3D, track: Track) -> void:
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	var n: int = track.point_count()
	if n == 0:
		camera.size = 60.0
		camera.position = Vector3(0.0, 40.0, 30.0)
		camera.look_at(Vector3.ZERO, Vector3.UP)
		return

	var min_x: float = INF
	var max_x: float = -INF
	var min_z: float = INF
	var max_z: float = -INF
	for i in range(n):
		var x: float = Fixed.to_float(track.point_x[i])
		var z: float = Fixed.to_float(track.point_z[i])
		min_x = minf(min_x, x)
		max_x = maxf(max_x, x)
		min_z = minf(min_z, z)
		max_z = maxf(max_z, z)

	var cx: float = (min_x + max_x) * 0.5
	var cz: float = (min_z + max_z) * 0.5
	var extent: float = maxf(max_x - min_x, max_z - min_z) * 0.65 + 10.0

	camera.size = extent
	camera.position = Vector3(cx, extent, cz + extent * 0.5)
	camera.look_at(Vector3(cx, 0.0, cz), Vector3.UP)

func _refresh_personal_best() -> void:
	if _selected.is_empty():
		_personal_best_label.text = ""
		return

	var vehicle_id: String = VehicleSelection.selected_id
	var vehicle_nom: String = VehicleRoster.find(vehicle_id).get("nom", "?")
	var best: Dictionary = Leaderboard.personal_best(_selected["uid"], vehicle_id)
	if best.is_empty():
		_personal_best_label.text = "Aucun temps (%s)" % vehicle_nom
	else:
		_personal_best_label.text = "%s — Temps : %s" % [vehicle_nom, TimeFormat.format_ms(int(best["ms"]))]


func _build_track_list_column(parent: HBoxContainer) -> void:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	parent.add_child(col)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)

	_track_list = VBoxContainer.new()
	_track_list.add_theme_constant_override("separation", 6)
	_track_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_track_list)

func _on_search_changed(text: String) -> void:
	_refresh_catalog(text)

func _on_group_changed(index: int) -> void:
	_group_mode = index
	_expanded_collection = ""
	_refresh_catalog(_search_edit.text)

func _refresh_catalog(filter: String = "") -> void:
	for child in _track_list.get_children():
		child.queue_free()
	_track_row_by_uid.clear()

	var needle: String = filter.strip_edges().to_lower()
	var filtered: Array[Dictionary] = []
	for entry in _all_tracks:
		var nom: String = String(entry["nom"]).to_lower()
		var auteur: String = String(entry["auteur"]).to_lower()
		if needle == "" or nom.contains(needle) or auteur.contains(needle):
			filtered.append(entry)

	var any_rows: bool = _build_catalog_rows(filtered)
	if not any_rows:
		var empty := Label.new()
		empty.text = "Aucune collection — clic droit sur une piste pour en créer une" if _group_mode == GroupMode.COLLECTIONS else "Aucune piste ne correspond à la recherche"
		empty.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		_track_list.add_child(empty)

	var target: Dictionary = {}
	if _group_mode != GroupMode.COLLECTIONS or _expanded_collection != "":
		target = _selected
		if target.is_empty() or not _track_row_by_uid.has(target.get("uid", "")):
			target = filtered[0] if not filtered.is_empty() else {}
			if _group_mode == GroupMode.COLLECTIONS and not _track_row_by_uid.has(target.get("uid", "")):
				target = {}
	_select_track(target)

func _build_catalog_rows(filtered: Array[Dictionary]) -> bool:
	match _group_mode:
		GroupMode.COLLECTIONS:
			return _build_grouped_list(filtered)
		GroupMode.CREATEUR:
			return _build_sectioned_list(TrackGrouping.sections_alpha(filtered, "auteur"))
		GroupMode.TITRE:
			return _build_sectioned_list(TrackGrouping.sections_alpha(filtered, "nom"))
		GroupMode.DATE_AJOUT:
			return _build_sectioned_list(TrackGrouping.sections_date_ajout(filtered))
		GroupMode.DUREE:
			return _build_sectioned_list(TrackGrouping.sections_duree(filtered, _meilleurs_temps_par_uid(filtered)))
		GroupMode.RECEMMENT_JOUEES:
			return _build_sectioned_list(TrackGrouping.sections_recemment_jouees(filtered, _derniers_joues_par_uid(filtered)))
		GroupMode.VEHICULE:
			return _build_sectioned_list(TrackGrouping.sections_vehicule(filtered))
		GroupMode.MES_PISTES:
			return _build_flat_list(filtered.filter(func(e: Dictionary) -> bool: return not bool(e.get("builtin", false))))
		_:
			return _build_flat_list(filtered) 

func _meilleurs_temps_par_uid(filtered: Array[Dictionary]) -> Dictionary:
	var result: Dictionary = {}
	for entry in filtered:
		var runs: Array[Dictionary] = Leaderboard.runs(entry["uid"])
		if not runs.is_empty():
			result[entry["uid"]] = int(runs[0]["ms"])
	return result

func _derniers_joues_par_uid(filtered: Array[Dictionary]) -> Dictionary:
	var result: Dictionary = {}
	for entry in filtered:
		var dernier: float = -1.0
		for run in Leaderboard.runs(entry["uid"]):
			var t: float = Time.get_unix_time_from_datetime_string(String(run.get("date", "")))
			if t > dernier:
				dernier = t
		if dernier >= 0.0:
			result[entry["uid"]] = dernier
	return result

func _build_sectioned_list(sections: Array[Dictionary]) -> bool:
	for section in sections:
		_track_list.add_child(_build_section_header(String(section["label"])))
		for entry in section["entries"]:
			var button: Button = _build_track_row(entry)
			_track_list.add_child(button)
			_track_row_by_uid[entry["uid"]] = button
	return not sections.is_empty()

func _build_section_header(label: String) -> Label:
	var header := Label.new()
	header.text = label
	header.add_theme_font_size_override("font_size", 16)
	header.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
	return header

func _build_flat_list(filtered: Array[Dictionary]) -> bool:
	for entry in filtered:
		var button: Button = _build_track_row(entry)
		_track_list.add_child(button)
		_track_row_by_uid[entry["uid"]] = button
	return not filtered.is_empty()

func _build_grouped_list(filtered: Array[Dictionary]) -> bool:
	var by_uid: Dictionary = {}
	for entry in filtered:
		by_uid[entry["uid"]] = entry

	var names: Array[String] = Collections.list_names()
	for name in names:
		_track_list.add_child(_build_collection_header(name))
		if name != _expanded_collection:
			continue

		var member_entries: Array[Dictionary] = []
		for uid in Collections.tracks_in(name):
			if by_uid.has(uid):
				member_entries.append(by_uid[uid])

		if member_entries.is_empty():
			var empty_label := Label.new()
			empty_label.text = "   (aucune piste ici)"
			empty_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
			_track_list.add_child(empty_label)
			continue

		for entry in member_entries:
			var margin := MarginContainer.new()
			margin.add_theme_constant_override("margin_left", 20)
			var button: Button = _build_track_row(entry)
			margin.add_child(button)
			_track_list.add_child(margin)
			_track_row_by_uid[entry["uid"]] = button

	return not names.is_empty()

func _build_collection_header(name: String) -> Button:
	var header := Button.new()
	header.text = "%s %s (%d)" % ["▾" if name == _expanded_collection else "▸", name, Collections.count(name)]
	header.custom_minimum_size = Vector2(0.0, 36.0)
	header.add_theme_font_size_override("font_size", 16)
	header.modulate = Color(0.75, 0.85, 1.0)
	header.pressed.connect(_on_collection_header_pressed.bind(name))
	return header

func _on_collection_header_pressed(name: String) -> void:
	_expanded_collection = "" if _expanded_collection == name else name
	_refresh_catalog(_search_edit.text)

func _build_track_row(entry: Dictionary) -> Button:
	var button := Button.new()
	button.toggle_mode = true
	button.button_group = _track_button_group
	button.custom_minimum_size = Vector2(0.0, 64.0)
	button.pressed.connect(_on_track_pressed.bind(entry))
	button.gui_input.connect(_on_track_row_gui_input.bind(entry))

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 10)
	button.add_child(row)

	var badge := Label.new()
	badge.text = "—"
	badge.custom_minimum_size = Vector2(36.0, 0.0)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(badge)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)

	var name_label := Label.new()
	name_label.text = entry["nom"]
	name_label.add_theme_font_size_override("font_size", 18)
	info.add_child(name_label)

	var auteur: String = entry.get("auteur", "")
	var author_label := Label.new()
	author_label.text = "Créée par : %s" % (auteur if auteur != "" else "—")
	author_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	info.add_child(author_label)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 2)
	info.add_child(bar)
	for i in range(6):
		var segment := ColorRect.new()
		segment.color = Color(0.35, 0.35, 0.35)
		segment.custom_minimum_size = Vector2(14.0, 4.0)
		bar.add_child(segment)

	return button


func _on_track_row_gui_input(event: InputEvent, entry: Dictionary) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_show_context_menu(entry)
		get_viewport().set_input_as_handled()

func _show_context_menu(entry: Dictionary) -> void:
	var builtin: bool = entry.get("builtin", false)

	var menu := PopupMenu.new()
	add_child(menu)
	menu.popup_hide.connect(menu.queue_free)
	menu.id_pressed.connect(_on_context_menu_id.bind(entry))

	menu.add_item("Gérer les collections...", 0)
	menu.add_item("Supprimer...", 1)
	menu.set_item_disabled(1, builtin)
	menu.add_item("Effacer les scores locaux", 2)
	menu.add_item("Éditer", 3)
	menu.set_item_disabled(3, builtin)
	menu.add_separator()
	menu.add_item("Annuler", 4)

	var mouse_pos: Vector2i = Vector2i(get_global_mouse_position())
	menu.popup(Rect2i(mouse_pos, Vector2i.ZERO))

func _on_context_menu_id(id: int, entry: Dictionary) -> void:
	match id:
		0:
			_open_collections_menu(entry)
		1:
			_confirm_delete_track(entry)
		2:
			_confirm_clear_scores(entry)
		3:
			_edit_track(entry)
		_:
			pass  # Annuler

func _open_collections_menu(entry: Dictionary) -> void:
	_root_layout.hide()
	_collections_menu.open_for(entry)
	_collections_menu.show()
	_collections_menu.focus_first()

func _on_collections_menu_closed() -> void:
	_collections_menu.hide()
	_root_layout.show()
	_refresh_catalog(_search_edit.text)  # compositions/comptages de collections ont pu changer

func _confirm_delete_track(entry: Dictionary) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Confirmation"
	dialog.dialog_text = "Supprimer définitivement « %s » ? Cette action est irréversible." % entry["nom"]
	dialog.confirmed.connect(_on_delete_track_confirmed.bind(entry))
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.get_cancel_button().text = "Annuler"
	dialog.popup_centered()

func _on_delete_track_confirmed(entry: Dictionary) -> void:
	TrackCatalog.delete_track(entry["path"])
	Collections.remove_track_everywhere(entry["uid"])
	_all_tracks = TrackCatalog.list_tracks()
	if not _selected.is_empty() and _selected["uid"] == entry["uid"]:
		_selected = {}
	_refresh_catalog(_search_edit.text)

func _confirm_clear_scores(entry: Dictionary) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Confirmation"
	dialog.dialog_text = "Effacer tous les temps locaux de « %s », tous véhicules confondus ?" % entry["nom"]
	dialog.confirmed.connect(_on_clear_scores_confirmed.bind(entry))
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.get_cancel_button().text = "Annuler"
	dialog.popup_centered()

func _on_clear_scores_confirmed(entry: Dictionary) -> void:
	Leaderboard.clear_track(entry["uid"])
	if not _selected.is_empty() and _selected["uid"] == entry["uid"]:
		_refresh_leaderboard()
		_refresh_personal_best()

func _edit_track(entry: Dictionary) -> void:
	if entry.get("builtin", false):
		return
	Session.pending_track_path = entry["path"]
	get_tree().change_scene_to_file("res://editor/track_editor.tscn")

func _on_track_pressed(entry: Dictionary) -> void:
	_select_track(entry)

func _select_track(entry: Dictionary) -> void:
	_selected = entry
	if _play_button != null:
		_play_button.disabled = entry.is_empty()
	if _ghost_button != null:
		_ghost_button.disabled = entry.is_empty()
		_refresh_ghost_button()
	if not entry.is_empty() and _track_row_by_uid.has(entry["uid"]):
		(_track_row_by_uid[entry["uid"]] as Button).button_pressed = true
	_refresh_preview()
	_refresh_leaderboard()
	_refresh_personal_best()


func _build_bottom_bar(parent: VBoxContainer) -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	parent.add_child(bar)

	var back := Button.new()
	back.text = "Retour"
	back.pressed.connect(_on_back_pressed)
	bar.add_child(back)

	var options := Button.new()
	options.text = "Options de jeu"
	options.disabled = true
	options.tooltip_text = "Bientôt disponible"
	bar.add_child(options)

	_ghost_button = Button.new()
	_ghost_button.text = "Choisir un fantôme"
	_ghost_button.disabled = _selected.is_empty()
	_ghost_button.pressed.connect(_on_ghost_pressed)
	bar.add_child(_ghost_button)

	_vehicle_button = Button.new()
	_vehicle_button.text = "Changer de véhicule"
	_vehicle_button.pressed.connect(_on_vehicle_pressed)
	bar.add_child(_vehicle_button)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(spacer)

	_play_button = Button.new()
	_play_button.text = "JOUER"
	_play_button.custom_minimum_size = Vector2(160.0, 48.0)
	_play_button.disabled = true
	_play_button.pressed.connect(_on_play_pressed)
	bar.add_child(_play_button)

func _on_vehicle_pressed() -> void:
	if _vehicle_menu.visible:
		_vehicle_menu.hide()
		return
	_vehicle_menu.open_above(_vehicle_button)
	_vehicle_menu.show()
	_vehicle_menu.focus_first()

func _on_vehicle_menu_closed() -> void:
	_vehicle_menu.hide()
	_refresh_personal_best()  
	_refresh_ghost_button() 
	_vehicle_button.grab_focus()

func _on_ghost_pressed() -> void:
	if _selected.is_empty():
		return
	_root_layout.hide()
	_ghost_menu.open_for(_selected["uid"])
	_ghost_menu.show()
	_ghost_menu.focus_first()

func _on_ghost_menu_closed() -> void:
	_ghost_menu.hide()
	_root_layout.show()
	_refresh_ghost_button() 
	_ghost_button.grab_focus()

func _refresh_ghost_button() -> void:
	if _selected.is_empty():
		return
	_ghost_button.text = GhostResolver.libelle(
		GhostSelection.selection(_selected["uid"]), VehicleSelection.selected_id
	)

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")

func _unhandled_input(event: InputEvent) -> void:
	if _root_layout.visible and event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and _search_edit.has_focus():
		var click_pos: Vector2 = (event as InputEventMouseButton).position
		if not _search_edit.get_global_rect().has_point(click_pos):
			_search_edit.release_focus()

func _on_play_pressed() -> void:
	if _selected.is_empty():
		return
	Session.pending_track_path = _selected.get("path", "")
	Session.pending_builtin_uid = _selected.get("uid", "") if _selected.get("builtin", false) else ""
	get_tree().change_scene_to_file("res://main.tscn")
