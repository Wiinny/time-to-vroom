# Prompt — Paramétrage des 5 véhicules

> À coller dans Claude Code, en **mode plan**, depuis la racine du projet.

---

## Objectif

Les cinq véhicules existent déjà avec des paramètres par défaut. Il s'agit maintenant
de leur donner cinq identités de pilotage réellement distinctes, chiffrées, réglables,
et vérifiables automatiquement.

Le livrable n'est pas « cinq voitures qui roulent ». C'est :

1. Un modèle de paramètres assez riche pour exprimer les cinq comportements décrits
2. Cinq fichiers de configuration remplis avec les valeurs ci-dessous
3. Un harnais de test qui mesure l'équilibrage et le point de bascule glisse/adhérence

---

## À lire avant toute proposition

- `CLAUDE.md` — les règles de déterminisme ne sont pas négociables
- `sim/car_config.gd` — le modèle de configuration actuel
- `sim/car_sim.gd` — le modèle de conduite actuel
- `sim/car_state.gd` — l'état actuel
- `core/fixed.gd` et `core/fixed_math.gd` — les outils disponibles

Ne présume rien de leur contenu : le paramétrage doit étendre l'existant, pas le
remplacer sans raison. Si le modèle actuel ne permet pas d'exprimer un comportement
demandé, dis-le explicitement dans le plan plutôt que d'approximer en silence.

---

## Principe directeur

**L'équilibrage ne se fait pas sur les statistiques longitudinales.**

Vitesse max, accélération et freinage s'appliquent à toutes les pistes : un véhicule
plus rapide en ligne droite est plus rapide partout. Aucun avantage en virage ne
compense ça.

L'objectif est que **les cinq véhicules réalisent des temps comparables sur une piste
de référence moyenne**, et que chaque écart par rapport à cette moyenne — plus de
virages serrés, plus de ligne droite, plus d'obstacles, plus de rampes — avantage un
véhicule différent.

C'est donc le **latéral** qui différencie : rayon de braquage, adhérence, inertie,
comportement en glisse, contrôle aérien. Les vitesses max restent resserrées dans une
fourchette de 11 %.

## Règle en cas de doute

Pour tout arbitrage non tranché ci-dessous, **choisis la solution la plus proche du jeu
dont le véhicule s'inspire** :

| Véhicule | Référence |
| --- | --- |
| Roadster | Forza Horizon |
| Needle | Trackmania (voiture unique, 2023) |
| Ironside | Bécane Bowser, Mario Kart Wii |
| Wasp | Moto légère, Mario Kart Wii |
| Halcyon | F-Zero |

Signale ces arbitrages dans un commentaire en tête du fichier concerné, pour qu'ils
soient repérables plus tard.

---

## Le modèle de paramètres à mettre en place

`sim/car_config.gd` doit exposer au minimum les champs suivants, en `@export` lisibles
(unités humaines), convertis **une seule fois** en virgule fixe au chargement.

### Longitudinal

| Champ | Unité | Rôle |
| --- | --- | --- |
| `vitesse_max` | km/h | plafond naturel, hors boost |
| `palier_accel` | km/h | vitesse à laquelle la courbe d'accélération se casse |
| `accel_basse` | m/s² | accélération sous le palier |
| `accel_haute` | m/s² | accélération au-dessus du palier |
| `freinage` | m/s² | décélération touche frein enfoncée |
| `decel_naturelle` | m/s² | décélération accélérateur relâché |

### Latéral

| Champ | Unité | Rôle |
| --- | --- | --- |
| `angle_braquage_max` | degrés | braquage maximal des roues |
| `vitesse_braquage` | deg/s | vitesse à laquelle l'angle se met en place |
| `adherence_laterale` | m/s² | accélération latérale maximale avant décrochage |
| `controle_aerien` | 0–1 | autorité de direction en l'air |

### Glisse

| Champ | Type | Rôle |
| --- | --- | --- |
| `type_glisse` | enum | `AUCUNE`, `PIVOT_AVANT`, `SAUT_ARC`, `PERMANENTE` |
| `perte_vitesse_glisse` | %/s | vitesse perdue pendant la glisse |
| `rayon_glisse` | m | rayon de l'arc, pour `SAUT_ARC` uniquement |

