# CLAUDE.md

## Le projet

Nom provisoire : **Time To Vroom**.

Jeu de course 3D arcade, sur le modèle d'osu! : les joueurs créent leurs pistes
dans un éditeur intégré, les partagent sur le site du projet, et s'affrontent sur
des leaderboards par piste **et par véhicule**.

- Moteur : **Godot 4.7.1** (version Steam), GDScript
- Cible : PC (exe téléchargeable), pas de navigateur
- Style : arcade, modèles 3D volontairement simples, pas de musique
- Cinq véhicules prévus (liste fermée, `ui/vehicle_roster.gd`) :

| ID interne | Nom affiché | Référence | Le geste |
| --- | --- | --- | --- |
| `gt` | Roadster | Forza Horizon | Gérer une masse, transfert de charge |
| `formula` | Needle | Trackmania | Exécuter à la frame près |
| `superbike` | Ironside | Bécane Bowser | Drift intérieur lourd, engagement |
| `street_bike` | Wasp | Moto légère MKWii | Drift extérieur léger, nervosité |
| `hover` | Halcyon | F-Zero | Inertie pure, anticipation |

L'ID interne est stable (clé de leaderboard, clé de `CarConfig.charger()`) ;
le nom affiché peut encore changer. Chaque véhicule a désormais sa propre
mécanique de conduite — voir « Paramétrage des véhicules » dans Architecture.

La piste de base est conçue pour un véhicule de référence (Roadster), puis
**convertie automatiquement** pour les autres véhicules — modèle osu!std vers
les autres modes. Certaines pistes seront mono-véhicule quand la conversion
n'a pas de sens.

Le multijoueur sera **hébergé sur un serveur**, sans collisions entre
joueurs (décision prise avec l'utilisateur, pas encore d'implémentation —
voir « Ce qu'il ne faut pas faire », pas de site/backend pour l'instant).
Le bouton correspondant existe déjà dans le menu principal, désactivé.

---

## Commandes

```bash
GODOT="D:/DL/JV/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"

# Lancer le jeu
"$GODOT" --path .

# Lancer sans fenêtre (tests, validation de replays, CI)
"$GODOT" --headless --path . --script res://tools/run_tests.gd

# Vérifier qu'un script compile sans lancer le jeu
"$GODOT" --headless --path . --check-only --script res://chemin/script.gd

# Export
"$GODOT" --headless --path . --export-release "Windows Desktop" build/jeu.exe
```

Le chemin contient des espaces : **toujours le mettre entre guillemets**.

Après l'ajout d'un nouveau `class_name`, le cache de classes globales
(`.godot/global_script_class_cache.cfg`) doit être régénéré avant qu'un
`--script` puisse le résoudre, sinon erreur `Identifier "X" not declared` :

```bash
"$GODOT" --headless --editor --quit --path .
```

Piège rencontré : `run/main_scene` doit être écrit sous la section
`[application]` de `project.godot`, pas dans une section `[run]` séparée —
si on le modifie via `ProjectSettings.set_setting("run/main_scene", ...)`
plutôt que par l'éditeur, Godot range le paramètre dans la mauvaise section
et le jeu refuse de lancer (« no main scene defined »).

