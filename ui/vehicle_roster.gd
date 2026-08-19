# Liste des véhicules prévus (source unique, réutilisée par l'écran de
# sélection et par main.gd). "nom" est susceptible d'évoluer ; "id" est
# l'identifiant stable (clé de leaderboard, futur fichier de config par
# véhicule). "couleur" identifie le véhicule dans les listes de temps
# (ui/track_select.gd) — purement cosmétique, sans lien avec le rendu 3D du
# véhicule (render/car_view.gd). Tous partagent pour l'instant le même
# sim/car_config.gd — la différenciation mécanique (hitbox, drift, vitesse
# par véhicule) viendra plus tard.
class_name VehicleRoster

const VEHICLES: Array[Dictionary] = [
	{"id": "gt", "nom": "Roadster", "reference": "Forza Horizon", "geste": "Gérer une masse, transfert de charge", "couleur": Color(0.85, 0.2, 0.2)},
	{"id": "formula", "nom": "Needle", "reference": "Trackmania", "geste": "Exécuter à la frame près", "couleur": Color(0.2, 0.55, 0.9)},
	{"id": "superbike", "nom": "Ironside", "reference": "Bécane Bowser", "geste": "Drift intérieur lourd, engagement", "couleur": Color(0.9, 0.65, 0.1)},
	{"id": "street_bike", "nom": "Wasp", "reference": "Moto légère MKWii", "geste": "Drift extérieur léger, nervosité", "couleur": Color(0.85, 0.85, 0.2)},
	{"id": "hover", "nom": "Halcyon", "reference": "F-Zero", "geste": "Inertie pure, anticipation", "couleur": Color(0.55, 0.25, 0.85)},
]

static func default_id() -> String:
	return VEHICLES[0]["id"]

# Dictionary vide si id inconnu (permet à l'appelant de retomber sur le
# défaut sans planter — voir ui/vehicle_selection.gd).
static func find(id: String) -> Dictionary:
	for entry in VEHICLES:
		if entry["id"] == id:
			return entry
	return {}
