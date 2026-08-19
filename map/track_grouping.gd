# Logique de regroupement/tri du menu "Regrouper par :" de
# ui/track_select.gd. Statique et pure, AUCUNE dépendance à un autoload —
# même contrainte de testabilité que replay/ghost_resolver.gd :
# tools/run_tests.gd tourne via --script et ne charge aucun autoload. Les
# données qui viennent de Leaderboard (autoload) sont donc précalculées par
# l'appelant (uid -> valeur) et passées en paramètre, jamais lues ici.
#
# Chaque fonction renvoie Array[{"label": String, "entries": Array[Dictionary]}]
# — sections déjà triées et ordonnées, une section vide n'est jamais incluse.
class_name TrackGrouping

const ACCENTS: Dictionary = {
	"À": "A", "Â": "A", "Ä": "A",
	"É": "E", "È": "E", "Ê": "E", "Ë": "E",
	"Î": "I", "Ï": "I",
	"Ô": "O", "Ö": "O",
	"Ù": "U", "Û": "U", "Ü": "U",
	"Ç": "C",
}

# A → Z, puis "0-9", puis "Autre" ; pistes triées alphabétiquement dans
# chaque section. `champ` : "nom" ou "auteur" (clé d'une entrée de
# TrackCatalog.list_tracks()).
static func sections_alpha(entries: Array[Dictionary], champ: String) -> Array[Dictionary]:
	var buckets: Dictionary = {}
	for entry in entries:
		var label: String = _alpha_label(String(entry.get(champ, "")))
		if not buckets.has(label):
			buckets[label] = []
		(buckets[label] as Array).append(entry)

	for label in buckets:
		(buckets[label] as Array).sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return String(a.get(champ, "")).naturalnocasecmp_to(String(b.get(champ, ""))) < 0)

	var ordre: Array[String] = []
	for i in range(26):
		ordre.append(char(65 + i))
	ordre.append("0-9")
	ordre.append("Autre")

	return _assembler(ordre, buckets)

# Premier caractère (après strip_edges()), normalisé pour quelques accents
# français courants — pas un normalisateur Unicode complet, une table de
# repli suffisante pour ce projet. Chiffre -> "0-9" ; vide/symbole -> "Autre".
static func _alpha_label(value: String) -> String:
	var trimmed: String = value.strip_edges()
	if trimmed.is_empty():
		return "Autre"
	var first: String = trimmed.substr(0, 1).to_upper()
	first = ACCENTS.get(first, first)
	if first.length() != 1:
		return "Autre"
	if first >= "0" and first <= "9":
		return "0-9"
	if first >= "A" and first <= "Z":
		return first
	return "Autre"

# Sections par jour calendaire, la plus récente en premier ; "Date inconnue"
# en dernier pour les entrées sans date_ajout (piste sauvegardée avant
# l'ajout de ce champ ET dont la migration par date de fichier a échoué).
static func sections_date_ajout(entries: Array[Dictionary]) -> Array[Dictionary]:
	var buckets: Dictionary = {}  # jour (int, jours depuis epoch) -> {"label", "entries"}
	var inconnue: Array[Dictionary] = []
	for entry in entries:
		var date_str: String = String(entry.get("date_ajout", ""))
		if date_str.is_empty():
			inconnue.append(entry)
			continue
		var t: float = Time.get_unix_time_from_datetime_string(date_str)
		var jour: int = int(t) / 86400
		if not buckets.has(jour):
			var dict: Dictionary = Time.get_datetime_dict_from_unix_time(int(t))
			buckets[jour] = {
				"label": "%02d/%02d/%04d" % [int(dict["day"]), int(dict["month"]), int(dict["year"])],
				"entries": [],
			}
		(buckets[jour]["entries"] as Array).append(entry)

	for jour in buckets:
		(buckets[jour]["entries"] as Array).sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return String(a.get("date_ajout", "")) > String(b.get("date_ajout", "")))

	var jours: Array = buckets.keys()
	jours.sort()
	jours.reverse()

	var result: Array[Dictionary] = []
	for jour in jours:
		result.append(buckets[jour])
	if not inconnue.is_empty():
		result.append({"label": "Date inconnue", "entries": inconnue})
	return result

const SEUILS_DUREE_MS: Array[int] = [30000, 60000, 120000, 300000]
const LABELS_DUREE: Array[String] = [
	"Moins de 30 secondes",
	"30 secondes à 1 minute",
	"1 à 2 minutes",
	"2 à 5 minutes",
	"Plus de 5 minutes",
]
const LABEL_DUREE_INCONNUE: String = "Durée inconnue"