Piège rencontré : appeler `set_anchors_preset(PRESET_FULL_RECT)` **au
runtime** dans `_ready()` ne fonctionne pas sur le nœud racine d'une scène
chargée comme `main_scene` — son `size` reste `(0, 0)` (et tout ce qui
s'y ancre en plein écran hérite du bug, silencieusement). Il faut déclarer
les ancrages directement dans le `.tscn` (`layout_mode = 3`,
`anchors_preset = 15`, `anchor_right = 1.0`, `anchor_bottom = 1.0`) — voir
`ui/main_menu.tscn`. Ce piège ne touche pas QUE la racine de scène : un
Control ajouté dynamiquement en enfant s'ancre correctement au runtime une
fois son parent déjà bien dimensionné **s'il reste visible depuis sa
création** (`ui/settings_menu.gd`) — mais un Control créé puis `.hide()`é
immédiatement (patron `VehicleMenu`/`CollectionsMenu`/`GhostMenu` : overlay
construit une fois, montré/caché ensuite) peut voir son ancrage plein écran
rester bloqué à `size (0, 0)` **indéfiniment**, y compris longtemps après
que son parent a fini par se dimensionner correctement — et **re-appeler
`set_anchors_preset()` plus tard ne force aucun recalcul** (vérifié : sans
effet). Bug réel rencontré et diagnostiqué via script headless jetable dans
`ui/ghost_menu.gd` (`GhostMenu`) : son panneau restait plaqué en haut à
gauche au lieu d'être centré, malgré des ancrages plein écran corrects —
`GhostMenu.size` était resté à `(0, 0)` depuis sa création, y compris après
plusieurs frames et un `.show()`. `CenterContainer`/toute logique de
centrage EN AVAL fonctionne alors dans un rectangle de taille nulle, sans
erreur ni avertissement. Corrigé en fixant `size`/`position` directement
via `get_viewport_rect()` (fiable dans tous les cas observés) au tout début
de `focus_first()` — appelée juste après `.show()`, quand le parent est
DÉFINITIVEMENT bien dimensionné — plutôt que de dépendre du système
d'ancrage pour ce nœud précis. Tout enfant dont la position dépend de LA
TAILLE de ce nœud (ex. `_back_button`, ancré bas-gauche) doit lui aussi
poser son ancrage à ce même moment, pas dans `_build_ui()` (trop tôt) : les
offsets d'un `set_anchors_preset()` sont calculés UNE FOIS, avec la taille
du parent au moment de l'appel — ils ne se recalculent jamais tout seuls
ensuite, y compris avec `grow_horizontal`/`vertical = GROW_DIRECTION_BOTH`
(tenté puis abandonné pour un centrage manuel de `vbox` : résultat bien
pire qu'avec `CenterContainer`, voir `ui/ghost_menu.gd`).

Piège rencontré, à part mais dans la même famille (rebuild dynamique d'une
liste de lignes UI) : `queue_free()` seul, sans `remove_child()` avant, sur
les enfants d'un conteneur qu'on vide pour le reconstruire (patron
`for child in container.get_children(): child.queue_free()`, très courant
dans `ui/`) — `queue_free()` diffère la suppression réelle à la fin du
frame, donc toute mesure de taille effectuée dans la MÊME fonction juste
après (`get_combined_minimum_size()`, positionnement d'un panneau calculé
sur cette taille) compte encore les anciennes lignes EN PLUS des nouvelles,
avant qu'elles ne soient réellement enfin retirées. Bug réel rencontré dans
`ui/vehicle_menu.gd` : la position du menu déroulant (calculée une fois par
ouverture, jamais recalculée automatiquement ensuite — pas de
`CenterContainer` derrière) était correcte à la première ouverture puis
décalée d'un espace vide aux suivantes, exactement la taille des lignes en
trop. Corrigé partout où ce patron de reconstruction existe (`ui/vehicle_
menu.gd::_refresh()`, `ui/ghost_menu.gd::_clear()`) en appelant
`container.remove_child(child)` avant `child.queue_free()` — retire
immédiatement de l'arbre (donc du calcul de taille), sans rien changer à la
suppression différée elle-même (toujours sûre). Un écran dont le
repositionnement passe par un vrai Container (`CenterContainer` en continu,
via le moteur) est moins exposé — un frame de trop s'auto-corrige au
suivant — mais un panneau positionné une fois manuellement (comme
`ui/vehicle_menu.gd`) ne se corrige jamais tout seul : à vérifier à chaque
nouvel écran qui reconstruit une liste ET se positionne/dimensionne
manuellement dans la même fonction.

Piège rencontré, non résolu dans son mécanisme exact : un clic sur une zone
« vide » de `ui/track_select.gd` (ni bouton, ni champ de texte) n'atteignait
JAMAIS `_unhandled_input()`, vérifié par trace (aucune ligne imprimée, même
après avoir mis `mouse_filter = IGNORE` sur le `ColorRect` de fond ET sur
les `Control` nus utilisés comme spacers — ces derniers sont `STOP` par
défaut, contrairement aux conteneurs `VBoxContainer`/`HBoxContainer`/
`ScrollContainer`, qui sont `PASS` par défaut : vérifié par script jetable,
`Control.mouse_filter par défaut = 0 (STOP)`, `VBoxContainer = 1 (PASS)`).
Un troisième correctif dans ce sens n'a pas non plus suffi — quelque chose
dans cette arborescence profondément imbriquée continue de consommer le
clic avant `_unhandled_input()`, sans qu'on ait isolé précisément quoi.
Contournement qui fonctionne, vérifié en jeu : `_input(event)` À LA PLACE
de `_unhandled_input()` pour ce cas précis — `_input()` s'exécute AVANT tout
le système de `Control` (dispatch GUI compris), donc voit CHAQUE clic sans
dépendre de la chaîne `mouse_filter`, avec une vérification de position
manuelle (`get_global_rect().has_point(...)`) plutôt que de compter sur le
fait qu'aucun `Control` ne l'ait déjà réclamé. Piège séparé rencontré en
essayant de VÉRIFIER ce bug avant de le corriger : `Window.push_input()` en
`--headless`/`SceneTree` ne reproduit PAS fidèlement le test de collision
d'un clic réel contre des `Control` (un même clic simulé atteignait
`_unhandled_input()` avec et sans le correctif attendu) — ce type précis de
bug (routage GUI d'un clic) n'est pas vérifiable de façon fiable en
headless, contrairement aux tailles/positions/valeurs de propriétés
(`get_minimum_size()`, `mouse_filter` par défaut, etc.), qui elles le sont.

---

## Règles non négociables

Ces règles existent parce que **la validation des temps et les fantômes reposent
sur la re-simulation d'un log d'inputs**. Un run est validé en le rejouant : si
la simulation n'est pas parfaitement déterministe, tout le système de
leaderboard s'effondre. Aucune de ces règles ne se négocie pour gagner du temps.

### 1. Simulation en virgule fixe, jamais en flottants

- Toute la simulation utilise des entiers `int` en format **16.16**
  (facteur d'échelle 65536). Voir `res://core/fixed.gd`.
- Aucun `float` ne doit entrer dans un calcul qui influence le résultat d'un run.
- Interdits dans la simulation : `sin()`, `cos()`, `sqrt()`, `atan2()`, `pow()`.
  Utiliser les tables précalculées de `res://core/fixed_math.gd`.
- Les flottants sont autorisés **uniquement** côté rendu et interface.
- Piège GDScript rencontré : à l'intérieur d'une classe qui définit une
  méthode statique du même nom qu'une fonction globale (`sin`, `cos`,
  `sqrt`...), un appel **non qualifié** résout vers la fonction globale
  flottante, pas vers la méthode de la classe — silencieusement, sans erreur
  ni avertissement. Toujours qualifier ces appels (`FixedMath.sin(...)`,
  jamais `sin(...)`, même depuis l'intérieur de `FixedMath` elle-même). Bug
  réel rencontré dans `core/fixed_math.gd` (`cos()` et `length_2d()`
  renvoyaient 0 en silence avant correction).

### 2. Pas plus d'une source de vérité pour le temps

- La simulation avance à **100 Hz fixe**, jamais au rythme du rendu.
- `physics/common/physics_ticks_per_second = 100`
- `physics/common/physics_jitter_fix = 0` (le lissage casse le déterminisme)
- Le numéro de tick est la seule horloge. Interdits dans la simulation :
  `delta`, `Time.get_ticks_msec()`, `Engine.get_frames_per_second()`.
- 100 Hz, pas 60 : passé de 60 à 100 sur demande explicite (le chrono de fin
  de course ne tombait qu'à 60 valeurs de milliseconde sur 1000, jamais aux
  99 autres — un tick de 16,666… ms ne divise pas 1000 exactement). 100 Hz
  donne un tick de 10 ms **pile** (`1000 % 100 == 0`, condition nécessaire
  à un chrono exact) — même cadence que Trackmania. `core/horloge.gd`
  (`Horloge`) est la seule source de la cadence : `TICKS_PAR_SECONDE`,
  `TICKS_PAR_SECONDE_CARRE` (pour les conversions d'accélération, voir
  convention de code plus bas) et `MS_PAR_TICK`. Tout le reste du projet
  (`CarConfig.bake()`, `ReglesCommunes`, `RaceState`, `TimeFormat`, les bancs
  de `tools/`) référence `Horloge` plutôt que d'écrire la cadence en dur —
  ne jamais réintroduire un `60` ou un `3600` littéral pour une conversion
  tick↔seconde. Le chrono de fin de course va plus loin que le tick : voir
  « Chrono, ligne d'arrivée et leaderboard » plus bas, il interpole au
  sous-tick pour obtenir un vrai millième, pas seulement un multiple de
  `MS_PAR_TICK`.

### 3. Aucun moteur physique intégré pour les véhicules

- Ne **jamais** utiliser `VehicleBody3D`, `RigidBody3D` ou Jolt pour un véhicule.
  Ces moteurs ne sont pas déterministes entre machines.
- Le modèle de conduite est écrit à la main : raycasts de suspension, courbe de
  grip, courbe de couple, le tout en virgule fixe.
- Les collisions de la simulation utilisent nos propres tests (AABB, sphères,
  raycasts maison), pas le serveur physique de Godot.

### 4. Zéro allocation dans la boucle de simulation

- Pas de `Array.new()`, pas de `Dictionary` créé par tick, pas de `String`
  construite par tick. Object pooling et tableaux préalloués.
- Une pause de GC = une frame sautée = un run faussé.

### 5. Pas d'aléatoire non contrôlé

- Interdits : `randf()`, `randi()`, `RandomNumberGenerator` non seedé.
- Si de l'aléatoire est nécessaire dans la simulation, il passe par un PRNG
  seedé depuis l'identifiant de la piste, avec un état sérialisé dans le snapshot.

### 6. Séparation stricte simulation / rendu

- `res://sim/` ne connaît **rien** du rendu : pas de `Node3D`, pas de matériaux,
  pas de caméra, pas d'entrée clavier directe.
- `res://render/` lit l'état de simulation et l'interpole. Il ne décide de rien.
- Test mental : la simulation doit tourner à l'identique en `--headless`.
- La souris ne pilote **jamais** le gameplay — pas même la caméra. Elle ne
  sert qu'à naviguer dans `res://ui/` (menus, boutons). Les contrôles de jeu
  sont clavier/manette uniquement ; l'écran de remapping
  (`ui/settings_menu.gd`) ignore explicitement les événements souris pour
  qu'un contrôle ne puisse jamais lui être lié.

---

## Architecture

```
core/       Virgule fixe, maths, PRNG, sérialisation, structures de base
sim/        Simulation déterministe : véhicules, collisions, chrono, checkpoints
map/        Format de piste, chargement, validation, conversion par véhicule
editor/     Éditeur de pistes intégré
render/     Affichage, interpolation, caméra, effets
ui/         Menus, HUD, navigation, écrans de résultats
replay/     Enregistrement des inputs, rejeu, fantômes, validation
net/        Client API du site : envoi des runs, leaderboards, téléchargements
tools/      Scripts utilitaires, tests, outils de build
```

**Le format de piste (`map/`) est le pivot du projet.** L'éditeur, la
simulation, la conversion, la validation et le site en dépendent tous. Toute
modification du format est une décision d'architecture, pas un détail
d'implémentation : passer en mode plan avant d'y toucher.

**Éditeur de piste (`editor/`, `map/track_data.gd`, `map/element_roster.gd`).**
`TrackData` (Resource Godot, `user://tracks/<nom_de_fichier>.tres` via
`ResourceSaver`/`ResourceLoader`) est LE format de fichier — pas encore
`Track` (`map/track.gd`, format en mémoire pour la simulation) :
`TrackData.to_track()` fait la conversion, comme `CarConfig.bake()` pour la
voiture. Le nom de fichier reste un détail technique : l'identité affichée
d'une piste vient de ses champs `nom`/`auteur` (édités dans
`editor/track_editor.gd`, deux `LineEdit` à côté du champ de nom de
fichier), et sa clé de leaderboard est `uid` — une chaîne générée une seule
fois par `TrackData.ensure_uid()` (`format_version` 2) à la première
sauvegarde, jamais recalculée, pour que renommer le `.tres` ne fasse pas
perdre les records associés. `TrackData.load_from_path()` migre les `.tres`
antérieurs (pas d'`uid`) en retombant sur le nom de fichier — en mémoire
seulement, persisté à la prochaine sauvegarde. `map/track_catalog.gd`
(`TrackCatalog.list_tracks()`) est la source unique de la liste des pistes
jouables (piste intégrée + `user://tracks/*.tres`), utilisée à la fois par
`ui/editor_menu.gd` (éditer) et `ui/track_select.gd` (jouer), pour ne pas
dupliquer le parcours du dossier.

`editor/track_editor.gd` (scène autonome comme `main.tscn`, pas un
overlay) édite le centre de piste (clic = ajoute un point, plat pour
l'instant, altitude à venir) et place des éléments depuis la palette
`ElementRoster` (voir « Éléments de piste »), souris pour la caméra libre et
le placement — c'est un outil de création, pas la conduite, donc la règle
« pas de souris pour le gameplay » ne s'applique pas ici (confirmé avec
l'utilisateur). `ui/editor_menu.gd` liste les pistes sauvegardées (nom
affiché, pas le nom de fichier) + « Nouvelle piste », accessible depuis
« Créer une course » dans le menu principal — la piste intégrée n'y
apparaît pas (non modifiable). « Jouer cette piste » sauvegarde et lance
`main.tscn` avec cette piste (`main.gd` en dérive l'ID de leaderboard de
`TrackData.uid`). Le passage d'une scène à l'autre (quelle piste
éditer/jouer) se fait via l'autoload `Session` (`ui/session.gd`, relais
ponctuel, jamais un état durable). Publication sur le site : bouton présent
mais désactivé (« Bientôt disponible ») — hors scope tant que le jeu n'est
pas bon hors ligne (voir « Ce qu'il ne faut pas faire »). L'éditeur en
lui-même reste une coquille pour le placement (tracé + placement + variantes
+ sauvegarde + test en jeu, pas de collision orientée ni d'édition
d'altitude) — mais les éléments posés ont désormais un premier lot d'effets
réels en simulation, voir « Éléments de piste » plus bas et
`docs/matrice-vehicules.md`.

Deux bugs trouvés lors d'une revue de code complète du projet, corrigés :
`_on_save_pressed()` construisait `user://tracks/<nom>.tres` directement
depuis le champ de nom, sans filtrer les caractères — un nom contenant `/`
(ex. `a/b`) produisait un chemin invalide et `ResourceSaver.save()` échouait
en silence (juste un `push_warning`, rien à l'écran). Corrigé avec
`String.validate_filename()` (remplace les caractères interdits par `_`,
natif Godot 4.3+) avant de construire le chemin. Séparément,
`_on_remove_point_pressed()`/`_on_remove_element_pressed()` supprimaient
bien le point/élément en 3D mais oubliaient d'appeler `_refresh_status()`
(contrairement à tous les autres gestionnaires qui mutent l'état) : le
compteur « Points : N / Éléments : N » restait affiché à l'ancienne valeur
jusqu'à la prochaine action. Les deux appels manquants sont ajoutés.

`TrackData` gagne `est_ferme: bool = true` (défaut = comportement historique,
aucune migration nécessaire : les `.tres` existants n'ont pas cette clé,
Godot leur applique le défaut) — `false` pour une piste **point à point**
(rallye), où le dernier point n'est pas relié au premier et la ligne
d'arrivée se retrouve physiquement ailleurs que le départ (voir « Chrono,
ligne d'arrivée et leaderboard »). `to_track()` le propage vers `Track.
est_ferme` (déjà utilisé par `tools/bench_rayon.gd` pour un virage isolé,
maintenant aussi consommé par `sim/race_state.gd` et `render/track_mesh.gd`,
qui adaptent tous les deux leurs boucles `% n` pour ne plus refermer
artificiellement une piste ouverte). `editor/track_editor.gd` affiche l'état
(« Boucle : oui/non ») dans son compteur de statut ; pas encore de bouton
pour le changer depuis l'éditeur (une piste ouverte se construit pour
l'instant par script, comme les pistes de test).

Deux bugs supplémentaires trouvés (et corrigés) en construisant la première
piste point à point : `TrackData.start_transform()` renvoyait un cap figé à
`0`, jamais dérivé du premier segment (`FixedMath.atan2`, même convention que
`sim/car_sim.gd`) — invisible sur un circuit qui démarre plein nord, mais la
voiture partait hors piste dès le premier tick sur toute autre orientation.
Séparément, `main.gd`/`tools/run_tests.gd` appliquaient `Fixed.from_int()` à
la position de départ d'une piste `TrackData` — déjà en Q16.16, contrairement
à `TrackHardcoded.start_transform()` qui renvoie des mètres bruts — ce qui
plaçait la voiture à une position multipliée par 65536, invisible seulement
parce que la piste intégrée démarre à l'origine (0 × 65536 = 0). Les deux
`start_transform()` partagent maintenant le même contrat (Q16.16 direct, cap
dérivé du tracé), documenté en tête de chacune.

**Menus et remapping (`ui/`).** Structure alignée sur une maquette fournie
par l'utilisateur (menu principal + écran de sélection de piste façon
écran de sélection de morceau d'osu!) : les assets changeront, la structure
doit rester. `ui/main_menu.tscn` est la scène principale — aperçu 3D du
véhicule sélectionné (`CarView` dans un `SubViewport`, tourne sur lui-même,
`set_process(false)` pour ne pas laisser `CarView._process()` écraser la
rotation pilotée par le menu — voir piège look_at() ci-dessous) à gauche,
boutons Jouer / Multijoueur / Créer une course / Paramètres / Quitter le jeu
à droite. « Jouer » ouvre `ui/track_select.tscn` (scène autonome) plutôt que
de lancer `main.tscn` directement. « Multijoueur » est présent mais
désactivé (voir « Le projet »). `ui/settings_menu.gd` (remapping des
touches) et `ui/editor_menu.gd` (entrée de l'éditeur, voir « Éditeur de
piste ») s'affichent en overlay dans le menu principal, même mécanique
show/hide qu'avant.

`ui/track_select.gd` (scène autonome) liste les pistes de
`TrackCatalog.list_tracks()` (recherche par nom/auteur fonctionnelle, tri et
profil joueur en placeholder désactivé — définis plus tard) ; sélectionner
une piste recadre un aperçu 3D (`TrackMesh` dans un second `SubViewport`,
caméra orthogonale cadrée sur les bornes XZ de la piste) et rafraîchit le
panneau leaderboard local (voir ci-dessous) et le record personnel. Le
bouton « Changer de véhicule » y ouvre `ui/vehicle_menu.gd`, un menu
déroulant ancré juste au-dessus de ce bouton (pas un overlay plein écran —
voir plus bas) — le choix du véhicule a déménagé ici, il n'y a plus de
bouton Véhicule dans le menu principal. « Options de jeu » est un
placeholder désactivé. « JOUER » passe par `Session` comme « Jouer cette
piste » de l'éditeur.

**Menu contextuel et collections (`ui/track_select.gd`, `ui/collections.gd`,
`ui/collections_menu.gd`).** Clic droit sur une piste → `PopupMenu` adapté
du menu contextuel d'osu! (demande explicite, maquette utilisateur) :
« Gérer les collections... », « Supprimer... », « Effacer les scores
locaux », « Éditer », « Annuler ». « Marquer comme jouée » d'osu! n'a
volontairement pas d'équivalent (pas de filtre « non joué » ici). Supprimer
et Éditer sont désactivés pour la piste intégrée (`builtin: true`, pas de
`path`) ; Supprimer et Effacer les scores locaux passent par un
`ConfirmationDialog` (`dialog.title` forcé à « Confirmation », sinon
« Please Confirm... » en anglais par défaut) avant d'agir — actions
irréversibles. Supprimer appelle `TrackCatalog.delete_track()` (efface le
`.tres`) puis `Collections.remove_track_everywhere()` (pas de référence
morte dans les collections) ; Éditer réutilise le flux `Session` +
`editor/track_editor.tscn` de `EditorMenu`.

L'autoload `Collections` (`ui/collections.gd`, même patron de persistance
tolérante aux pannes que `Leaderboard`, `user://collections.cfg`) associe un
nom de collection à une liste d'`uid` de pistes — organisation purement
locale, aucun rapport avec le futur site. `ui/collections_menu.gd`
(`CollectionsMenu`, même patron d'overlay que `VehicleMenu`) gère toutes les
collections à la fois : un champ texte en haut crée une nouvelle collection
(Entrée), chaque ligne a Renommer / Ajouter-Retirer (agit sur la piste qui a
ouvert le panneau via `open_for()`) / Supprimer. Piège rencontré :
`text_submitted` ne garde pas le focus sur le `LineEdit` une fois que
`_refresh()` a reconstruit les lignes en dessous — sans un `grab_focus()`
explicite après le refresh, créer plusieurs collections à la suite au
clavier ne marchait qu'une fois sur deux.

Dans `ui/track_select.gd`, le menu déroulant « Regrouper par : » fait
basculer la colonne droite entre plusieurs présentations — voir
« Regrouper par : douze modes de tri » plus bas dans Architecture pour le
détail complet (à l'origine, seuls Toutes les pistes / Collections
existaient ; ce paragraphe documente encore l'**accordéon** des
collections, toujours en place tel quel). Une entête par collection
(`▸`/`▾`, compteur), une seule dépliée à la fois (`_expanded_collection`,
cliquer une autre entête referme la précédente — demande explicite). Rien
n'est présélectionné tant qu'aucune collection n'est dépliée. `ui/leaderboard.gd`
gagne `clear_track()` (efface l'historique d'une piste, tous véhicules) et
`map/track_catalog.gd` gagne `delete_track()` (`DirAccess.remove_absolute`)
pour ces actions.
Piège rencontré : `Camera3D.look_at()` lit `global_transform`, qui n'est
fiable que si le nœud est **déjà** dans le `SceneTree` — appelé sur une
caméra tout juste créée mais pas encore `add_child()`ée, l'appel est un
no-op silencieux (la caméra garde son orientation par défaut, -Z), et
l'objet visé n'apparaît que par un minuscule fragment dans un coin de
l'image au lieu d'être cadré. Toujours `add_child()` avant `look_at()`.
Chaque `SubViewport` de rendu 3D isolé (aperçu véhicule, aperçu piste) doit
avoir `own_world_3d = true`, sinon plusieurs `SubViewport` partageraient le
même monde 3D et leurs objets se mélangeraient.

L'autoload `VehicleSelection` (`ui/vehicle_selection.gd`) porte le véhicule
choisi, persisté dans `user://vehicle.cfg` (même tolérance aux pannes que
`Controls` ci-dessous : ID inconnu ou fichier corrompu → premier véhicule de
`ui/vehicle_roster.gd`). `ui/pause_menu.gd` est instancié par
`main.gd` pour la pause en course (Continuer / Redémarrer / Quitter, type
osu!, sans confirmation). « Quitter » (pause ou fin de course,
`main.gd::_on_pause_quit()`, signal partagé par `PauseMenu` et
`FinishMenu`) ramène à `ui/track_select.tscn`, pas au menu principal — on
vient d'y choisir cette piste, c'est là qu'on veut revenir. L'autoload `Controls` (`ui/controls.gd`) porte
l'état des bindings : défauts capturés depuis l'`InputMap` de
`project.godot` au démarrage, remaps persistés dans `user://controls.cfg`
(tolérant aux pannes : fichier absent/corrompu → défauts, jamais de crash).
Toutes les UI de ce dossier sont construites par code dans `_ready()`
(comme `render/`), pas par des `.tscn` détaillés.

**Silhouette par véhicule (`render/car_view.gd`).** Le modèle 3D affiché
dépend du véhicule choisi (`VehicleSelection.selected_id`, lu au `_ready()`)
— une méthode `_build_<archetype>()` par entrée de `ui/vehicle_roster.gd`,
primitives simples assemblées par code (`BoxMesh`/`CylinderMesh`), pas de
modèle importé (ce projet n'a pas de pipeline d'assets 3D, et le style visé
est volontairement simple, cf. « Le projet »). Un ID inconnu retombe
silencieusement sur `gt` (Roadster) — même repli que `CarConfig.charger()`
(voir « Véhicules » ci-dessous) pour la mécanique.

Les deux motos (`superbike`, `street_bike`) et le vaisseau (`hover`) ont en
plus un bonhomme très simple (`_add_rider()`) — même modèle (torse, tête,
bras) pour les trois, seules les couleurs changent pour rester
distinguables. Nœud séparé du corps du véhicule (pas fusionné dans le même
mesh). Les deux voitures (`gt`, `formula`) n'en ont pas.

**Véhicules (`sim/car_config.gd`, `sim/car_sim.gd`, `sim/car_configs/`,
`sim/regles_communes.gd`).** Les 5 identifiants internes (`gt`/Roadster,
`formula`/Needle, `superbike`/Ironside, `street_bike`/Wasp, `hover`/Halcyon)
ont chacun leur propre classe GDScript de configuration
(`sim/car_configs/car_config_<id>.gd extends CarConfig`, valeurs fixées dans
`_init()`) — **volontairement pas des `.tres`** : décision explicite pour ne
pas exposer les réglages comme un fichier de données éditable en texte brut
à côté de l'exécutable. `CarConfig.charger(vehicule_id)` résout l'id vers la
bonne classe, avec repli sur le véhicule par défaut si l'id est inconnu
(même tolérance aux pannes que `Controls`/`VehicleSelection`) ; `main.gd`
l'appelle avec `VehicleSelection.selected_id`.

**Principe d'équilibrage : par le latéral, jamais par le longitudinal.**
Vitesse max, accélération et freinage avantageraient un véhicule sur
*toutes* les pistes s'ils étaient déséquilibrés ; c'est l'adhérence
latérale, le rayon de braquage et le comportement de glisse qui
différencient les véhicules, pour que chacun soit avantagé par un profil de
piste différent (virages serrés vs lignes droites). Modèle "bicyclette +
budget latéral" dans `sim/car_sim.gd` : le cap tourne de `Δψ = v · angle des
roues / empattement`, et `adherence_laterale` est un **budget de correction
par tick** (pas une fraction) — au-delà, ça glisse (`type_glisse` :
`AUCUNE`, `PIVOT_AVANT`, `SAUT_ARC`, `PERMANENTE`). `ReglesCommunes.coef_glisse`
est le levier qui rend la glisse plus rapide que l'adhérence pure sous un
certain rayon (cible ~28 m) ; `perte_vitesse_glisse` (par véhicule) draine
la vitesse **proportionnellement à la saturation du travers**, jamais un
drain plat — sinon un véhicule en glisse permanente (Halcyon) perdrait de
la vitesse même en ligne droite. Conséquence du modèle bicyclette à
connaître : un véhicule **ne tourne plus du tout à l'arrêt** (`Δψ ∝ v`).

PIVOT_AVANT (Roadster) a deux réglages supplémentaires, ajoutés sur retour
manette en main et documentés comme arbitrages en tête de `sim/car_sim.gd` :
`ReglesCommunes.coef_glisse_passif` (1,5, strictement sous `coef_glisse`,
1,8) élargit le budget latéral **en permanence**, pas seulement pendant une
glisse activement engagée — sans lui, la conduite normale du Roadster
tombait au même plafond strict que Needle/Ironside mais sans leur filet de
vitesse ("scrub"), ressenti comme une ligne droite forcée à haute vitesse.
`ReglesCommunes.coef_braquage_glisse` (0,35) ralentit à l'inverse la
convergence de l'angle des roues **pendant** une glisse activement engagée :
une fois lancée, une glisse doit rester difficile à rediriger (comme une
vraie voiture de drift, en plus simple à contrôler), pas suivre le stick
aussi vite qu'en conduite normale.

**Règle du boost** (`sim/regles_communes.gd`, `CarSim.declencher_boost()`) :
poussée **absolue et identique pour tous** (+45 km/h, jamais un
pourcentage), appliquée dans la direction de la **trajectoire** (pas de
l'orientation — un boost pris en dérapage projette donc vers l'extérieur).
La vitesse excédentaire retombe à un **taux fixe** (12 km/h/s), **jamais
indexé sur `decel_naturelle`** (sinon Halcyon garderait son surplus plus
longtemps que les autres). Déclenché depuis le lot « Effets des éléments de
piste » (voir « Éléments de piste » ci-dessous) : `sim/car_sim.gd::
_appliquer_elements()` appelle `declencher_boost()` à l'entrée dans un
élément `boost`. Le saut de Wasp (`SAUT_ARC`) reste, lui, propre au
franchissement d'un obstacle au sol — hors scope du Lot A (voir
« Éléments de piste »), même si la physique de saut sous-jacente est
maintenant aussi réutilisée par l'élément `rampe` (générique, tous
véhicules).

**Interdiction des seuils « N actions en M secondes ».** Aucune mécanique
de coût de ce type (ex. limiter les sauts par fenêtre de temps) : un seuil
brutal devient une cible à optimiser dans un jeu de time attack et il est
illisible pour le joueur. Le coût continu (`cout_vitesse_saut`, drain de
glisse) suffit — si un comportement reste rentable après réglage, monter le
coût correspondant, ne pas ajouter de règle de seuil.

**Deux bancs de mesure** (`tools/bench_equilibrage.gd`,
`tools/bench_rayon.gd`, tous deux `--headless`, déterministes, pilotés par
`tools/bench_pilote.gd` — un contrôleur automatique 100 % virgule fixe,
poursuite de point cible pour la direction, vitesse dérivée du braquage
courant pour éviter de "perdre" un virage déjà engagé) :
- `bench_equilibrage.gd` chronomètre les 5 véhicules sur une piste de
  référence fermée par **symétrie centrale** (une moitié dont la somme des
  virages vaut exactement 180°, rejouée deux fois) et affiche l'écart entre
  eux — cible du cahier des charges : quelques % d'écart. Rampes, plots et
  route dégradée n'étant pas simulés (voir ci-dessus), la piste les
  approxime (altitude sans effet, rétrécissement de piste) ou les omet, et
  l'imprime en tête de sortie pour que le chiffre ne soit pas lu comme
  complet.
- `bench_rayon.gd` mesure, pour une série de virages isolés de rayon
  croissant (10 à 60 m), le temps de passage de chaque véhicule à vitesse
  d'entrée imposée (140 km/h, pour isoler le latéral pur) et identifie le
  rayon où la glisse cesse d'être plus rapide que l'adhérence — le curseur
  d'équilibrage principal du jeu.

Piège rencontré : dans `sim/car_sim.gd`, `Fixed.mul(a, b)` suppose que les
DEUX opérandes sont des grandeurs Q16.16 générales, OU qu'une seule est une
fraction Q16.16 dans `[-1, 1]` multipliant un entier brut (comme
`taux_braquage_par_tick × braquage`, voir plus bas) — jamais deux grandeurs
Q16.16 générales dont une n'est en réalité qu'un entier simple (un signe
`-1/0/1`, un angle en unités brutes potentiellement grand). `Δψ = mul(mul(v,
inv_empattement), angle_effectif)` s'est fait piéger : `mul(v,
inv_empattement)` est une grandeur Q16.16 générale, et la multiplier par
`angle_effectif` (unités brutes, pas une fraction) avec un second `mul()`
divisait le résultat par 65536 en trop — le yaw ne tournait quasiment plus,
et la voiture restait plaquée contre le premier mur venu, détecté en
mesurant un temps de passage qui n'arrivait jamais sur `tools/
bench_equilibrage.gd`. Corrigé avec l'opérateur `*` normal pour ce genre de
multiplication (grandeur Q16.16 générale × entier simple). Verrouillé par
`tools/run_tests.gd::_test_echelle_rotation()`.

Piège rencontré (mesure, pas simulation) : sur une piste OUVERTE à un seul
point de sortie (`tools/bench_rayon.gd`), le dernier point ajouté ne crée
aucun segment après lui — mesurer un temps de passage via
« `segment_index` dépasse l'index de fin de virage » ne se déclenchait
jamais, puisque ce dernier segment était aussi le dernier de toute la
piste. Il faut au moins deux segments de sortie pour qu'il existe un
segment à dépasser une fois le virage franchi.

**Moddage (skins) : décision explicitement reportée, mécanisme revu.**
L'utilisateur voulait au départ une texture unique par élément plaquée sur le
modèle 3D, façon atlas CS:GO/CS2 (comme les skins d'osu!) — **écarté** :
plutôt qu'une image appliquée sur le modèle, les couleurs et motifs seront
appliqués **de base sur les modèles 3D eux-mêmes**, pour faciliter la
personnalisation par les joueurs. Toujours prévu à terme pour tout élément
visuel (menus, piste, véhicules, personnages). La contrainte de hitbox
stable (jamais affectée par une modification visuelle) reste valable tant
qu'elle n'est pas explicitement levée — à reconfirmer avec l'utilisateur au
moment du mode plan dédié, ce nouveau mécanisme rendant peut-être la
question moins centrale si la géométrie elle-même n'est plus modifiable,
seules les couleurs/motifs l'étant. Aujourd'hui rien n'est chargé
depuis des fichiers externes (tout est généré par code au runtime), donc
c'est toujours un changement d'architecture complet, volontairement pas
commencé — à traiter en mode plan dédié quand l'utilisateur voudra s'y
atteler, ce nouveau mécanisme (couleurs/motifs sur le modèle plutôt qu'atlas
texture) devant être précisé à ce moment-là.

**Chrono, ligne d'arrivée et leaderboard (`sim/`, `ui/`).** `sim/race_state.gd`
détecte le franchissement de la ligne de départ/arrivée — une porte calculée
une fois (position, tangente, demi-largeur), vérifiée à chaque tick par
`sim/world.gd` avec la position avant/après. Le segment source de cette porte
dépend de `Track.est_ferme` (propagé depuis `TrackData.est_ferme`, voir
« Éditeur de piste ») : circuit (`est_ferme` vrai, défaut historique) → premier
segment, départ et arrivée confondus, comme avant ; piste **point à point**
(`est_ferme` faux) → **dernier** segment, arrivée physiquement distincte du
départ — le dernier segment de la piste devient alors une zone de
décélération après la ligne, non chronométrée. Sur un circuit, la porte est
aussi le point d'apparition : un garde-fou (`DEPARTED_THRESHOLD`, 3 m)
empêche un faux départ-arrivée au tick 0 en exigeant de s'éloigner d'abord.
Sur une piste point à point, départ et arrivée sont déjà éloignés l'un de
l'autre : ce garde-fou est désactivé (sinon aucune arrivée ne pourrait jamais
se déclencher, la voiture restant tout le run du côté « avant » négatif de
cette porte-là). Un franchissement dans le mauvais sens est ignoré sans effet
de bord : il ne compte jamais comme une arrivée. Le chrono (`current_elapsed`)
ne démarre qu'au premier input actif du joueur (accélérateur, frein ou
braquage — calculé par `sim/world.gd`, transmis à `race_state.tick()`) : tant
qu'il n'a rien pressé, `started` reste `false` et le chrono affiche 0:00.000,
même si la simulation tourne déjà. `finish_ms` et la limite de temps sont
tous deux exprimés relativement à ce premier input, pas au tick absolu de
`World`. Limite de temps fixe à 30 minutes pile (`RaceState.TIME_LIMIT_TICKS`
/ `TIME_LIMIT_MS`, en ticks/ms — jamais en secondes flottantes) : au-delà,
`timed_out` passe à `true` et plus aucun franchissement ne peut se produire ;
le run échoue, rien n'est envoyé au leaderboard.

Le chrono de fin de course est **interpolé au sous-tick**, pas seulement
converti depuis un numéro de tick : à la cadence fixe de la simulation
(`Horloge.TICKS_PAR_SECONDE`, voir règle non négociable n°2), un tick vaut
`Horloge.MS_PAR_TICK` ms — s'arrêter au tick le plus proche du franchissement
donnerait un chrono toujours multiple de `MS_PAR_TICK`, jamais un vrai
millième quelconque (le problème d'origine qui a motivé le passage à 100 Hz).
`RaceState.tick()` calcule déjà `t`, la fraction Q16.16 du tick à laquelle la
ligne est franchie (nécessaire pour vérifier que le franchissement reste dans
la largeur de la porte) ; ce même `t` sert à interpoler le chrono :
`elapsed_fixed = (current_elapsed - 1) * Fixed.ONE + t`, puis
`finish_ms = Fixed.mul(elapsed_fixed, Horloge.MS_PAR_TICK)`. Cas d'usage
volontaire de `Fixed.mul()` sur une grandeur Q16.16 générale (pas une
fraction `[-1, 1]`) multipliée par un scalaire brut — l'inverse du piège
documenté à la règle n°1 : ici on VEUT redescendre à l'échelle brute (des ms
entières), pas garder l'échelle Q16.16.

`ui/time_format.gd::format_ms()` convertit des millisecondes en texte
`m:ss.mmm` (jamais via `Time.get_ticks_msec()`, cf. règle 2 — le tick est la
seule horloge) ; `format_ticks()` reste une enveloppe pour l'affichage en
direct du HUD, où interpoler n'a pas de sens (`ui/hud.gd`). Utilisé aussi par
`ui/finish_menu.gd` (écran de fin de course, même patron que
`ui/pause_menu.gd` : Rejouer / Quitter). L'autoload `Leaderboard`
(`ui/leaderboard.gd`, même tolérance aux pannes que `Controls`) persiste dans
`user://leaderboard.cfg` l'**historique local** de tous les runs terminés par
piste (un run n'écrase jamais un run précédent, conformément à « Données à
enregistrer pour chaque run » ci-dessous) — `runs()` et `personal_best()`
filtrent par véhicule ; `submit_time()`/`best_time_ms()` stockent des
millisecondes (clé `"ms"`), pas des ticks. C'est toujours un sous-ensemble
volontairement léger de ce que décrit « Données à enregistrer pour chaque
run » (pas d'inputs, pas de hash, pas de temps aux checkpoints) — le log
complet reste l'étape 5, hors scope pour l'instant. Les entrées dans l'ancien
format (`"ticks"`, cadence 60 Hz d'avant ce lot) ne sont plus reconnues et
sont ignorées au chargement plutôt que migrées : elles auraient affiché un
temps faux une fois réinterprétées à 100 Hz (un run de 30 s à 60 Hz
afficherait 18 s à 100 Hz) — décision explicite de repartir de zéro plutôt
que de migrer des temps qui ne sont plus comparables (physique différente).
`ui/track_select.gd` affiche cet historique (voir « Menus et remapping »)
avec le véhicule utilisé par entrée — c'est ce qui a motivé le passage d'un
simple record à un historique.

**Système de fantôme (`replay/`, `main.gd`, `ui/ghost_menu.gd`).** Étape 5
du projet : enregistrer le log d'inputs d'un run terminé, le sauvegarder, et
le rejouer en superposition (un second véhicule semi-transparent, piloté
par le log plutôt que par le joueur) pendant une course ultérieure.

`replay/input_crans.gd` (`InputCrans`) est la seule source de vérité pour
la quantification des inputs — sortie de `main.gd` pour être partagée entre
enregistrement et lecture, avec deux moitiés bien séparées : `*_to_cran()`
(float du singleton `Input` → cran entier, jamais appelée pendant la
lecture d'un replay) et `cran_to_fixed_*()` (cran → Q16.16, float-free —
c'est ce contrat qui doit rester identique entre enregistrement et lecture
pour qu'un replay soit bit-exact). `braquage` (signé, `[-127, 127]`) est
décalé de `+QUANT_BI` pour tenir dans un octet non signé
(`PackedByteArray`, `bi_to_octet()`/`octet_to_bi()`).

`replay/replay_data.gd` (`ReplayData extends Resource`, sauvegardé/chargé
via `ResourceSaver`/`ResourceLoader` vers `user://replays/<nom>.tres`,
même patron que `TrackData`) stocke le log **complet depuis le tick 0 de la
scène** — pas depuis le premier input actif — plus `start_tick` (l'index du
tick où `RaceState.started` est devenu vrai) et `hash_final`
(`CarState.compute_hash()`, extrait de l'ancien
`tools/run_tests.gd::_hash_state()` pour être réutilisable). Piège de
correction trouvé en concevant ce lot, pas juste une optimisation : le
chrono ne démarre qu'au premier input actif, mais la simulation tourne dès
le chargement de la scène — si le fantôme était rejoué en lockstep brut
depuis le tick 0, son temps d'attente initial (potentiellement plusieurs
secondes) se cumulerait avec celui du joueur et les deux véhicules
dériveraient l'un par rapport à l'autre. `main.gd::_reset_ghost()` corrige
ça en pré-roulant silencieusement le monde du fantôme jusqu'à
`start_tick` avant la course, puis `_tick_ghost()` ne l'avance plus que
d'un tick par tick une fois `race_state.started` du JOUEUR devenu vrai —
les deux restent alignés sur le même « zéro » de chrono.

`replay/replay_store.gd` (`ReplayStore`) sauvegarde **un fichier par run
terminé**, jamais seulement le meilleur — seule option cohérente avec la
règle déjà en vigueur dans `Leaderboard` (« ne jamais écraser un run par un
meilleur »). `Leaderboard` reste l'unique index : chaque entrée gagne les
clés `"replay"` (nom de fichier) et `"hash"` ; `clear_track()` supprime
aussi les fichiers de replay référencés (sinon des orphelins que plus rien
ne peut lister). `ReplayStore.load_file()` utilise
`ResourceLoader.CACHE_MODE_IGNORE` — pas juste par prudence : un replay
sauvegardé puis relu dans la même session (écran de fin → sélection de
piste → choix du fantôme) sans ce mode donnerait une lecture périmée.

`main.gd` tick un second `World` (`_ghost_world`) totalement indépendant du
joueur, en lockstep juste après le tick du joueur — vérifié qu'aucun état
mutable partagé ne fuit entre deux `World` simultanés
(`tools/run_tests.gd::_test_deux_mondes_isoles()`, toutes les `static var`
de `sim/` sont en lecture seule après initialisation). Le fantôme utilise
sa propre `CarView` (`render/car_view.gd` gagne `vehicle_id_override` et
`alpha`, réglés avant `add_child()` — le véhicule enregistré dans le
replay, pas forcément celui du joueur, en semi-transparent) et se fige
proprement (dernière pose) une fois son log épuisé ou à l'arrivée du joueur
(`_run_over`), jamais d'erreur. Contre-rejeu de validation à l'arrivée
(`main.gd::_valider_replay()`, activable via `VALIDER_APRES_RUN`) : rejoue
le replay qu'on vient d'enregistrer dans un `World` jetable et compare le
hash — `push_warning` en cas de désaccord (signal de déterminisme suspect),
ne bloque jamais la soumission au leaderboard pour ce premier lot.

**Sélection du fantôme par mode, pas par fichier figé
(`replay/ghost_resolver.gd`, `ui/ghost_selection.gd`, `main.gd`,
`ui/ghost_menu.gd`).** Le premier lot (ci-dessus) figeait un nom de fichier
choisi une fois dans `ui/track_select.gd` : battre son record ne changeait
rien à la tentative suivante, il fallait ressortir de la course et
re-sélectionner manuellement. Sur demande explicite, la sélection devient un
**mode** re-résolu à chaque tentative. `ui/ghost_menu.gd` suit une maquette
fournie par l'utilisateur : titre centré, « Aucun fantôme » centré juste
en dessous (même taille que les autres boutons de fantôme, 300×40), puis
trois colonnes côte à côte (`Records mondiaux` / `Mes records` /
`Fantômes enregistrés`) — le tout centré à l'écran via `CenterContainer`.
Un bouton « Retour » indépendant, bas-gauche de l'écran, même taille et
emplacement que celui de `ui/track_select.gd` (PAS un élément du panneau
centré). Chaque ligne porte une barre verticale, grise par défaut,
**verte** sur la ligne qui correspond à la sélection courante — une seule
à la fois, y compris « Aucun fantôme » (verte tant que rien n'a été choisi
explicitement, voir `GhostSelection.selection()` plus bas : le défaut est
`AUCUN`, pas « mon record », pour qu'aucun fantôme ne s'impose sur une
piste jamais configurée). Sélectionner une ligne écrit dans `GhostSelection`
et rafraîchit LE PANNEAU SUR PLACE (jamais de fermeture automatique, sur
demande explicite) — seuls « Retour » et Échap (voir plus bas) le ferment.

- **Mes records** — une ligne par véhicule ayant un temps encore rejouable
  (grisée/désactivée sinon), plus « Véhicule courant » qui suit
  `VehicleSelection`. Battre son record ne change PAS la sélection (elle
  reste « mon record sur ce véhicule ») : c'est simplement le run que ce
  mode désigne qui change, donc le remplacement à la tentative suivante est
  automatique, sans repasser par ce menu.
- **Records mondiaux** — demande le site/backend, explicitement hors scope
  avant l'étape 6 (voir « Ce qu'il ne faut pas faire »). Toutes les lignes y
  sont visibles (même liste de véhicules que « Mes records », pour garder la
  mise en page symétrique et prête pour de vraies données) mais désactivées
  et sans score — pas de mention « Bientôt disponible » (décalait la
  colonne par rapport aux autres, sur demande explicite : l'absence de
  score suffit). Toute la logique de bascule `MONDIAL`→`PERSO` est écrite
  et testée dès maintenant (voir plus bas), il ne restera qu'à brancher une
  vraie source de données.
- **Fantômes enregistrés** — runs épinglés manuellement (voir
  « Enregistrer un run qui n'est pas un record » plus bas), avec suppression
  dédiée derrière confirmation (`ConfirmationDialog`, même patron que
  « Supprimer... »/« Effacer les scores locaux » de `ui/track_select.gd`) —
  **supprime le run entièrement** (entrée de leaderboard + fichier), pas
  seulement le retire de la liste. Décision explicite : sort du principe
  « on garde l'historique », mais cette règle vise le système qui écraserait
  un run silencieusement, pas le joueur qui efface le sien explicitement.

`replay/ghost_resolver.gd` (`GhostResolver`) porte toute la logique de
décision, **statique et pure** (aucune dépendance à un autoload) :
contrainte non négociable de testabilité, `tools/run_tests.gd` tourne via
`--script` et ne charge aucun autoload. `resolve(selection, runs,
vehicule_courant, records_mondiaux) -> String` cherche explicitement le
minimum dans `runs` (jamais « le premier de la liste » — ne dépend donc pas
de l'ordre fourni par l'appelant) et ignore une entrée dont le fichier de
replay n'existe plus (`ReplayStore.exists()`, statique lui aussi, pas un
autoload — appelable ici sans casser la contrainte de testabilité). En
mode `MONDIAL`, la dégradation vers `PERSO` (« si le record perso est plus
rapide que le WR stocké, on l'a battu, on affronte donc son propre
record ») est calculée à la résolution, **jamais écrite dans la sélection
stockée** — le choix `MONDIAL` du joueur doit survivre intact jusqu'à ce
qu'un vrai classement mondial existe. Le mode est persisté en **chaîne**
(`source_name()`/`source_from_name()`), pas en `int` d'enum brut : un enum
sérialisé tel quel se corromprait silencieusement au moindre
réordonnancement futur — même précaution que les ID de véhicule/piste,
toujours stockés en chaîne ailleurs dans le projet.

`ui/ghost_selection.gd` (autoload `GhostSelection`) est **stockage seul**
(`user://ghosts.cfg`, par piste, même tolérance aux pannes que
`Controls`/`Leaderboard`) — ne connaît ni `Leaderboard` ni
`VehicleSelection`. Les autoloads de ce projet restent des îlots
indépendants (aucun n'appelle un autre autoload) : l'orchestration
`GhostResolver.resolve(GhostSelection.selection(uid), Leaderboard.runs(uid),
VehicleSelection.selected_id, [])` vit dans les appelants (`main.gd`,
`ui/track_select.gd`), pas dans l'autoload. `Session.pending_replay_file`
est supprimé : l'état est désormais durable et indexé par piste, un relais
à usage unique n'a plus de sens.

`main.gd::_resoudre_fantome()` remplace l'ancien `_load_ghost()` : appelée
en tête de `_reset_ghost()`, donc à **chaque** tentative (bouton
« Rejouer », raccourci `reinitialiser`, redémarrage depuis la pause), pas
une seule fois au chargement de la scène. Court-circuit obligatoire — pas
juste une optimisation — si le fichier résolu n'a pas changé : `resolve()`
touche le disque (`ReplayStore.load_file()`, qui force
`CACHE_MODE_IGNORE`, jamais mis en cache par le moteur) et un replay de
plusieurs minutes pèse plusieurs centaines de Ko à reparser ; sans ce
court-circuit, relancer 40 fois la même piste contre le même record
relirait 40 fois le même fichier. Piège de revue trouvé et corrigé avant
livraison : `queue_free()` sur l'ancienne `CarView` du fantôme sans
`remove_child()` immédiat laissait l'ancien nœud rendu un frame de plus
(deux fantômes visibles à l'écran le temps d'un frame) — `queue_free()`
diffère la destruction à la fin du frame, `remove_child()` retire
immédiatement le nœud de l'arbre. Second piège trouvé et corrigé : le
double `sample()` anti-lerp doit avoir lieu **après** le pré-roulement
jusqu'à `start_tick`, pas avant — chaque tick du pré-roulement ré-échantillonne
la vue, donc un double `sample()` placé avant serait entièrement écrasé dès
que `start_tick >= 2`, ne laissant l'anti-lerp fonctionner que par chance
(le fantôme ne bouge pas avant son premier input actif, donc les deux
poses finissent identiques aujourd'hui — mais ça ne tient qu'à ce hasard).

**Enregistrer un run qui n'est pas un record (`ui/finish_menu.gd`).** Le
mode `PERSO` remplace déjà automatiquement le fantôme quand un run bat le
record — mais un run qui ne le bat pas resterait introuvable ailleurs que
dans l'historique brut du leaderboard. `FinishMenu.show_result()` affiche
alors un bouton « Enregistrer ce fantôme » (uniquement quand le run n'est
PAS un record et qu'un replay a bien été sauvegardé) qui épingle le run
(`Leaderboard.set_pinned()`) et atterrit dans « Fantômes enregistrés ».

Trou connu, signalé mais pas traité : `TrackData` n'a pas de numéro de
révision de contenu — un replay enregistré avant une modification de la
piste désynchronise silencieusement. Garde minimale en place
(`replay.track_uid == _track_id`, sinon le fantôme est ignoré avec un
avertissement) ; un vrai correctif attend une révision de piste dans
`TrackData`, hors scope ici. Ce trou reste atteignable plus facilement
qu'avant : une fois le mode `PERSO` choisi une fois pour une piste (le
défaut reste `AUCUN` tant que rien n'a été choisi, voir plus haut), il se
réapplique automatiquement à chaque tentative — éditer sa piste puis la
relancer peut donc désynchroniser un fantôme sans qu'une NOUVELLE action
délibérée ne l'ait redéclenché. Signalé, pas corrigé dans ce lot.
Second trou, mineur : rien n'efface une sélection `MANUEL` épinglée sur un
replay détruit par `Leaderboard.clear_track()` ou `TrackCatalog.delete_track()`
en dehors de `GhostMenu` (qui, lui, gère ce cas à la suppression) — la
résolution reste sûre (`resolve()` renvoie `""` proprement, `main.gd`
n'affiche alors aucun fantôme), mais le bouton peut afficher « Fantôme :
choisi » pour un fichier qui n'existe plus tant qu'on n'a pas rouvert le
menu. `CarState.compute_hash()` n'inclut pas non plus les champs ajoutés
par le lot « Éléments de piste » (`controle_perdu_ticks`,
`saut_gravite_courante`, `elements_dans`, `elem_*`) — délibéré, pour que
l'extraction depuis `tools/run_tests.gd::_hash_state()` reste prouvée
neutre (`REFERENCE_HASH` inchangé) ; à combler dans un lot séparé avec
régénération explicite du hash.

**Menu déroulant de véhicule (`ui/vehicle_menu.gd`).** Sur demande explicite
(maquette utilisateur) : l'ancien overlay plein écran « Choix du véhicule »
(assombrissait tout l'arrière-plan, listait référence + geste par véhicule)
est remplacé par un petit menu déroulant ancré juste au-dessus du bouton
« Changer de véhicule » de `ui/track_select.gd` — le reste de l'écran
(leaderboard, aperçu, liste des pistes) reste visible et net derrière,
aucun assombrissement. Cliquer un véhicule le sélectionne ET ferme le menu
(comportement dropdown, pas de bouton « Retour ») ; cliquer n'importe où
ailleurs sur l'écran ou Échap ferme sans rien changer (`_on_background_input()`
sur un `Control` plein écran invisible, mouse_filter STOP — les clics sur
le petit panneau lui-même ne remontent jamais jusque-là, comportement
standard de propagation des `Control` imbriqués). Seuls les noms des
véhicules sont listés (pas référence/geste, qui restent dans
`ui/vehicle_roster.gd` et `docs/matrice-vehicules.md` si besoin ailleurs).

Position et taille de ce petit panneau calculées directement sur
`_anchor_button.global_position`/`.size` et `get_viewport_rect()` — jamais
via les ancrages Godot, pour la même raison que `ui/ghost_menu.gd` (voir le
piège `PRESET_FULL_RECT` en tête de ce fichier) : ce nœud est créé puis
`.hide()`é avant que son parent ait sa taille finale. Bug réel trouvé et
corrigé pendant ce lot, distinct de celui de `GhostMenu` mais dans la même
famille (voir le piège `remove_child()`/`queue_free()` en tête de ce
fichier) : `_refresh()` reconstruit les lignes du menu à chaque ouverture ;
sans `remove_child()` avant `queue_free()`, la hauteur du panneau (calculée
juste après, pour le positionner) comptait encore les anciennes lignes en
plus des nouvelles — correct à la première ouverture, décalé (un grand
espace vide sous « Halcyon ») à partir de la deuxième. `ui/ghost_menu.gd`
avait le même patron de reconstruction (protégé de la même conséquence
visible par `CenterContainer`, qui se re-corrige tout seul au frame
suivant) — corrigé par précaution aux deux endroits.

Second bug trouvé et corrigé, purement visuel : `focus_first()` donnait
systématiquement le focus clavier à la PREMIÈRE ligne (Roadster), pas au
véhicule réellement sélectionné — l'anneau de focus par défaut de Godot
(toujours visible sur la ligne qui a le focus) restait donc figé sur
Roadster à chaque ouverture, quel que soit le véhicule choisi. Une première
correction a fait pointer le focus sur le véhicule réellement sélectionné
ET ajouté une coloration verte du texte comme second indicateur — jugée
inutile et mal rendue à l'usage (retour utilisateur direct), retirée :
l'anneau de focus (désormais correctement positionné) reste le seul
indicateur de sélection à l'ouverture du menu.

**Regrouper par : douze modes de tri (`map/track_grouping.gd`,
`map/track_data.gd`, `map/track_catalog.gd`, `ui/track_select.gd`).** Sur
demande explicite, façon osu! : le menu « Regrouper par : » passe de 2 à 12
entrées. La plupart affichent des **sections toujours dépliées** (pas
l'accordéon des collections, qui reste le seul mode replié/déplié — voir
plus haut) : un `Label` d'entête non interactif par section, suivi des
lignes habituelles (`_build_track_row()`, inchangé). Trois entrées restent
des placeholders désactivés (« Par date de création », « Par difficulté »,
« Par note reçue »), suffixées « (bientôt disponible) », même patron que
« Leaderboard en ligne » juste à côté — toutes trois demandent soit le
site/backend (hors scope, CLAUDE.md), soit une mécanique déjà explicitement
reportée (la difficulté « calculée rétroactivement, plus tard », badge
neutre existant dans `_build_track_row()`).

`map/track_grouping.gd` (`TrackGrouping`) porte toute la logique de
section/tri, **statique et pure** : même contrainte de testabilité que
`replay/ghost_resolver.gd` (`tools/run_tests.gd` ne charge aucun autoload).
Les données qui viennent de `Leaderboard` (autoload) sont donc précalculées
par `ui/track_select.gd` (`_meilleurs_temps_par_uid()`/
`_derniers_joues_par_uid()`, uid → valeur, absent = jamais joué) et passées
en paramètre, jamais lues directement dans `TrackGrouping`. Chaque fonction
renvoie `Array[{"label": String, "entries": Array[Dictionary]}]`, sections
déjà triées et ordonnées, une section vide n'est jamais incluse.

- **Par créateur / Par titre** — même fonction (`sections_alpha()`,
  `champ` = "auteur" ou "nom") : A → Z, puis « 0-9 », puis « Autre »,
  pistes triées alphabétiquement (`String.naturalnocasecmp_to()`) dans
  chaque section. Premier caractère normalisé pour quelques accents
  français courants (table de repli, pas un normalisateur Unicode complet) ;
  chiffre → « 0-9 » ; vide ou symbole → « Autre ».
- **Par date d'ajout** — nécessite un nouveau champ, `TrackData.date_ajout`
  (chaîne ISO, généré une seule fois à la première sauvegarde par
  `ensure_date_ajout()`, même patron qu'`ensure_uid()`, appelé juste à côté
  dans `editor/track_editor.gd`). Les pistes sauvegardées avant l'ajout de
  ce champ sont migrées en mémoire dans `TrackData.load_from_path()` en
  repli sur la date de modification du fichier (`FileAccess.
  get_modified_time()`) — même principe que la migration d'`uid` juste au-
  dessus, jamais une case « Date inconnue » par défaut pour les pistes déjà
  existantes. Sections par jour calendaire, la plus récente en premier,
  « Date inconnue » en dernier si la migration elle-même échoue.
- **Par durée** — aucune donnée dédiée : approximée par le meilleur temps
  personnel du joueur sur la piste, tous véhicules confondus (`Leaderboard.
  runs(uid)`, déjà trié par temps croissant, premier élément). Tranches
  fixes (< 30 s, 30 s–1 min, 1–2 min, 2–5 min, > 5 min), la plus courte en
  premier, « Durée inconnue » en dernier pour une piste jamais jouée PAR CE
  JOUEUR (donnée strictement locale, pas un temps de référence objectif).
- **Par véhicule** — aucune piste n'a de restriction de véhicule aujourd'hui
  (le système de conversion mono-véhicule mentionné dans « Le projet »
  n'est pas construit) : une seule section « Tous les véhicules » contenant
  tout, triée alphabétiquement — prête à se décliner en sections par
  véhicule le jour où des pistes mono-véhicule existeront, sans changer la
  fonction appelante.
- **Mes pistes** — filtre `filtered` sur `not builtin`, liste plate (pas de
  sections). Comme il n'existe aucun système de téléchargement/partage de
  pistes, TOUTE piste locale non intégrée est nécessairement créée par le
  joueur lui-même sur cette machine — ce mode est donc aujourd'hui
  strictement équivalent à « Toutes les pistes » moins la piste intégrée,
  en attendant qu'un vrai système de partage existe.
- **Pistes récemment jouées** — sections par récence du dernier run (tous
  véhicules), la plus récente en premier : Aujourd'hui (< 1 j), Cette
  semaine (< 7 j), Ce mois-ci (< 30 j), Il y a plus d'un mois, « Jamais
  jouée » en dernier (pas une valeur de récence, n'a pas sa place ailleurs
  que tout en bas).

Présélection de piste généralisée : l'ancienne condition (`_group_mode ==
0`) devient `_group_mode != GroupMode.COLLECTIONS or _expanded_collection
!= ""` — tous les nouveaux modes affichent tout immédiatement comme
« Toutes les pistes », seul l'accordéon des collections a un état replié à
gérer.

Testé : `tools/run_tests.gd` passe (269 tests — 29 nouveaux sur
`TrackGrouping`, bornes exactes de chaque classification testées
directement sur les fonctions privées par convention (`_alpha_label()`,
`_duree_label()`, `_recence_label()`), pas seulement via les fonctions
publiques —, hash de régression inchangé : ce lot ne touche rien dans
`sim/`). Comme documenté juste au-dessus pour le menu de véhicule, cette
suite de tests ne peut PAS voir une erreur dans `ui/track_select.gd`
(dispatch du menu, rendu des sections) — vérifié en jeu, tous les modes
testés manuellement par l'utilisateur sans erreur en console.

---

## Vocabulaire du projet

Employer ces termes, dans le code comme dans les échanges :

| Terme | Sens |
| --- | --- |
| **piste** | Le circuit créé par un joueur (jamais « map » ni « niveau » dans le code) |
| **run** | Une tentative, du départ à l'arrivée ou à l'échec |
| **replay** | Le log d'inputs d'un run, rejouable et vérifiable |
| **fantôme** | Un replay affiché en superposition pendant qu'on joue |
| **checkpoint** | Élément **invisible pour le joueur** posé par le créateur ; le franchir (dans n'importe quel ordre) valide l'emplacement de réapparition courant |
| **repop** | Position de réapparition utilisée après une chute/un obstacle mortel — le dernier checkpoint franchi, ou un point généré automatiquement le long du tracé tant qu'aucun n'a encore été franchi |

Les checkpoints sont **optionnels** pour le créateur. Les points de repop
générés automatiquement, eux, existent toujours le long du tracé — pour
qu'une piste sans aucun checkpoint reste jouable.

**Décision explicite : pas de modèle façon Mario Kart Wii.** L'idée
initiale — franchissement dans un ordre imposé, anti-raccourci strict —
est écartée : elle ouvrirait la porte à des stratégies de glitch/raccourci
extrême (des runs de quelques secondes sur des pistes prévues pour durer
bien plus longtemps), ce qui demanderait un leaderboard séparé pour ces
runs-là — plus de travail que voulu pour l'instant. Le modèle retenu est
volontairement permissif : un checkpoint ne fait que mettre à jour le point
de réapparition, aucun ordre n'est imposé, aucun raccourci n'est détecté ni
pénalisé. Pas encore implémenté (dépend du système de repop lui-même,
toujours à construire, et de la détection d'une "chute" — voir « Ordre de
travail », étape 3) — cette entrée documente la décision de conception, pas
un état livré.

---

## Éléments de piste

Liste fermée (`map/element_roster.gd`, source unique — id stable, nom
affiché évolutif). Ne pas en ajouter sans décision explicite.

- Route normale (`route_normale`)
- Route qui ralentit (`route_ralentit`)
- Route qui dégrade les contrôles (`route_degrade_controles`)
- Vide, comme un trou dans la route (`vide`)
- Route aimantée, façon Mario Kart 8 / F-Zero (`route_aimantee`)
- Barrière, délimite/guide (`barriere`)
- Mur (`mur`)
- Obstacle bloquant (`obstacle_bloquant`)
- Obstacle qui ralentit au contact, type plot de chantier (`obstacle_ralentit`)
- Obstacle mortel (`obstacle_mortel`)
- Rampe (`rampe`)
- Boost (`boost`)
- Ligne de départ / d'arrivée, un seul élément ou deux au choix du créateur (`ligne_depart_arrivee`)
- Checkpoint (`checkpoint`)

Chaque élément doit avoir un comportement **différent selon le véhicule**. C'est
ce qui justifie d'avoir trois leaderboards plutôt qu'un. La matrice
véhicule × élément est la référence : `docs/matrice-vehicules.md`.

**Variantes.** Un élément peut avoir plusieurs variantes : même comportement,
modèle 3D et hitbox différents (ex. `barriere` : `campagne` et `ville`).
Une variante ne change **jamais** le comportement, seulement l'apparence/la
forme — sinon c'est un élément différent, pas une variante. Les éléments
sans variante spécifique portent une unique variante `defaut` en attendant.
La variante reste purement déclarative même côté simulation : `map/track.gd`
(`Track.elem_kind`) ne porte que le TYPE de chaque élément, jamais sa
variante — la faire porter jusqu'à `sim/` inviterait à violer cette règle.

**Effets en simulation — Lot A / Lot B (voir `sim/element_effects.gd`,
`sim/car_sim.gd`, `docs/matrice-vehicules.md`).** Le premier lot d'effets
(« Lot A ») est en place : `route_ralentit`, `route_degrade_controles`,
`route_aimantee`, `obstacle_ralentit`, `boost`, `rampe` et `obstacle_mortel`/
`vide` (repli explicite — arrêt net + verrou de direction, pas encore une
vraie mort/réapparition, voir « État actuel ») ont un vrai effet en jeu ;
`route_normale` et `ligne_depart_arrivee` restent des no-op assumés (la
porte de départ/arrivée vient toujours de `sim/race_state.gd`, jamais d'un
élément posé). Détection par rayon fixe autour du point de l'élément
(`TrackData` ne stocke pas de taille) — approximation assumée, documentée
comme telle dans `sim/element_effects.gd`. **Lot B, pas encore traité** :
`mur`, `obstacle_bloquant`, `barriere` (collision orientée contre un
obstacle placé n'importe où — `editor/track_editor.gd` écrit d'ailleurs
`rotation = 0` pour tout élément aujourd'hui, donc ça demande aussi du
travail éditeur) et `checkpoint` (invisible pour le joueur, valide un point
de réapparition — voir « Vocabulaire du projet » ; pas d'anti-raccourci,
décision explicite).

---

## Conventions de code

- **Typage statique obligatoire** partout : `var vitesse: int = 0`,
  `func avancer(tick: int) -> void:`. Aucune variable non typée dans `sim/`.
- `snake_case` pour variables et fonctions, `PascalCase` pour les classes.
- Une classe par fichier, `class_name` déclaré en tête.
- Les constantes de gameplay vont dans des fichiers de configuration dédiés,
  jamais en dur au milieu du code — elles seront réglées à la manette.
- Commentaires en français, courts, seulement quand le « pourquoi » n'est pas
  évident. Ne pas paraphraser le code.
- Pas de `get_node()` avec des chemins en dur : `@onready` ou `@export`.
- Dans `sim/`, les vitesses sont stockées en **mètres par tick** (pas par
  seconde). Une constante de configuration exprimée en unité physique par
  seconde (accélération en m/s², par exemple) traverse donc **deux**
  conversions tick→seconde et doit être divisée par
  `Horloge.TICKS_PAR_SECONDE_CARRE` (`core/horloge.gd`) au chargement — une
  seule division par `Horloge.TICKS_PAR_SECONDE` ne suffit que pour les
  grandeurs déjà « par tick » en sortie (une vitesse cible, un taux
  angulaire). Bug réel rencontré dans `sim/car_config.gd::bake()`
  (accélération 60× trop rapide, à l'époque où la cadence était encore
  écrite en dur). Vérifier ce point à chaque nouveau paramètre physique —
  et ne jamais écrire la cadence en dur, toujours passer par `Horloge`.
- Pour centrer un bloc de contrôles dans `ui/`, utiliser `CenterContainer`
  plutôt qu'un `set_anchors_preset(PRESET_CENTER)` + `position` calculée à
  la main — cette dernière méthode suppose de connaître la taille finale du
  contenu à l'avance et donne un résultat décalé dès que le contenu change
  (bug réel rencontré sur les trois menus). `CenterContainer` se recalcule
  tout seul.
- Un écran `ui/` construit une fois (`_ready()`) puis simplement montré/caché
  (`show()`/`hide()`) doit **rafraîchir son propre état à chaque
  affichage** (voir `SettingsMenu.focus_first()`), pas seulement à sa
  construction — sinon il affiche des données périmées si le state a changé
  pendant qu'il était caché.
- Piège rencontré : la convention d'orientation de `sim/car_sim.gd`
  (`yaw = 0` → +Z, braquage positif vers +X) ne correspond **pas** au
  repère que Godot construit pour une caméra qui regarde vers +Z avec un
  « haut » +Y — le vecteur « droite » que `look_at()` calcule (produit
  vectoriel avant × haut) pointe alors vers -X, pas +X. Deux bugs réels en
  ont découlé : la caméra de poursuite se plaçait devant la voiture au lieu
  de derrière (il manquait un décalage de PI radians entre `yaw` et
  `rotation.y` dans `render/car_view.gd` — Godot considère qu'un nœud
  « regarde » vers -Z par défaut, pas +Z), et les touches gauche/droite
  étaient visuellement inversées une fois la caméra corrigée (corrigé dans
  `main.gd` en inversant le mapping clavier, pas la convention de `sim/`,
  qui reste correcte). Le sens de rotation de `rotation.y` est piégeux à
  calculer à la main : vérifié empiriquement via un script headless jetable
  plutôt que par le calcul.

---

## Données à enregistrer pour chaque run

Le système de difficulté et de classement sera calculé **rétroactivement**, plus
tard. Il faut donc tout logger dès maintenant, sinon les données sont perdues à
jamais. Pour chaque run terminé :

joueur, piste, version de la piste, véhicule, mods actifs, temps final, temps à
chaque checkpoint, nombre de tentatives dans la session, date, version du jeu,
log d'inputs complet, hash de l'état final.

Ne jamais écraser un run par un meilleur : on garde l'historique.

---

## Ce qu'il ne faut pas faire

- Ne pas « optimiser » en repassant un calcul de simulation en flottants.
- Ne pas ajouter de dépendance externe sans validation préalable.
- Ne pas toucher au format de piste sans passer par le mode plan.
- Ne pas ajouter d'éléments de piste hors de la liste fermée ci-dessus.
- Ne pas travailler sur le site ou le backend : c'est la dernière étape du
  projet, le jeu doit être bon hors ligne d'abord.
- Ne pas régler le *feeling* de conduite à ma place : exposer les paramètres,
  je les ajuste manette en main.

---

## Méthode de travail

- Lire les fichiers concernés avant de proposer une modification.
- Après un changement dans `sim/`, lancer les tests de déterminisme
  (`tools/run_tests.gd`) et vérifier que le rejeu d'un replay de référence donne
  exactement le même temps.
- Pour toute décision d'architecture, passer en mode plan et proposer les options
  avec leurs compromis avant d'écrire du code.
- Si une règle de ce fichier bloque une solution, le dire plutôt que la
  contourner silencieusement.

---

## État actuel

**Étape 1 jouable.** `core/`, `sim/`, `map/`, `render/`, `ui/` ont une première
implémentation ; `tools/run_tests.gd` fait passer 203 tests (arithmétique
fixe, rejeu déterministe, détection de ligne d'arrivée et de temps écoulé —
circuit et point à point —, non-régression par hash de référence). Le circuit de `map/track_hardcoded.gd` est un échafaudage
volontaire, pas le format de piste final. Une première version se refermait
par une longue diagonale qui traversait une autre partie du tracé (voir le
piège documenté en tête de ce fichier) — corrigé : le tracé actuel referme la
boucle sans croisement ni proximité de moins d'une largeur de piste entre
deux segments non adjacents. La voiture peut reculer (voir `sim/car_sim.gd` —
accélérateur et frein poussent chacun dans leur sens, plus de blocage à
l'arrêt). Le modèle initial partagé par tous les véhicules (une seule
`vitesse_max_kmh`, traînée proportionnelle `trainee`) a depuis été remplacé
par un modèle par véhicule — voir « Paramétrage des véhicules » ci-dessous ;
`trainee` et `frottement_roulement_ms2` n'existent plus dans `CarConfig`.

Menu principal, remapping des touches (clavier/manette, persistant, tolérant
aux pannes, affichage localisé selon la disposition clavier active) et pause
en course sont en place — voir la section « Menus et remapping » dans
Architecture. Testé manuellement : navigation clavier/souris/manette, remap
avec retrait automatique des conflits, persistance entre relances du jeu,
pause qui gèle bien la simulation.

Chrono, ligne de départ/arrivée (franchissement dans le bon sens uniquement),
limite de temps de 30 minutes et record local persistant sont en place —
voir la section « Chrono, ligne d'arrivée et leaderboard » dans Architecture.
C'est un premier morceau de l'étape 3 ci-dessous ; checkpoints et repop
restent à faire.

Sélection du véhicule dans le menu principal en place (5 véhicules, voir
« Le projet ») — persistée, tolérante aux pannes, même patron que le
remapping des touches. Chaque véhicule a sa propre silhouette 3D (voir
« Silhouette par véhicule » dans Architecture) et, depuis le lot
« Paramétrage des véhicules » (ci-dessous), sa propre mécanique de conduite
complète — plus de config partagée.

**Paramétrage des véhicules (`sim/car_config.gd`, `sim/car_sim.gd`,
`sim/car_configs/`, `sim/regles_communes.gd`).** Les 5 véhicules ont
désormais des identités de pilotage distinctes et chiffrées, d'après
`Paramétrage-Véhicules.md`. Voir « Véhicules » dans Architecture pour le
détail. Testé : `tools/run_tests.gd` passe (114 tests, hash de régression
mis à jour), `tools/bench_equilibrage.gd` et `tools/bench_rayon.gd`
tournent et produisent des mesures pour les 5 véhicules (Ironside ne
termine pas l'épingle serrée de la piste de référence avec le pilote
automatique actuel — signalé, pas un crash). Le *feeling* n'est pas réglé
— valeurs de départ plausibles issues du cahier des charges, à ajuster à
la manette ; le banc `bench_rayon.gd` montre déjà que la glisse de Roadster
domine sur toute la plage de rayons testée (10-60 m) avec les valeurs
actuelles, signal de réglage attendu et documenté par l'outil lui-même.

**Passage à 100 Hz et chrono au millième réel (`core/horloge.gd`,
`sim/race_state.gd`, `ui/time_format.gd`, `ui/leaderboard.gd`).** Sur
constat utilisateur que le chrono ne tombait jamais que sur six valeurs de
milliseconde (60 Hz ne divise pas 1000) : simulation passée à 100 Hz (voir
règle non négociable n°2) et chrono de fin de course interpolé au sous-tick
(voir « Chrono, ligne d'arrivée et leaderboard » dans Architecture) — un
temps peut désormais tomber sur n'importe lequel des 1000 millièmes.
`Leaderboard` stocke des millisecondes (clé `"ms"`), pas des ticks ;
décision explicite de **ne pas migrer** l'historique local 60 Hz
(non comparable à la nouvelle physique) — les anciennes entrées sont
ignorées au chargement plutôt que réinterprétées à la nouvelle cadence, ce
qui aurait affiché des temps faux. Cela rend obsolète la mention plus haut
d'une migration automatique de `Leaderboard` depuis l'ancien format
best-only : cette migration-là existe toujours dans l'historique de ce
fichier mais n'a plus d'effet, ses entrées étant elles aussi en `"ticks"`.
Réserve de calibration : le quantum d'accélération Q16.16 (~0,153 m/s² à
100 Hz, contre ~0,055 à 60 Hz) fait dévier `decel_naturelle_ms2 = 0.5`
d'Halcyon d'environ 8 % de sa valeur — la fiche la plus sensible à ce
paramètre. Pas de correctif propre sans toucher au format virgule fixe
(hors scope) ; signalé pour ajustement à la manette.

Première version du format de piste et de l'éditeur en place (`TrackData`,
`editor/track_editor.gd`, voir « Éditeur de piste » dans Architecture) — sur
demande explicite, donc en avance sur l'ordre de travail ci-dessous (étapes
2 et 4 attaquées avant que l'étape 3 soit finie). C'est volontairement une
coquille : tracé plat éditable, palette complète (liste fermée + vide/mur/
route aimantée + variantes), sauvegarde/chargement locaux, test en jeu.
Aucun élément placé n'a d'effet en simulation, la publication est désactivée.

Menu principal et sélection de piste retravaillés d'après une maquette
utilisateur (voir « Menus et remapping » dans Architecture) : aperçu 3D du
véhicule au menu principal, nouvel écran `ui/track_select.gd` (recherche
fonctionnelle, aperçu 3D de piste, leaderboard **local** avec véhicule par
entrée, record personnel, liste des pistes avec nom/auteur). A entraîné deux
changements de format en avance sur leur étape : `TrackData` gagne
`nom`/`auteur`/`uid` (`format_version` 2, migration automatique des
anciennes pistes) pour que l'écran affiche une identité stable et que
renommer un fichier ne perde plus son record ; `Leaderboard` passe d'un
best-only à un historique local par piste+véhicule (migration automatique
de l'ancien format). Multijoueur, leaderboard en ligne, profil joueur,
options de jeu et fantômes sont des placeholders désactivés — dépendent du
site/backend ou de l'étape 5, hors scope ici. Testé manuellement en jeu :
menu → sélection de piste → changement de véhicule (record personnel mis à
jour) → course sur la piste intégrée, aller-retour complet sans erreur.

Menu contextuel (clic droit) sur les pistes de `ui/track_select.gd` et
système de collections en place (voir « Menu contextuel et collections »
dans Architecture) — adapté du clic droit d'osu! sur demande explicite,
« Marquer comme jouée » écarté (pas d'équivalent). Nouvel autoload
`Collections`. Testé manuellement en jeu : création de plusieurs
collections au clavier à la suite, ajout/retrait/renommage/suppression
d'une collection, regroupement accordéon (une seule dépliée à la fois),
effacement des scores locaux d'une piste (n'affecte pas les autres pistes),
suppression d'une piste (disparaît de la liste, désactivée pour la piste
intégrée) — tout sans erreur.

**Réglage du drift et de l'adhérence du Roadster (`sim/regles_communes.gd`,
`sim/car_sim.gd`, `sim/car_configs/*.gd`).** Plusieurs retours manette en
main enchaînés sur le Roadster (`PIVOT_AVANT`), dans l'ordre :

- Angle de travers en glisse resserré : `ReglesCommunes.tan_pivot_max`
  passe de tan(35°) à tan(20°) — la trajectoire divergeait trop de la
  direction du nez pendant un drift, ressenti comme une courbe trop large.
- `ReglesCommunes.coef_glisse_passif` (voir « Principe d'équilibrage »
  ci-dessus) ajouté pour éliminer une ligne droite forcée hors glisse à
  haute vitesse.
- `ReglesCommunes.coef_braquage_glisse` (voir « Principe d'équilibrage »
  ci-dessus) ajouté pour qu'une glisse engagée reste difficile à rediriger.
- `adherence_laterale_ms2` remonté ×1,8 pour **les 5 véhicules** (hiérarchie
  relative inchangée, Needle reste le plus adhérent) : à vitesse et rayon de
  virage réalistes pour la taille des pistes du jeu, même Needle ne pouvait
  pas prendre un virage large sans freiner d'abord — pas un problème propre
  au Roadster. Effet de bord assumé : la glisse du Roadster ne gagne plus
  sur aucun rayon testé par `tools/bench_rayon.gd` (10-60 m), contre
  systématiquement avant — resté tel quel, pas encore recorrigé.
- `decel_naturelle_ms2` du Roadster remonté de 5.0 à 12.0 : relâcher
  l'accélérateur donnait une sensation de glace (roulage libre ~77 m depuis
  100 km/h), ramené à ~32 m.

Testé : `tools/run_tests.gd` passe à chaque étape (hash de régression mis à
jour à chaque changement volontaire du modèle de conduite), `tools/
bench_rayon.gd` et `tools/bench_equilibrage.gd` vérifiés après le
changement d'adhérence. Le *feeling* reste à valider manette en main
au-delà de ces retours ponctuels — en particulier le point de bascule
glisse/adhérence du Roadster, laissé tel quel après l'effet de bord
ci-dessus.

**Pistes point à point (`map/track_data.gd`, `sim/race_state.gd`,
`render/track_mesh.gd`).** Sur demande explicite (une piste dont le départ et
l'arrivée sont deux endroits distincts, pas une boucle) : `TrackData` gagne
`est_ferme`, propagé vers `Track`/`RaceState`/`TrackMesh` — voir « Éditeur de
piste » et « Chrono, ligne d'arrivée et leaderboard » dans Architecture pour
le détail. A aussi corrigé deux bugs latents trouvés au passage (cap de
départ figé à 0, position de départ doublement convertie en Q16.16 pour
toute piste `TrackData` — voir « Éditeur de piste »). Testé :
`tools/run_tests.gd` passe (125 tests, hash de régression inchangé —
prouvé : la piste intégrée reste fermée et ses valeurs de départ sont déjà à
zéro), `tools/bench_rayon.gd` (seul consommateur préexistant d'une piste
ouverte) tourne sans régression.

**Éléments visibles en jeu (`render/track_elements_view.gd`, `map/element_roster.gd`).**
Les éléments posés dans l'éditeur n'étaient affichés que dans l'aperçu de
l'éditeur lui-même — une fois "Jouer" lancé, `render/track_mesh.gd` ne
dessinait que la route et les murs, rien pour les éléments. `TrackElementsView`
(repère cube coloré par type, même palette que l'éditeur via le nouveau
`ElementRoster.color_for_type()` partagé) comble ce trou : `main.gd` transmet
désormais `TrackData.elements` (vide pour la piste intégrée, qui n'en a pas)
à ce nouveau nœud de rendu au chargement. Purement cosmétique, comme
`TrackMesh` (l'effet en simulation est arrivé juste après, voir « Effets des
éléments de piste » ci-dessous). Bug corrigé au passage dans
`main.gd::_physics_process()` : le
raccourci "reinitialiser" était vérifié APRÈS le garde `_run_over`, donc
inopérant une fois la course terminée ou le temps écoulé (seul le bouton
"Rejouer" du menu de fin fonctionnait) — la vérification est remontée avant
ce garde.

**Effets des éléments de piste, Lot A (`sim/element_effects.gd`,
`sim/car_sim.gd`, `map/track.gd`, `map/track_data.gd`, `map/element_roster.gd`).**
Sur demande explicite : les éléments posés dans l'éditeur ont maintenant un
premier lot d'effets réels en simulation, pas seulement une présence
visuelle. Détail complet (constantes, mécanisme, matrice élément × stat
responsable de la différenciation par véhicule) dans
`docs/matrice-vehicules.md` — coche le TODO de configuration. Voir
« Éléments de piste » dans Architecture pour le résumé Lot A/Lot B. Testé :
`tools/run_tests.gd` passe (203 tests — nouvelle couverture par élément,
garde-fou anti-traversée des rayons de détection, anti-cumul des zones qui
se chevauchent, piste avec un élément Lot B posé sous la voiture → hash
identique à une piste sans élément —, hash de régression inchangé : preuve
que ce lot est totalement inerte sur la piste intégrée, qui n'a pas
d'éléments), `tools/bench_equilibrage.gd` et `tools/bench_rayon.gd`
inchangés (aucun des deux ne construit de piste avec éléments).

**Système de fantôme, premier lot (`replay/`, `main.gd`, `render/car_view.gd`,
`ui/leaderboard.gd`, `ui/ghost_menu.gd`, `ui/track_select.gd`).** Étape 5 du
projet, demandée explicitement alors qu'elle était à 0 % : enregistrement du
log d'inputs complet d'un run (depuis le tick 0, pas depuis le premier
input), sauvegarde d'un fichier de replay par run terminé, lecture en
superposition d'un second véhicule semi-transparent piloté par ce log.
Détail complet (mécanisme d'alignement `start_tick`, politique de
stockage, contre-rejeu de validation) dans « Système de fantôme » plus haut
dans Architecture. Bouton « Choisir un fantôme » de `ui/track_select.gd`
(placeholder désactivé jusqu'ici) branché. Testé :
`tools/run_tests.gd` passe (226 tests — quantification des crans aux
bornes, aller-retour enregistrement/lecture bit-exact, sérialisation
`ResourceSaver`/`ResourceLoader` d'un `ReplayData`, isolation de deux
`World` tickés en entrelacé —, hash de régression inchangé
(`2224413573259929705`) : preuve que l'extraction de `CarState.compute_hash()`
et tout le nouveau code sont neutres sur la piste intégrée). Jeu lancé et
vérifié sans erreur de chargement/compilation jusqu'au menu principal ;
le parcours complet en jeu (terminer un run → choisir ce fantôme → le voir
apparaître semi-transparent et synchronisé) reste à valider manette en
main, non vérifiable sans interaction humaine avec la fenêtre native.

**Sélection du fantôme par mode (`replay/ghost_resolver.gd`,
`ui/ghost_selection.gd`, `main.gd`, `ui/ghost_menu.gd`, `ui/finish_menu.gd`,
`ui/leaderboard.gd`, `ui/track_select.gd`).** Sur demande explicite : le
fantôme figé du lot précédent devient un **mode** re-résolu à chaque
tentative (Mes records / Records mondiaux — grisé, backend hors scope —
/ Fantômes enregistrés), pour qu'un nouveau record remplace automatiquement
le fantôme sans repasser par un menu. Détail complet (mécanisme de
résolution, dégradation `MONDIAL`→`PERSO`, persistance en chaîne plutôt
qu'en `int` d'enum, deux pièges de revue corrigés avant livraison sur le
cycle de vie de la `CarView` fantôme) dans « Sélection du fantôme par mode »
plus haut dans Architecture. Deux décisions prises avec l'utilisateur : la
section « Records mondiaux » reste un placeholder désactivé (le site/backend
est hors scope avant l'étape 6) mais toute la logique de bascule est écrite
et testée dès maintenant ; supprimer un fantôme « ajouté manuellement »
supprime le run entièrement (derrière confirmation), pas seulement de la
liste. Testé : `tools/run_tests.gd` passe (240 tests — 14 nouveaux sur
`GhostResolver`, statique et pur : recherche explicite du minimum
indépendante de l'ordre fourni, entrée orpheline ignorée, remplacement
automatique après un nouveau record, dégradation `MONDIAL`→`PERSO` dans les
deux sens, `MANUEL` jamais re-résolu, aller-retour chaîne↔enum pour la
persistance —, hash de régression inchangé : preuve que ce lot ne touche
rien dans `sim/`). Cache de classes régénéré (nouveau `class_name
GhostResolver`, nouvel autoload `GhostSelection`), jeu lancé sans erreur
jusqu'au menu principal. Le parcours complet (enchaîner deux tentatives et
voir le fantôme se remplacer tout seul après un record, épingler puis
supprimer un fantôme manuel) reste à valider manette en main.

**Polish `ui/ghost_menu.gd` + Échap partout où « Retour » existe
(`main.gd`, `ui/vehicle_menu.gd`, `ui/editor_menu.gd`,
`ui/settings_menu.gd`, `ui/track_select.gd`).** Retours utilisateur après
test manuel en jeu (captures d'écran) : le panneau fantôme apparaissait
plaqué en haut à gauche au lieu d'être centré — bug Godot réel trouvé et
corrigé (voir le piège `PRESET_FULL_RECT` développé dans la section
correspondante en tête de ce fichier). `ui/finish_menu.gd` : Échap ouvrait
le panneau pause DERRIÈRE l'écran de fin de course — `main.gd::_unhandled_input()`
distingue maintenant ce cas (`_run_over`) et ramène directement à la
sélection de piste, comme le bouton « Quitter ». Échap déclenche désormais
partout la même action que le bouton « Retour » visible à l'écran — un
garde `visible`/`_root_layout.visible` (selon l'écran) évite qu'un overlay
cache réagisse alors qu'il n'est pas affiché, et qu'un overlay ouvert
par-dessus `ui/track_select.gd` court-circuite le retour direct au menu
principal (c'est LUI qui doit se fermer en premier). Sélectionner un
fantôme dans `ui/ghost_menu.gd` ne ferme plus le panneau (rafraîchi sur
place) — sur demande explicite, pour pouvoir comparer plusieurs choix sans
rouvrir le menu à chaque fois ; seuls « Retour »/Échap le ferment.

Deux bugs supplémentaires trouvés APRÈS le premier correctif de centrage
(retours utilisateur successifs, chacun vérifié par script jetable ou log
en jeu plutôt que supposé) : (1) `_back_button` (bas-gauche, voir le piège
`PRESET_FULL_RECT` en tête de ce fichier) se retrouvait en HAUT à gauche —
son `set_anchors_preset()`, appelé juste après avoir corrigé la taille de
`GhostMenu`, lisait encore l'ANCIENNE taille (la mise à jour de `size` ne se
propage pas de façon synchrone à `get_parent_area_size()`) ; corrigé en
calculant sa position directement sur `get_viewport_rect()`, même
contournement que pour `GhostMenu` lui-même, plutôt que de dépendre du
système d'ancrage pour ce nœud. (2) Le panneau de confirmation de
suppression (`ConfirmationDialog`, ici et dans les deux dialogues
préexistants de `ui/track_select.gd`, « Supprimer... »/« Effacer les scores
locaux ») ne s'affichait plus du tout après une tentative de retirer la
croix de fermeture (redondante avec le bouton « Annuler ») via
`dialog.get_close_button()` : cette méthode **n'existe pas** sur
`ConfirmationDialog` dans cette version de Godot (vérifié directement par
script jetable, pas supposé), plantant la fonction en silence avant
`popup_centered()`. Retirée — aucune API scriptable trouvée pour masquer
uniquement la croix sans supprimer toute la barre de titre (donc aussi le
texte « Confirmation ») ; la croix reste, doublon mineur assumé.
`get_cancel_button().text = "Annuler"` (confirmé valide) reste, et doit
être appelé APRÈS `add_child(dialog)` — les boutons internes n'existent pas
avant que le dialogue soit dans l'arbre. Testé : `tools/run_tests.gd` passe
(240 tests, hash de régression inchangé — ce lot ne touche que de l'UI,
rien dans `sim/`) ; ATTENTION, ce lot illustre une limite réelle de cette
suite de tests — elle ne charge ni n'exécute aucun code de `ui/`, donc une
erreur de script dans ce dossier (comme les deux bugs ci-dessus) ne s'y
voit JAMAIS : seul un lancement en jeu (ou un script headless ciblé) les
révèle. Diagnostic de centrage vérifié en jeu via impressions console
temporaires (retirées) avant validation visuelle par l'utilisateur, qui a
confirmé le résultat final correct après ces deux correctifs.

**Menu déroulant de véhicule (`ui/vehicle_menu.gd`, `ui/track_select.gd`).**
Sur demande explicite (maquette utilisateur) : remplace l'ancien overlay
plein écran par un petit menu déroulant ancré au-dessus du bouton
« Changer de véhicule », arrière-plan resté visible. Détail complet
(mécanisme de positionnement, deux bugs trouvés et corrigés en cours de
route — hauteur du panneau décalée à partir de la deuxième ouverture,
focus clavier toujours sur Roadster au lieu du véhicule réellement
sélectionné) dans « Menu déroulant de véhicule » plus haut dans
Architecture. Décision de conception prise avec l'utilisateur après
premier essai : une coloration verte du texte comme indicateur de
sélection secondaire (même idée que les pastilles de `ui/ghost_menu.gd`)
a été ajoutée puis retirée sur retour direct (« mal fait et pas vraiment
utile ») — l'anneau de focus, désormais correctement positionné sur le
véhicule sélectionné, reste le seul indicateur. Testé : `tools/run_tests.gd`
passe (240 tests, hash de régression inchangé — ce lot ne touche que de
l'UI, rien dans `sim/`) ; les deux bugs de ce lot n'étaient visibles qu'en
jeu (même limite de la suite de tests que documentée juste au-dessus),
chacun corrigé après reproduction manuelle par l'utilisateur puis
validation par relance du jeu.

**Regrouper par : douze modes de tri (`map/track_grouping.gd`,
`map/track_data.gd`, `map/track_catalog.gd`, `editor/track_editor.gd`,
`ui/track_select.gd`).** Sur demande explicite, façon osu! : le menu
« Regrouper par : » passe de 2 à 12 entrées (créateur, titre, date
d'ajout, durée, véhicule, mes pistes, récemment jouées — trois placeholders
désactivés pour ce qui demande le backend ou une mécanique déjà reportée).
Détail complet (logique de section, nouveau champ `TrackData.date_ajout`
+ migration, contrainte de pureté testable) dans « Regrouper par : douze
modes de tri » plus haut dans Architecture. Décisions prises avec
l'utilisateur avant ce lot (AskUserQuestion) pour chaque critère sans
donnée existante — voir cette section pour le détail de chacune. Testé :
`tools/run_tests.gd` passe (269 tests — 29 nouveaux sur `TrackGrouping`,
bornes exactes de chaque tranche/classification —, hash de régression
inchangé : ce lot ne touche rien dans `sim/`) ; tous les modes du menu
testés manuellement en jeu par l'utilisateur, aucune erreur en console.

**Deux bugs de marche arrière corrigés (`sim/car_sim.gd`,
`sim/car_configs/car_config_formula.gd`).** Retour utilisateur après test
manuel en jeu : (1) en marche arrière, le volant tournait la voiture du
côté OPPOSÉ à la touche pressée pour Roadster/Ironside/Wasp/Halcyon — la
formule du lacet (étape 4) utilise `v`, une MAGNITUDE (`FixedMath.
length_2d`, jamais négative), donc le nez tourne toujours dans le même sens
pour une même touche, avant ou en arrière ; mais la trajectoire suit
`forward_speed` (signé, étape 8), qui s'inverse en marche arrière — la
voiture visible à l'écran tournait donc du côté opposé à la touche. Corrigé
par un multiplicateur de signe (`sens_deplacement`, dérivé de la vitesse
projetée sur le nez au repère du tick précédent) appliqué UNIQUEMENT à
l'étape 4, jamais à la magnitude de `v` utilisée ailleurs (ARC, seuils
d'écrêtage) — un `Fixed.sign()` qui vaut +1 dès qu'il y a la moindre
composante avant rend ce correctif un no-op bit-exact pour toute conduite
qui ne recule jamais, y compris en glisse. (2) Needle (id `formula`) ne
pouvait pas du tout reculer : `freinage_ms2` et `decel_naturelle_ms2`
valaient tous les deux 8.0, seul véhicule avec cette égalité — la poussée
du frein et la résistance naturelle s'annulaient pile à zéro CHAQUE tick
sous frein seul, sans jamais accumuler d'un tick à l'autre (les 4 autres
véhicules ont tous un écart net entre ces deux valeurs). `freinage_ms2`
relevé à 10.0 (`decel_naturelle_ms2` inchangé) — reste sous Superbike
(12.0), cohérent avec le profil plus léger de Needle, ajustable à la
manette si besoin. Les deux bugs trouvés et confirmés via script headless
jetable AVANT correction (jamais supposés) — voir `_build_test_world()`/
`World.setup()`/`world.tick()` pour le patron de script minimal réutilisé.
Testé : `tools/run_tests.gd` passe (269 tests, **hash de régression
inchangé** — preuve directe que le correctif de signe est un no-op sur
toute la suite de tests existante, qui ne recule jamais).

**Champ de recherche (`ui/track_select.gd`) : cliquer en dehors ne libérait
pas le focus.** Retour utilisateur : seul un clic sur un bouton en sortait,
gênant. Trois correctifs successifs par `mouse_filter` (fond, deux spacers)
n'ont pas suffi — le clic n'atteignait jamais `_unhandled_input()`, vérifié
par trace, cause exacte non isolée dans cette arborescence imbriquée.
Contourné avec `_input()` à la place (voir le piège détaillé en tête de ce
fichier), qui voit le clic sans dépendre de la chaîne `mouse_filter`. Un
détour de vérification a aussi révélé que `Window.push_input()` en
`--headless` ne reproduit pas fidèlement le routage GUI réel d'un clic —
deux « confirmations » en cours de route étaient donc des faux positifs,
signalés à l'utilisateur plutôt que tus. Testé : `tools/run_tests.gd` passe
(269 tests, hash de régression inchangé — ce lot ne touche que de l'UI) ;
comportement final confirmé en jeu par l'utilisateur après plusieurs allers-
retours.

**`ui/collections_menu.gd` recentré, « Fermer » → « Retour ».** Sur demande
explicite (« pas ton intuition, une méthode sûre ») : appliqué mot pour mot
les techniques déjà vérifiées empiriquement sur `ui/ghost_menu.gd`/
`ui/vehicle_menu.gd` cette session (voir le piège `PRESET_FULL_RECT` et le
piège `remove_child()`/`queue_free()` en tête de ce fichier), pas de
nouvelle tentative à l'aveugle — `size`/`position` forcés sur
`get_viewport_rect()` dans `focus_first()`, bouton « Retour » repositionné
au même endroit, `remove_child()` avant `queue_free()` dans `_refresh()`,
Échap ajouté (ce panneau ne l'avait jamais eu, contrairement au reste du
jeu). Vérifié par diagnostic chiffré temporaire (pas seulement visuel) avant
de conclure : position du panneau strictement égale au centre calculé
`(largeur_écran − largeur_panneau) / 2`, bouton « Retour » à `y +
hauteur_bouton == hauteur_écran` (collé au bord). Testé :
`tools/run_tests.gd` passe (269 tests, hash de régression inchangé) ;
confirmé en jeu par l'utilisateur, cohérent avec les chiffres du
diagnostic.

Ordre de travail retenu :

1. Conduite de la voiture sur une piste codée en dur — **jouable, feeling à régler**
2. Format de fichier de piste + chargeur — **première version faite (`TrackData`), pas encore le format final**
3. Chrono, checkpoints, repop, limite de temps — **chrono, ligne d'arrivée et limite de temps faits ; checkpoints et repop restants**
4. Éditeur intégré — **première version faite ; comportement des éléments : Lot A câblé (zones/contact), Lot B restant (collision orientée, checkpoints)**
5. Log d'inputs, rejeu déterministe, fantômes — **enregistrement + lecture + sélection par mode (perso/mondial/manuel) faits ; mods/temps aux checkpoints toujours absents du log, records mondiaux en placeholder (backend)**
6. Site et backend — **publication depuis l'éditeur volontairement désactivée en attendant**

Rien ne passe à l'étape suivante tant que la précédente n'est pas jouable.

---

## TODO de configuration

- [x] Remplacer `<NOM_EXE>` par le nom réel de l'exécutable Godot (`godot.windows.opt.tools.64.exe`)
- [x] Confirmer le chemin du dossier de projet (`D:/DL/JV/Godot/time-to-vroom`)
- [x] Créer `docs/matrice-vehicules.md`
