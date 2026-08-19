# Panneau de choix du fantôme (bouton "Choisir un fantôme" de
# ui/track_select.gd), ouvert pour une piste donnée — même patron d'overlay
# que ui/vehicle_menu.gd/ui/collections_menu.gd, sauf le bouton "Retour" :
# bas-gauche de l'écran, même taille/emplacement que celui de
# ui/track_select.gd, PAS un élément du panneau centré. Maquette fournie par
# l'utilisateur : "Aucun fantôme" centré au-dessus (même taille que les
# autres boutons de fantôme, voir _build_pick_row()), puis trois colonnes
# côte à côte (voir replay/ghost_resolver.gd, ui/ghost_selection.gd) :
#   - Records mondiaux : demande le site/backend (CLAUDE.md, étape 6), hors
#     scope ici — lignes visibles (même liste de véhicules que "Mes records",
#     pour garder la mise en page prête) mais désactivées et sans score.
#   - Mes records : un par véhicule, plus "Véhicule courant" qui suit
#     ui/vehicle_selection.gd — sélectionner l'une de ces lignes REMPLACE
#     AUTOMATIQUEMENT le fantôme dès qu'un record est battu, sans repasser
#     par ce menu (c'est GhostResolver qui fait ça).
#   - Fantômes enregistrés : runs épinglés manuellement (voir
#     ui/finish_menu.gd, "Enregistrer ce fantôme" sur un run qui n'est pas un
#     record), chacun avec une suppression dédiée derrière confirmation.
#
# Chaque ligne porte une barre verticale : grise par défaut, VERTE sur la
# ligne qui correspond à la sélection courante (GhostSelection) — une seule
# à la fois, y compris "Aucun fantôme" (verte par défaut tant que rien n'a
# été choisi, voir ui/ghost_selection.gd::selection()). Écrit directement
# dans GhostSelection au clic ET REFRESH SUR PLACE (pas de closed.emit()) —
# sur demande explicite : choisir un fantôme reste sur ce panneau, seul
# "Retour"/Échap le ferme.
class_name GhostMenu
extends Control

signal closed

const COULEUR_INACTIVE := Color(0.42, 0.42, 0.42)
const COULEUR_ACTIVE := Color(0.3, 0.78, 0.38)

var _track_uid: String = ""
var _selection: Dictionary = {}  # GhostSelection.selection(_track_uid), mise en cache pour le _refresh() courant

var _none_container: VBoxContainer
var _mondiaux_rows: VBoxContainer
var _perso_rows: VBoxContainer
var _pinned_rows: VBoxContainer
var _back_button: Button

func _ready() -> void:
	_build_ui()

# À appeler avant .show() — ne rafraîchit pas tout de suite, focus_first()
# (appelée par le parent juste après .show(), même patron que les autres
# overlays) s'en charge.
func open_for(track_uid: String) -> void:
	_track_uid = track_uid