### Saut (Wasp uniquement, laisser à zéro ailleurs)

| Champ | Unité | Rôle |
| --- | --- | --- |
| `hauteur_saut` | m | hauteur du petit saut |
| `duree_saut` | s | durée de la phase aérienne |
| `cout_vitesse_saut` | km/h | vitesse perdue à chaque saut |

### Boost

| Champ | Unité | Rôle |
| --- | --- | --- |
| `boost_destab_duree` | s | durée de la perte d'autorité après boost |
| `boost_destab_facteur` | 0–1 | multiplicateur d'autorité pendant cette durée |

---

## Les cinq fiches

Ces valeurs sont des **points de départ plausibles**, pas des vérités. Elles seront
réajustées manette en main. Ce qui compte est qu'elles soient cohérentes entre elles
et qu'elles produisent bien cinq comportements distincts.

### Roadster — la référence

Pas de personnage visible. Le véhicule d'apprentissage : du poids, du transfert de
charge, tolérant, bon partout sans jamais dominer.

```
vitesse_max          180
palier_accel         110
accel_basse          11.0
accel_haute          3.5
freinage             18.0
decel_naturelle      5.0
angle_braquage_max   34
vitesse_braquage     180
adherence_laterale   14.0
controle_aerien      0.50
type_glisse          PIVOT_AVANT
perte_vitesse_glisse 6.0
```

Glisse façon Forza : les roues restent au sol, l'arrière décroche, la voiture **pivote
autour de son avant**. Point important : la trajectoire elle-même doit se raccourcir
pendant la glisse, pas seulement l'orientation changer. Sans ça, le drift n'est qu'une
perte de vitesse avec un joli visuel. Glisse modulable en continu par la direction et
l'accélérateur, corrigeable à tout moment.

### Needle — l'exécution pure

Pas de personnage visible. Inertie quasi nulle, réponse instantanée, adhérence
maximale. Ne peut pas s'incliner brusquement : pour prendre un virage serré, il **faut**
ralentir. Trajectoires larges, façon Trackmania.

```
vitesse_max          185
palier_accel         185      (courbe linéaire, pas de palier)
accel_basse          7.5
accel_haute          7.5
freinage             8.0
decel_naturelle      8.0
angle_braquage_max   30
vitesse_braquage     400
adherence_laterale   20.0
controle_aerien      0.90
type_glisse          AUCUNE
perte_vitesse_glisse 0
```

Le freinage faible combiné à la forte décélération naturelle est intentionnel : le geste
n'est pas de freiner mais de **lever le pied au bon moment**. Dépasser l'adhérence ne
produit pas de glisse mais un sous-virage avec perte de vitesse — la voiture pousse tout
droit et ralentit, elle ne part jamais en travers.

### Ironside — l'engagement

Personnage visible. Lourde, braquage lent, adhérence élevée. Ne glisse pas. Le geste est
l'anticipation du point d'entrée : on s'engage tôt parce qu'on ne peut pas corriger vite.

```
vitesse_max          185
palier_accel         120
accel_basse          11.5
accel_haute          3.0
freinage             12.0
decel_naturelle      5.0
angle_braquage_max   32
vitesse_braquage     110
adherence_laterale   17.0
controle_aerien      0.25
type_glisse          AUCUNE
perte_vitesse_glisse 0
```

La `vitesse_braquage` très basse est le cœur de son identité — ce n'est pas qu'elle tourne
peu, c'est qu'elle met du temps à commencer à tourner. Même traitement que Needle en cas
de dépassement d'adhérence : sous-virage, pas de glisse.

### Wasp — la nervosité

Personnage visible. Légère, accélère fort partout, plafonne bas. Pardonne les erreurs
parce qu'on reprend sa vitesse instantanément.

