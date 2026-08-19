# Résolution pure de la sélection de fantôme (ui/ghost_selection.gd) vers un
# nom de fichier de replay. Statique, AUCUNE dépendance à un autoload : c'est
# ce qui rend cette logique testable depuis tools/run_tests.gd, qui tourne
# via --script et ne charge aucun autoload. ReplayStore (statique lui aussi,
# pas un autoload) reste appelable ici sans casser cette contrainte.
class_name GhostResolver

enum Source { AUCUN, PERSO, MONDIAL, MANUEL }

# selection : {"source": Source, "vehicule": String, "fichier": String}
#   "vehicule" == "" -> suit vehicule_courant (PERSO/MONDIAL uniquement).
# runs : Leaderboard.runs(track_uid) — chaque entrée a "vehicule"/"ms"/"replay".
#   PAS supposé trié : le minimum est recherché explicitement (voir
#   best_entry()), pour ne jamais dépendre de l'ordre de l'appelant.
# records_mondiaux : même forme que runs mais pour le classement mondial
#   ("vehicule"/"ms"/"fichier") — toujours vide tant que le backend n'existe
#   pas (voir CLAUDE.md, étape 6), donc MONDIAL retombe naturellement sur
#   PERSO ou "" sans rien inventer.
static func resolve(selection: Dictionary, runs: Array[Dictionary], vehicule_courant: String, records_mondiaux: Array[Dictionary]) -> String:
	match int(selection.get("source", Source.AUCUN)):
		Source.MANUEL:
			return String(selection.get("fichier", ""))
		Source.PERSO:
			return String(best_entry(runs, _vehicule_effectif(selection, vehicule_courant)).get("replay", ""))
		Source.MONDIAL:
			return _resolve_mondial(selection, runs, vehicule_courant, records_mondiaux)
		_:
			return ""

# Texte du bouton "Choisir un fantôme" (ui/track_select.gd) et de l'entête
# du menu (ui/ghost_menu.gd) — reflète la SÉLECTION, pas le fichier résolu
# (une sélection PERSO reste "mon record" même quand aucun temps n'existe
# encore sur cette piste).
static func libelle(selection: Dictionary, vehicule_courant: String) -> String:
	var vehicule: String = _vehicule_effectif(selection, vehicule_courant)
	var nom: String = VehicleRoster.find(vehicule).get("nom", "?")
	match int(selection.get("source", Source.AUCUN)):
		Source.PERSO:
			return "Fantôme : mon record (%s)" % nom
		Source.MONDIAL:
			return "Fantôme : record mondial (%s)" % nom
		Source.MANUEL:
			return "Fantôme : choisi"
		_:
			return "Choisir un fantôme"

# Traduction persistée <-> enum : un int d'enum écrit tel quel dans un .cfg se
# corromprait silencieusement au moindre réordonnancement futur de Source —
# même précaution que les ID de véhicule/piste, toujours stockés en chaîne
# ailleurs dans le projet. ui/ghost_selection.gd est seul appelant.
static func source_name(source: int) -> String:
	match source:
		Source.PERSO:
			return "perso"
		Source.MONDIAL:
			return "mondial"
		Source.MANUEL:
			return "manuel"
		_:
			return "aucun"

static func source_from_name(name: String) -> int:
	match name:
		"perso":
			return Source.PERSO
		"mondial":
			return Source.MONDIAL
		"manuel":
			return Source.MANUEL
		_:
			return Source.AUCUN

# Meilleure entrée (temps minimal) d'un véhicule DONT le fichier de replay
# existe encore sur disque — ignore une entrée orpheline (supprimée
# manuellement, ou disque nettoyé) plutôt que de la laisser masquer le run
# suivant. Cherche le minimum explicitement (pas juste "le premier match") :
# ne dépend jamais de l'ordre dans lequel l'appelant fournit `runs`. Publique
# pour être réutilisée telle quelle par ui/ghost_menu.gd (une seule source de
# vérité pour "quel est mon meilleur run encore rejouable").
static func best_entry(runs: Array[Dictionary], vehicule: String) -> Dictionary:
	var meilleure: Dictionary = {}
	var meilleur_ms: int = -1
	for entry in runs:
		if entry.get("vehicule", "") != vehicule:
			continue
		if not ReplayStore.exists(String(entry.get("replay", ""))):
			continue
		var ms: int = int(entry.get("ms", 0))
		if meilleur_ms < 0 or ms < meilleur_ms:
			meilleur_ms = ms
			meilleure = entry
	return meilleure

# Le WR le plus rapide devenu plus lent que notre propre record signifie
# qu'on l'a battu et qu'on EST devenu le record — on affronte alors son
# propre record plutôt qu'un fantôme obsolète de soi-même. La dégradation
# est calculée ici, à la résolution, JAMAIS écrite dans la sélection stockée
# : le choix MONDIAL du joueur doit rester intact pour le jour où le
# classement mondial existera vraiment.
static func _resolve_mondial(selection: Dictionary, runs: Array[Dictionary], vehicule_courant: String, records_mondiaux: Array[Dictionary]) -> String:
	var vehicule: String = _vehicule_effectif(selection, vehicule_courant)
	var wr: Dictionary = _record_mondial(records_mondiaux, vehicule)
	var pb: Dictionary = best_entry(runs, vehicule)
	if wr.is_empty():
		return String(pb.get("replay", ""))
	if not pb.is_empty() and int(pb["ms"]) < int(wr.get("ms", 0)):
		return String(pb["replay"])
	return String(wr.get("fichier", ""))

static func _vehicule_effectif(selection: Dictionary, vehicule_courant: String) -> String:
	var v: String = String(selection.get("vehicule", ""))
	return v if v != "" else vehicule_courant

static func _record_mondial(records_mondiaux: Array[Dictionary], vehicule: String) -> Dictionary:
	for entry in records_mondiaux:
		if entry.get("vehicule", "") == vehicule:
			return entry
	return {}
