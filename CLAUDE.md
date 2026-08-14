# CLAUDE.md

## Le projet

Jeu de course 3D arcade, sur le modèle d'osu! : les joueurs créent leurs pistes
dans un éditeur intégré, les partagent sur le site du projet, et s'affrontent sur
des leaderboards par piste **et par véhicule**.

- Moteur : **Godot 4.7.1** (version Steam), GDScript
- Cible : PC (exe téléchargeable), pas de navigateur
- Style : arcade, modèles 3D volontairement simples, pas de musique
- Trois véhicules prévus : voiture (référence), moto, un troisième non arrêté

La piste de base est conçue pour la voiture, puis **convertie automatiquement**
pour les autres véhicules — modèle osu!std vers les autres modes. Certaines
pistes seront mono-véhicule quand la conversion n'a pas de sens.

---

## Commandes

GODOT="D:/DL/JV/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"

```bash
# Adapter le nom de l'exécutable — voir TODO en bas de fichier
GODOT="D:/DL/JV/Steam/steamapps/common/Godot Engine/<NOM_EXE>.exe"

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

### 2. Pas plus d'une source de vérité pour le temps

- La simulation avance à **60 Hz fixe**, jamais au rythme du rendu.
- `physics/common/physics_ticks_per_second = 60`
- `physics/common/physics_jitter_fix = 0` (le lissage casse le déterminisme)
- Le numéro de tick est la seule horloge. Interdits dans la simulation :
  `delta`, `Time.get_ticks_msec()`, `Engine.get_frames_per_second()`.

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

---

## Vocabulaire du projet

Employer ces termes, dans le code comme dans les échanges :

| Terme | Sens |
| --- | --- |
| **piste** | Le circuit créé par un joueur (jamais « map » ni « niveau » dans le code) |
| **run** | Une tentative, du départ à l'arrivée ou à l'échec |
| **replay** | Le log d'inputs d'un run, rejouable et vérifiable |
| **fantôme** | Un replay affiché en superposition pendant qu'on joue |
| **checkpoint** | Élément posé par le créateur, valide le parcours (anti-raccourci) |
| **repop** | Position de réapparition, **générée automatiquement**, sans lien avec les checkpoints |
| **diffuseur** | Terme réservé à un autre projet — ne pas l'utiliser ici |

Les checkpoints sont **optionnels** pour le créateur. Les points de repop, non :
ils sont toujours générés le long du tracé.

---

## Éléments de piste

Liste fermée. Ne pas en ajouter sans décision explicite.

- Route normale
- Route qui ralentit
- Route qui dégrade les contrôles
- Barrière (délimite, guide)
- Obstacle bloquant
- Obstacle qui ralentit au contact (type plot de chantier)
- Obstacle mortel
- Rampe
- Boost
- Ligne de départ / d'arrivée (un seul élément ou deux, au choix du créateur)
- Checkpoint

Chaque élément doit avoir un comportement **différent selon le véhicule**. C'est
ce qui justifie d'avoir trois leaderboards plutôt qu'un. La matrice
véhicule × élément est la référence : `docs/matrice-vehicules.md`.

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

Projet en démarrage. Ordre de travail retenu :

1. Conduite de la voiture sur une piste codée en dur — **étape en cours**
2. Format de fichier de piste + chargeur
3. Chrono, checkpoints, repop, limite de temps
4. Éditeur intégré
5. Log d'inputs, rejeu déterministe, fantômes
6. Site et backend

Rien ne passe à l'étape suivante tant que la précédente n'est pas jouable.

---

## TODO de configuration

- [ ] Remplacer `<NOM_EXE>` par le nom réel de l'exécutable Godot
- [ ] Confirmer le chemin du dossier de projet
- [ ] Créer `docs/matrice-vehicules.md`