static func _duree_label(ms: int) -> String:
	if ms < 0:
		return LABEL_DUREE_INCONNUE
	for i in range(SEUILS_DUREE_MS.size()):
		if ms < SEUILS_DUREE_MS[i]:
			return LABELS_DUREE[i]
	return LABELS_DUREE[LABELS_DUREE.size() - 1]

# meilleurs_temps : uid -> ms (meilleur temps perso, tous véhicules
# confondus — absent = jamais joué). Tranches de durée croissantes (la plus
# courte en premier), "Durée inconnue" en dernier.
static func sections_duree(entries: Array[Dictionary], meilleurs_temps: Dictionary) -> Array[Dictionary]:
	var buckets: Dictionary = {}
	var ordre: Array[String] = LABELS_DUREE.duplicate()
	ordre.append(LABEL_DUREE_INCONNUE)
	for label in ordre:
		buckets[label] = []

	for entry in entries:
		var ms: int = int(meilleurs_temps.get(String(entry.get("uid", "")), -1))
		(buckets[_duree_label(ms)] as Array).append(entry)

	for label in buckets:
		(buckets[label] as Array).sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var ms_a: int = int(meilleurs_temps.get(String(a.get("uid", "")), -1))
			var ms_b: int = int(meilleurs_temps.get(String(b.get("uid", "")), -1))
			return ms_a < ms_b)

	return _assembler(ordre, buckets)

const LABEL_AUJOURDHUI: String = "Aujourd'hui"
const LABEL_CETTE_SEMAINE: String = "Cette semaine"
const LABEL_CE_MOIS: String = "Ce mois-ci"
const LABEL_PLUS_UN_MOIS: String = "Il y a plus d'un mois"
const LABEL_JAMAIS: String = "Jamais jouée"

static func _recence_label(dernier_unix: float, maintenant_unix: float) -> String:
	if dernier_unix < 0.0:
		return LABEL_JAMAIS
	var jours: float = (maintenant_unix - dernier_unix) / 86400.0
	if jours < 1.0:
		return LABEL_AUJOURDHUI
	if jours < 7.0:
		return LABEL_CETTE_SEMAINE
	if jours < 30.0:
		return LABEL_CE_MOIS
	return LABEL_PLUS_UN_MOIS

# derniers_joues : uid -> unix du run le plus récent (tous véhicules
# confondus — absent = jamais joué). Sections par récence décroissante (la
# plus récente en premier), "Jamais jouée" en dernier.
static func sections_recemment_jouees(entries: Array[Dictionary], derniers_joues: Dictionary) -> Array[Dictionary]:
	var maintenant: float = Time.get_unix_time_from_system()
	var ordre: Array[String] = [LABEL_AUJOURDHUI, LABEL_CETTE_SEMAINE, LABEL_CE_MOIS, LABEL_PLUS_UN_MOIS, LABEL_JAMAIS]
	var buckets: Dictionary = {}
	for label in ordre:
		buckets[label] = []

	for entry in entries:
		var dernier: float = float(derniers_joues.get(String(entry.get("uid", "")), -1.0))
		(buckets[_recence_label(dernier, maintenant)] as Array).append(entry)

	for label in buckets:
		(buckets[label] as Array).sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var d_a: float = float(derniers_joues.get(String(a.get("uid", "")), -1.0))
			var d_b: float = float(derniers_joues.get(String(b.get("uid", "")), -1.0))
			return d_a > d_b)

	return _assembler(ordre, buckets)

# Une seule section "Tous les véhicules" (aucune piste n'a de restriction de
# véhicule aujourd'hui — voir CLAUDE.md, section correspondante — prête à se
# décliner en sections par véhicule le jour où ça existera), tri
# alphabétique par nom.
static func sections_vehicule(entries: Array[Dictionary]) -> Array[Dictionary]:
	if entries.is_empty():
		return []
	var sorted: Array[Dictionary] = entries.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("nom", "")).naturalnocasecmp_to(String(b.get("nom", ""))) < 0)
	return [{"label": "Tous les véhicules", "entries": sorted}]

# Construit le résultat final dans l'ordre `ordre`, en omettant toute
# section vide — partagé par les modes à liste de libellés fixe (durée,
# récence, alpha).
static func _assembler(ordre: Array[String], buckets: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for label in ordre:
		if buckets.has(label) and not (buckets[label] as Array).is_empty():
			result.append({"label": label, "entries": buckets[label]})
	return result