# Piège trouvé en jeu (pas en headless, où tout semblait correct) : ce nœud
# est créé puis .hide()é AVANT que son parent (ui/track_select.gd) n'ait sa
# taille finale. La taille calculée depuis les ancrages restait bloquée à
# (0,0) indéfiniment — re-appeler set_anchors_preset() ne force PAS de
# recalcul (vérifié). get_viewport_rect() reste fiable dans tous les cas
# observés, donc on fixe la taille de CE nœud directement dessus. Même
# piège pour _back_button (ancré bas-gauche RELATIVEMENT à ce nœud) : son
# set_anchors_preset() doit attendre d'être appelé ICI, une fois cette
# taille corrigée — le faire dans _build_ui() (trop tôt) reproduirait le
# même bug.
func focus_first() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size
	# set_anchors_preset() sur _back_button lisait encore l'ANCIENNE taille
	# de ce nœud (la mise à jour de `size` juste au-dessus ne se propage pas
	# de façon synchrone à get_parent_area_size()) — le bouton finissait en
	# haut à gauche au lieu du bas. Position calculée directement sur
	# get_viewport_rect(), même contournement que pour ce nœud lui-même.
	_back_button.position = Vector2(0.0, get_viewport_rect().size.y - _back_button.size.y)
	_refresh()

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

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
	vbox.custom_minimum_size = Vector2(960.0, 0.0)  # exactement 3 × 300 + 2 × 30 (colonnes + séparation) : aucun jeu qui étirerait les colonnes au-delà de 300
	vbox.add_theme_constant_override("separation", 14)
	vbox.mouse_filter = Control.MOUSE_FILTER_STOP
	vbox.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	center.add_child(vbox)

	var title := Label.new()
	title.text = "Choisir un fantôme"
	title.add_theme_font_size_override("font_size", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Simple sous-conteneur (pas de centrage ici : voir _build_pick_row(),
	# c'est le bouton lui-même qui se centre via SIZE_SHRINK_CENTER) —
	# uniquement un emplacement qu'on vide/reconstruit à chaque _refresh().
	_none_container = VBoxContainer.new()
	vbox.add_child(_none_container)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 30)
	vbox.add_child(columns)

	_mondiaux_rows = _build_column(columns, "Records mondiaux")
	_perso_rows = _build_column(columns, "Mes records")
	_pinned_rows = _build_column(columns, "Fantômes enregistrés")

	# "Retour" HORS du panneau centré ci-dessus : bas-gauche de l'écran, même
	# taille/emplacement que le bouton "Retour" de
	# ui/track_select.gd::_build_bottom_bar() (maquette utilisateur) — pas un
	# élément du panneau qui grandirait avec lui. Ancrage posé dans
	# focus_first(), voir son commentaire.
	_back_button = Button.new()
	_back_button.text = "Retour"
	_back_button.pressed.connect(func() -> void: closed.emit())
	add_child(_back_button)

# Échap ferme ce panneau comme le bouton "Retour" — même règle sur tous les
# écrans qui en proposent un (voir ui/vehicle_menu.gd, ui/editor_menu.gd,
# ui/settings_menu.gd, ui/track_select.gd). Le garde `visible` est
# nécessaire : ce nœud reste dans l'arbre (show()/hide()) même quand ce
# panneau n'est pas affiché, _unhandled_input() continuerait sinon à réagir.
func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		closed.emit()
		get_viewport().set_input_as_handled()

# Ajoute une colonne (entête + sous-conteneur de lignes) à `columns`, renvoie
# le sous-conteneur : c'est lui qu'on vide/reconstruit à chaque _refresh(),
# l'entête au-dessus reste en place.
func _build_column(columns: HBoxContainer, titre: String) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(300.0, 0.0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	columns.add_child(col)

	var header := Label.new()
	header.text = titre
	header.add_theme_font_size_override("font_size", 16)
	col.add_child(header)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	col.add_child(rows)
	return rows

func _refresh() -> void:
	_selection = GhostSelection.selection(_track_uid)
	_refresh_none_row()
	_refresh_mondiaux()
	_refresh_perso()
	_refresh_pinned()

# ------------------------------------------------------------- aucun fantôme --

func _refresh_none_row() -> void:
	for child in _none_container.get_children():
		child.queue_free()
	# largeur_fixe=300.0 : EXACTEMENT la largeur d'une colonne
	# (custom_minimum_size de _build_column()), pour que "Aucun fantôme" soit
	# de la même taille que les autres boutons de fantôme, pas une bande
	# pleine largeur ni une taille arbitraire.
	_none_container.add_child(_build_pick_row(
		"Aucun fantôme",
		_est_selection(GhostResolver.Source.AUCUN, "", ""),
		GhostResolver.Source.AUCUN, "", "", 300.0
	))

# --------------------------------------------------------- records mondiaux --

# Demande le site/backend (CLAUDE.md, étape 6) : lignes visibles pour garder
# la mise en page symétrique avec "Mes records" (prêtes pour de vraies
# données plus tard), mais désactivées et sans score — pas de mention
# "Bientôt disponible" qui décalerait cette colonne par rapport aux autres,
# sur demande explicite (l'absence de score suffit).
func _refresh_mondiaux() -> void:
	for child in _mondiaux_rows.get_children():
		child.queue_free()

	_mondiaux_rows.add_child(_build_disabled_row("Véhicule courant"))
	for vehicle in VehicleRoster.VEHICLES:
		_mondiaux_rows.add_child(_build_disabled_row(vehicle["nom"]))

# ---------------------------------------------------------------- mes records --

func _refresh_perso() -> void:
	for child in _perso_rows.get_children():
		child.queue_free()

	var runs: Array[Dictionary] = Leaderboard.runs(_track_uid)

	_perso_rows.add_child(_build_pick_row(
		"Véhicule courant",
		_est_selection(GhostResolver.Source.PERSO, "", ""),
		GhostResolver.Source.PERSO, "", ""
	))

	for vehicle in VehicleRoster.VEHICLES:
		# GhostResolver.best_entry() : même recherche que celle utilisée pour
		# résoudre effectivement le fantôme (main.gd) — une seule source de
		# vérité pour "quel est mon meilleur run encore rejouable".
		var entry: Dictionary = GhostResolver.best_entry(runs, vehicle["id"])
		if entry.is_empty():
			_perso_rows.add_child(_build_disabled_row("%s — aucun temps" % vehicle["nom"]))
			continue
		var texte: String = "%s — %s" % [vehicle["nom"], TimeFormat.format_ms(int(entry["ms"]))]
		_perso_rows.add_child(_build_pick_row(
			texte, _est_selection(GhostResolver.Source.PERSO, vehicle["id"], ""),
			GhostResolver.Source.PERSO, vehicle["id"], ""
		))

# ---------------------------------------------------------- fantômes enregistrés --

func _refresh_pinned() -> void:
	for child in _pinned_rows.get_children():
		child.queue_free()

	var entries: Array[Dictionary] = []
	for entry in Leaderboard.pinned_runs(_track_uid):
		if ReplayStore.exists(String(entry.get("replay", ""))):
			entries.append(entry)

	if entries.is_empty():
		var empty := Label.new()
		empty.text = "Aucun fantôme enregistré manuellement"
		empty.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		# autowrap : sans lui, le texte non coupé (plus large que la colonne)
		# forcerait cette colonne au-delà de sa largeur fixe et casserait la
		# symétrie des 3 colonnes (même piège que ui/vehicle_menu.gd::geste).
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD
		_pinned_rows.add_child(empty)
		return

	for entry in entries:
		_pinned_rows.add_child(_build_pinned_row(entry))

func _build_pinned_row(entry: Dictionary) -> HBoxContainer:
	var replay_file: String = String(entry.get("replay", ""))
	var vehicle: Dictionary = VehicleRoster.find(entry.get("vehicule", ""))
	var texte: String = "%s — %s" % [vehicle.get("nom", "?"), TimeFormat.format_ms(int(entry["ms"]))]

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_build_pick_row(texte,
		_est_selection(GhostResolver.Source.MANUEL, "", replay_file),
		GhostResolver.Source.MANUEL, "", replay_file))

	var delete_button := Button.new()
	delete_button.text = "Supprimer"
	delete_button.pressed.connect(_confirm_delete.bind(entry))
	row.add_child(delete_button)

	return row

func _confirm_delete(entry: Dictionary) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Confirmation"
	dialog.dialog_text = "Supprimer définitivement ce fantôme ? Cette action est irréversible."
	dialog.confirmed.connect(_on_delete_confirmed.bind(entry))
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	# get_cancel_button() n'existe qu'une fois le dialogue DANS l'arbre
	# (add_child() ci-dessus) : l'appeler avant plantait la fonction (nœud pas
	# encore construit), empêchant popup_centered() de s'exécuter — le
	# panneau ne s'affichait plus du tout. Repli anglais par défaut sinon
	# ("Cancel"), même logique que le titre "Confirmation". Pas de
	# get_close_button() : cette méthode n'existe pas sur ConfirmationDialog
	# dans cette version de Godot (vérifié) — la croix de fermeture de la
	# barre de titre reste, aucune API scriptable pour la retirer sans virer
	# toute la barre de titre (donc aussi "Confirmation").
	dialog.get_cancel_button().text = "Annuler"
	dialog.popup_centered()

func _on_delete_confirmed(entry: Dictionary) -> void:
	var replay_file: String = String(entry.get("replay", ""))
	# Si ce fantôme était la sélection MANUELLE active, revenir à "Aucun
	# fantôme" plutôt que de laisser la sélection pointer vers un fichier qui
	# n'existe plus.
	if int(_selection.get("source", GhostResolver.Source.AUCUN)) == GhostResolver.Source.MANUEL \
			and String(_selection.get("fichier", "")) == replay_file:
		GhostSelection.select(_track_uid, GhostResolver.Source.AUCUN)
	Leaderboard.delete_run(_track_uid, replay_file)
	_refresh()

# ------------------------------------------------------------------- lignes --

# Vrai si (source, vehicule, fichier) correspond à la sélection courante —
# c'est cette comparaison qui décide quelle SEULE barre est verte.
func _est_selection(source: int, vehicule: String, fichier: String) -> bool:
	if int(_selection.get("source", GhostResolver.Source.AUCUN)) != source:
		return false
	match source:
		GhostResolver.Source.PERSO, GhostResolver.Source.MONDIAL:
			return String(_selection.get("vehicule", "")) == vehicule
		GhostResolver.Source.MANUEL:
			return String(_selection.get("fichier", "")) == fichier
		_:
			return true  # AUCUN : rien d'autre à comparer

# Une ligne cliquable : barre verticale (grise/verte selon _est_selection) +
# texte. Sélectionner écrit dans GhostSelection puis _refresh() SUR PLACE
# (jamais closed.emit() — sur demande explicite, choisir un fantôme reste
# sur ce panneau ; seuls "Retour"/Échap le ferment). largeur_fixe > 0 :
# largeur figée + SIZE_SHRINK_CENTER au lieu de SIZE_EXPAND_FILL — utilisé
# uniquement par "Aucun fantôme", pour qu'il ait la même taille que les
# autres boutons (300×40) mais reste centré dans _none_container au lieu de
# s'étirer pleine largeur.
func _build_pick_row(texte: String, actif: bool, source: int, vehicule: String, fichier: String, largeur_fixe: float = 0.0) -> Button:
	var button := Button.new()
	if largeur_fixe > 0.0:
		button.custom_minimum_size = Vector2(largeur_fixe, 40.0)
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	else:
		button.custom_minimum_size = Vector2(0.0, 40.0)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(_on_row_pressed.bind(source, vehicule, fichier))
	button.add_child(_build_row_content(texte, COULEUR_ACTIVE if actif else COULEUR_INACTIVE))
	return button

# Ligne non cliquable (section "Records mondiaux", ou véhicule "Mes records"
# sans aucun temps) : toujours la barre inactive, jamais de couleur.
func _build_disabled_row(texte: String) -> Control:
	var container := Control.new()
	container.custom_minimum_size = Vector2(0.0, 40.0)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(_build_row_content(texte, COULEUR_INACTIVE))
	return container

func _build_row_content(texte: String, couleur: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 10)

	var barre := ColorRect.new()
	barre.color = couleur
	barre.custom_minimum_size = Vector2(4.0, 0.0)
	barre.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(barre)

	var label := Label.new()
	label.text = texte
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)

	return row

func _on_row_pressed(source: int, vehicule: String, fichier: String) -> void:
	GhostSelection.select(_track_uid, source, vehicule, fichier)
	_refresh()