```
vitesse_max          175
palier_accel         175      (courbe linéaire)
accel_basse          13.5
accel_haute          13.5
freinage             18.0
decel_naturelle      8.0
angle_braquage_max   36
vitesse_braquage     400
adherence_laterale   13.0
controle_aerien      0.85
type_glisse          SAUT_ARC
perte_vitesse_glisse 4.0
rayon_glisse         22
hauteur_saut         0.6
duree_saut           0.45
cout_vitesse_saut    8
```

Glisse façon Mario Kart Wii : **petit saut, puis dérapage engagé** décrivant un grand arc
de cercle de rayon largement fixe. Le joueur doit viser le virage avant de déclencher —
la correction en cours de glisse est très limitée. C'est le véhicule le plus difficile à
placer, et c'est voulu.

Le saut permet de franchir un obstacle au sol (plot de chantier). C'est un skill
supplémentaire assumé, et son coût est **uniquement** `cout_vitesse_saut` : chaque saut
retire de la vitesse, donc enchaîner les sauts se punit tout seul.

**N'implémente aucun seuil du type « plus de N sauts en M secondes ».** Un seuil brutal
devient une cible à optimiser dans un jeu de time attack, et il est illisible pour le
joueur. Le coût continu suffit. Si le spam reste rentable après réglage, monte
`cout_vitesse_saut` — ne rajoute pas de règle.

### Halcyon — l'anticipation

Pas de personnage visible (ou intégré au vaisseau). Vitesse la plus élevée, mais elle se
mérite : accélération très lente, pratiquement aucun freinage, décélération naturelle
quasi nulle.

```
vitesse_max          195
palier_accel         195      (courbe linéaire)
accel_basse          4.0
accel_haute          4.0
freinage             3.0
decel_naturelle      0.5
angle_braquage_max   26
vitesse_braquage     70
adherence_laterale   7.0
controle_aerien      0.20
type_glisse          PERMANENTE
perte_vitesse_glisse 2.0
boost_destab_duree   0.8
boost_destab_facteur 0.35
```

`decel_naturelle` à 0.5 est la ligne la plus importante de toute cette fiche. Lever le
pied ne fait presque rien, freiner non plus : toute la vitesse acquise reste. La seule
façon de négocier un virage est de l'avoir préparé. C'est le seul véhicule où l'erreur se
commet trois secondes avant qu'elle ne se voie.

`type_glisse = PERMANENTE` : il n'y a pas de déclenchement ni de sortie de glisse. Le
vaisseau dérive en continu et braquer ne fait qu'infléchir une trajectoire qui suit
toujours son inertie. On ne tourne pas, on oriente une dérive.

---

## Règles globales du boost

Identiques pour les cinq véhicules, à placer dans une configuration partagée et non dans
chaque fiche :

- Poussée **absolue et identique pour tous** : `+45 km/h`, appliqués instantanément.
  Pas de pourcentage — un pourcentage avantagerait mécaniquement les véhicules rapides.
- La poussée s'applique **dans la direction de la trajectoire** du véhicule, pas dans
  celle de son orientation. Conséquence assumée : prendre un boost en dérapage près du
  bord projette vers l'extérieur, et peut envoyer dans le vide. C'est un outil de level
  design, pas un bug.
- La vitesse excédentaire au-dessus de `vitesse_max` retombe à un **rythme fixe de
  12 km/h par seconde, identique pour tous les véhicules**. Ce rythme ne doit
  **jamais** être indexé sur `decel_naturelle` : sinon Halcyon conserve son surplus
  bien plus longtemps que les autres et monopolise les pistes chargées en boosts.
- Seul Halcyon subit une déstabilisation après boost (`boost_destab_*`). Elle doit rester
  un assaisonnement, pas une punition : le vaisseau doit rester pilotable pendant la
  perte d'autorité.

---

## Le harnais d'équilibrage à construire

C'est la partie la plus importante de ce lot, et c'est celle qui a le plus de valeur dans
la durée. Deux outils, tous deux en `--headless`, tous deux déterministes.

### 1. `tools/bench_equilibrage.gd`

Construit une **piste de référence délibérément moyenne** : environ un tiers de ligne
droite, des virages de rayons variés, une épingle, deux rampes, une zone de plots, une
portion de route dégradée.

