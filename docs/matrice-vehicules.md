# Matrice véhicule × élément

Référencée depuis `CLAUDE.md` (« Chaque élément doit avoir un comportement
différent selon le véhicule. C'est ce qui justifie d'avoir trois
leaderboards plutôt qu'un. »). Ce document couvre le Lot A (voir
`sim/element_effects.gd`, `sim/car_sim.gd`) : les éléments à effet de
zone/contact, sans nouvelle physique de collision.

## Règle de lecture

**Aucun nombre par véhicule n'est inventé dans ce document.** Chaque
élément utilise une seule magnitude partagée par les 5 véhicules (voir le
tableau des constantes ci-dessous). La différenciation par véhicule
**émerge** des stats déjà réglées de chaque fiche (`sim/car_configs/*.gd`,
`Paramétrage-Véhicules.md`) — un même effet touche différemment un véhicule
lourd/lent et un véhicule léger/rapide sans qu'il faille dupliquer une
constante cinq fois. C'est un choix de conception assumé, pas un état
provisoire en attendant que quelqu'un remplisse un tableau : voir le
tableau « élément × stat responsable » plus bas pour le détail de chaque
cas.

## Constantes Lot A (`sim/element_effects.gd`)

Valeurs de départ, à ajuster manette en main comme tout le reste du
gameplay (CLAUDE.md, « Ce qu'il ne faut pas faire ») :

| Constante | Valeur | Ancrage |
| --- | --- | --- |
| `RAYON_ZONE_M` (ralentit/dégradé/aimantée) | 6,0 m | > `DEFAULT_HALF_WIDTH` (5,0) de l'éditeur, un marqueur couvre la piste |
| `RAYON_PAD_M` (boost, rampe) | 3,0 m | = `SELECTION_RADIUS` de l'éditeur, un pad qu'on vise |
| `RAYON_PLOT_M` (obstacle_ralentit, obstacle_mortel) | 2,0 m | 3x le plancher anti-traversée (voir garde-fou ci-dessous) |
| `RAYON_VIDE_M` | 4,0 m | un trou, plus grand qu'un plot |
| `RALENTIT_PLAFOND_KMH` | 95,0 | ~moitié de la fourchette 175-195 km/h |
| `RALENTIT_RESISTANCE_MS2` | 14,0 | entre `freinage_ms2` min (3,0) et max (18,0) |
| `DEGRADE_AUTORITE` | 0,45 | entre `boost_destab_facteur` d'Halcyon (0,35) et `controle_aerien` du Roadster (0,50) |
| `AIMANT_BONUS_MS2` | +10,0 (additif) | Halcyon +79 %, Needle +28 % — égalisateur, comme la règle du boost |
| `PLOT_PENALITE_KMH` | 35,0 | < le gain du boost (45) : un plot coûte moins qu'un boost ne rapporte |
| `MORTEL_PENALITE_KMH` | 250,0 | > 195+45 : arrêt garanti pour tous, jamais de marche arrière |
| `MORTEL_AUTORITE` | 0,15 | sous le pire du jeu (Halcyon, `controle_aerien` 0,20) |
| `MORTEL_CONTROLE_PERDU_S` | 1,5 s | ~2x la déstabilisation post-boost d'Halcyon (0,8 s) |
| `RAMPE_HAUTEUR_M` | 1,2 m | 2x le petit saut de Wasp (0,6 m) |
| `RAMPE_DUREE_S` | 0,7 s | 1,55x celle de Wasp (0,45 s) |

**Garde-fou non négociable** (verrouillé par `tools/run_tests.gd::_test_element_rayons`) :
à vitesse_max + boost (Halcyon, 195+45 km/h), la voiture avance 0,667 m par
tick — tout rayon de détection non nul reste ≥ 2,0 m (3x cette distance),
sinon l'échantillonnage ponctuel peut sauter par-dessus un élément sans
jamais le détecter.

## Élément × stat responsable de la différenciation

| Élément | Mécanisme (Lot A) | Stat(s) qui différencient les véhicules |
| --- | --- | --- |
| `route_ralentit` | Plafond DOUX (résistance seulement au-dessus du plafond, jamais un clamp dur — voir arbitrage dans `car_sim.gd`) | Vitesse de réaccélération en sortie de zone : `accel_basse`/`accel_haute` (4,0 à 13,5 m/s²). Perte absolue plus grande pour les véhicules à `vitesse_max` élevée (Halcyon, Needle) que pour les plus lents. |
| `route_degrade_controles` | Multiplie l'autorité de direction (min si plusieurs zones se chevauchent, jamais un cumul) | Temps de RÉCUPÉRATION après la zone : `vitesse_braquage_deg_s` (70 à 400°/s) — Ironside (110°/s) reste pénalisé ~4x plus longtemps que Needle (400°/s) pour revenir à son angle cible. Cas particulier documenté : la contribution de `glisse_intensite` à l'angle effectif (Roadster en PIVOT_AVANT) n'est PAS gatée par cette réduction — un Roadster qui dérape garde l'essentiel de sa rotation dans la zone, assumé comme la « réponse » spécifique du Roadster à cet élément. |
| `route_aimantee` | Bonus ADDITIF au budget latéral (max si plusieurs zones, jamais un cumul), après le multiplicateur de glisse, jamais en l'air | Additif plutôt que multiplicatif : proportionnellement bien plus fort pour l'adhérence la plus faible. Halcyon (12,6 m/s²) : +79 %. Needle (36,0 m/s²) : +28 %. Un tronçon aimanté peut donc redistribuer l'ordre d'un classement. Sans effet pendant la phase ARC de Wasp (`budget_illimite`). |
| `obstacle_ralentit` | Pénalité ponctuelle de vitesse à l'entrée dans le rayon, retrigger possible en sortant/rentrant | Coût identique en absolu pour tous (comme le boost) — proportionnellement plus douloureux pour les véhicules déjà lents (Halcyon) que pour les rapides. |
| `obstacle_mortel` / `vide` | Repli EXPLICITE : arrêt net (vitesse à 0, jamais négative) + verrou d'autorité de direction ~1,5 s. **Pas un système de mort/réapparition** — CLAUDE.md liste encore « repop » comme non construit (État actuel : « checkpoints et repop restants »). Remplacer par un vrai repop plus tard ne touche qu'un point d'appel (`CarSim.appliquer_penalite()`). | L'arrêt est absolu (identique pour tous), mais le temps perdu à repartir dépend de `accel_basse` de chaque véhicule — Wasp (13,5) repart nettement plus vite qu'Halcyon (4,0). |
| `rampe` | Lancement générique (vitesse verticale + gravité PROPRES à la rampe, jamais celles d'un véhicule — `CarState.saut_gravite_courante` distingue le saut en cours), `budget` forcé à 0 en l'air (vol rectiligne, pas de correction de trajectoire) | `controle_aerien` (0,20 à 0,90) pendant tout le vol — un nothing-burger pour Needle (0,90), un engagement pour Halcyon (0,20). Vol rectiligne : un grand saut sur une piste qui tourne tape le mur à l'atterrissage, même famille que l'arbitrage 8 du saut de Wasp (assumé, pas une règle cachée). |
| `boost` | Réutilise `CarSim.declencher_boost()` (poussée absolue +45 km/h dans la direction de la trajectoire, déstabilisation propre à chaque véhicule) — déjà testé (`_test_boost`) avant ce lot, juste câblé à l'élément de piste | Identique au boost déjà documenté dans CLAUDE.md : seul Halcyon subit une déstabilisation (`boost_destab_facteur` 0,35), et un boost pris en dérapage projette vers l'extérieur pour tout véhicule qui dérape. |
| `route_normale`, `ligne_depart_arrivee` | Aucun effet (rayon 0 dans `ElementEffects.rayons`) — `route_normale` est le comportement par défaut, `ligne_depart_arrivee` reste purement déclarative : la vraie porte de départ/arrivée est calculée géométriquement par `sim/race_state.gd` depuis le tracé, jamais depuis un élément posé. | — |

## Lot B (nommé, pas encore traité)

`mur`, `obstacle_bloquant`, `barriere` : nécessitent une vraie collision
orientée (position + rotation, hitbox) contre un obstacle placé n'importe
où — un problème différent du clamp de bord de piste existant
(`sim/car_sim.gd`, étape 14, qui ne connaît que le tracé). Note :
`editor/track_editor.gd` écrit `rotation = 0` pour tout élément posé
aujourd'hui, donc une collision orientée demande aussi du travail côté
éditeur.

`checkpoint` : invisible pour le joueur, valide le point de réapparition
courant (pas d'anti-raccourci — décision explicite, voir CLAUDE.md
« Vocabulaire du projet », pour éviter d'avoir à maintenir un leaderboard
séparé pour les runs abusant de raccourcis façon Mario Kart Wii). Dépend du
système de repop lui-même (toujours à construire) et d'une détection de
"chute" — distinct de la simple détection de zone du Lot A.
