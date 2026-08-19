# Liste fermée des éléments de piste (voir CLAUDE.md) — source unique,
# réutilisée par l'éditeur (palette) et plus tard par le rendu/la simulation
# de chaque élément. "id" est stable (sauvegardé dans TrackData), "nom" et
# les variantes peuvent encore évoluer.
#
# Une variante change le modèle 3D / la hitbox d'un élément, jamais son
# comportement (ex. barrière "campagne" vs "ville" : toujours une barrière).
# Les éléments sans variante spécifique portent une unique variante "defaut",
# en attendant qu'on en définisse d'autres.
class_name ElementRoster

# Même ordre que ELEMENTS ci-dessous, pour que kind_for_id() reste facile à
# vérifier à l'œil. Contrairement à CarConfig.TypeGlisse (sérialisé dans les
# CarConfig, donc figé), cet enum n'est JAMAIS persisté : Track.elem_kind
# (sim/) est reconstruit depuis les ids à chaque chargement de piste
# (map/track_data.gd::to_track()) — le réordonner ne casse rien de
# sauvegardé, INCONNU doit juste rester la valeur 0 (repli silencieux pour
# un id absent/mal orthographié).
enum Kind {
	INCONNU,
	ROUTE_NORMALE,
	ROUTE_RALENTIT,
	ROUTE_DEGRADE_CONTROLES,
	VIDE,
	ROUTE_AIMANTEE,
	BARRIERE,
	MUR,
	OBSTACLE_BLOQUANT,
	OBSTACLE_RALENTIT,
	OBSTACLE_MORTEL,
	RAMPE,
	BOOST,
	LIGNE_DEPART_ARRIVEE,
	CHECKPOINT,
}

const ELEMENTS: Array[Dictionary] = [
	{"id": "route_normale", "nom": "Route normale", "variants": [{"id": "defaut", "nom": "Défaut"}]},
	{"id": "route_ralentit", "nom": "Route qui ralentit", "variants": [{"id": "defaut", "nom": "Défaut"}]},
	{"id": "route_degrade_controles", "nom": "Route qui dégrade les contrôles", "variants": [{"id": "defaut", "nom": "Défaut"}]},
	{"id": "vide", "nom": "Vide", "variants": [{"id": "defaut", "nom": "Défaut"}]},
	{"id": "route_aimantee", "nom": "Route aimantée", "variants": [{"id": "defaut", "nom": "Défaut"}]},
	{"id": "barriere", "nom": "Barrière", "variants": [{"id": "campagne", "nom": "Campagne"}, {"id": "ville", "nom": "Ville"}]},
	{"id": "mur", "nom": "Mur", "variants": [{"id": "defaut", "nom": "Défaut"}]},
	{"id": "obstacle_bloquant", "nom": "Obstacle bloquant", "variants": [{"id": "defaut", "nom": "Défaut"}]},
	{"id": "obstacle_ralentit", "nom": "Obstacle qui ralentit au contact", "variants": [{"id": "defaut", "nom": "Défaut"}]},
	{"id": "obstacle_mortel", "nom": "Obstacle mortel", "variants": [{"id": "defaut", "nom": "Défaut"}]},
	{"id": "rampe", "nom": "Rampe", "variants": [{"id": "defaut", "nom": "Défaut"}]},
	{"id": "boost", "nom": "Boost", "variants": [{"id": "defaut", "nom": "Défaut"}]},
	{"id": "ligne_depart_arrivee", "nom": "Ligne de départ / d'arrivée", "variants": [{"id": "defaut", "nom": "Défaut"}]},
	{"id": "checkpoint", "nom": "Checkpoint", "variants": [{"id": "defaut", "nom": "Défaut"}]},
]

static func find(id: String) -> Dictionary:
	for entry in ELEMENTS:
		if entry["id"] == id:
			return entry
	return {}

static func find_variant(element: Dictionary, variant_id: String) -> Dictionary:
	for v in element.get("variants", []):
		if v["id"] == variant_id:
			return v
	return {}

# Résout un id (tel que stocké dans TrackData.elements) vers l'enum Kind
# utilisé par sim/ — Kind.INCONNU pour tout id absent/mal orthographié,
# jamais un crash (même tolérance aux pannes que Controls/Leaderboard).
static func kind_for_id(id: String) -> int:
	match id:
		"route_normale": return Kind.ROUTE_NORMALE
		"route_ralentit": return Kind.ROUTE_RALENTIT
		"route_degrade_controles": return Kind.ROUTE_DEGRADE_CONTROLES
		"vide": return Kind.VIDE
		"route_aimantee": return Kind.ROUTE_AIMANTEE
		"barriere": return Kind.BARRIERE
		"mur": return Kind.MUR
		"obstacle_bloquant": return Kind.OBSTACLE_BLOQUANT
		"obstacle_ralentit": return Kind.OBSTACLE_RALENTIT
		"obstacle_mortel": return Kind.OBSTACLE_MORTEL
		"rampe": return Kind.RAMPE
		"boost": return Kind.BOOST
		"ligne_depart_arrivee": return Kind.LIGNE_DEPART_ARRIVEE
		"checkpoint": return Kind.CHECKPOINT
		_: return Kind.INCONNU

# Couleur distinctive par type d'élément, dérivée de son id (stable, donc la
# couleur d'un type donné ne change jamais) — partagée par l'éditeur
# (editor/track_editor.gd) et le rendu en jeu (render/track_elements_view.gd)
# pour que la même palette s'affiche aux deux endroits.
static func color_for_type(type_id: String) -> Color:
	var h: int = type_id.hash()
	return Color.from_hsv(float(abs(h) % 360) / 360.0, 0.65, 0.85)