Pour chaque véhicule, rejoue un log d'inputs enregistré et affiche le temps obtenu.

Sortie attendue : un tableau des cinq chronos et de leur écart-type. L'objectif de
réglage est que les cinq temps tiennent dans une fourchette de quelques pour cent.

Ce n'est **pas** un test qui échoue : c'est un instrument de mesure. Il affiche, il ne
juge pas.

### 2. `tools/bench_rayon.gd`

Mesure le **point de bascule glisse/adhérence**, qui est le curseur d'équilibrage
principal de tout le jeu.

Génère une série de virages de rayons croissants (par exemple de 10 m à 60 m, par pas de
5 m). Pour chaque rayon et chaque véhicule, mesure le temps de passage optimal.

Sortie attendue : pour chaque véhicule, la courbe temps/rayon, et le rayon où les
véhicules à glisse deviennent plus lents que les véhicules à adhérence.

**Cible de réglage : la glisse doit être plus rapide en dessous d'environ 28 m de rayon,
et plus lente au-dessus.** Si la glisse gagne partout, Roadster et Wasp domineront toutes
les pistes. Si elle perd partout, c'est un piège que personne n'utilisera. Le levier pour
déplacer ce point est `perte_vitesse_glisse`.

---

## Contraintes techniques

Elles découlent du `CLAUDE.md` et ne se négocient pas :

- Toutes les valeurs ci-dessus sont exprimées en unités humaines dans les `@export`, et
  converties en virgule fixe **une seule fois au chargement**. Aucun flottant ne doit
  entrer dans un calcul de simulation.
- Les courbes d'accélération, de glisse et de braquage doivent être des fonctions
  entières. Pas d'appel à `sin()`, `cos()`, `pow()` ou `sqrt()` natifs — passe par
  `core/fixed_math.gd`.
- Aucune allocation par tick. Les cinq configurations sont chargées une fois et
  réutilisées.
- `sim/` ne doit référencer aucun `Node3D`, aucun `float`, aucun `delta`.
- Les tests de déterminisme existants doivent continuer à passer, et deux exécutions
  successives doivent produire le même hash d'état final.

---

## Vérification attendue

```bash
GODOT="D:/DL/JV/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"

"$GODOT" --headless --editor --quit --path .
"$GODOT" --headless --path . --script res://tools/run_tests.gd
"$GODOT" --headless --path . --script res://tools/bench_equilibrage.gd
"$GODOT" --headless --path . --script res://tools/bench_rayon.gd
"$GODOT" --path .
```

Critères de réussite :

- Les tests de déterminisme passent, deux exécutions donnent le même hash
- Les cinq véhicules sont pilotables et se comportent visiblement différemment
- Les cinq chronos du banc d'équilibrage sont affichés avec leur écart
- La courbe temps/rayon est affichée et le point de bascule est identifiable
- Aucun `float`, aucun `Node3D`, aucun `delta` dans `sim/` et `core/`

Le *feeling* de conduite ne fait pas partie des critères. Expose les paramètres, donne
des valeurs de départ plausibles, et laisse le réglage fin à la manette.

---

## Hors scope

Ne traite pas dans ce lot : la matrice véhicule × élément de route (les comportements
spécifiques sur route qui ralentit, route dégradée, barrières, obstacles), les modèles 3D
et les skins, le multijoueur, l'éditeur, le format de fichier de piste.

Si une de ces choses bloque le paramétrage, signale-le dans le plan au lieu de la traiter.

---

## Mise à jour du `CLAUDE.md`

À la fin du lot, ajoute une section « Véhicules » qui documente :

- Les cinq identifiants internes : `gt`, `formula`, `superbike`, `street_bike`, `hover`
- Le principe d'équilibrage : équilibrage par le latéral, jamais par le longitudinal
- La règle du boost : poussée absolue identique, direction de la trajectoire,
  décroissance à taux fixe jamais indexée sur `decel_naturelle`
- L'existence des deux bancs de mesure et ce qu'ils servent à vérifier
- L'interdiction des seuils du type « N actions en M secondes » comme mécanique de coût
