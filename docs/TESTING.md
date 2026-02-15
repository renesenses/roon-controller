> **[English version](TESTING.en.md)** | Francais

# Guide de test

## Prerequis

- Roon Core actif et paire avec l'extension
- App macOS buildee et lancee

## Tests manuels

### 1. Connexion

| # | Test | Resultat attendu |
|---|------|-------------------|
| 1.1 | Lancer l'app avec un Core sur le reseau | Decouverte SOOD, connexion automatique, zones apparaissent |
| 1.2 | Lancer l'app sans Core sur le reseau | Ecran de connexion, tentatives de decouverte periodiques |
| 1.3 | Eteindre le Core pendant l'utilisation | Reconnexion automatique avec backoff exponentiel |
| 1.4 | Rallumer le Core | Reconnexion automatique, zones reapparaissent |
| 1.5 | Connexion manuelle par IP (Parametres) | Le Core se paire, les zones apparaissent |
| 1.6 | Premier lancement (pas de token) | L'extension apparait dans Roon > Extensions, attente d'autorisation |

### 2. Zones

| # | Test | Resultat attendu |
|---|------|-------------------|
| 2.1 | Selectionner une zone | La zone est surlignee, le lecteur affiche son contenu |
| 2.2 | Zone en lecture | Indicateur vert "play" dans la sidebar |
| 2.3 | Zone en pause | Indicateur orange "pause" dans la sidebar |
| 2.4 | Zone arretee | Indicateur gris "stop" dans la sidebar |
| 2.5 | Mini pochette dans la sidebar | Pochette 40x40 a cote du titre en cours |
| 2.6 | Volume slider | Le slider bouge, le volume change dans Roon |
| 2.7 | Bouton mute | L'icone passe en rouge, le son est coupe |

### 3. Lecteur

| # | Test | Resultat attendu |
|---|------|-------------------|
| 3.1 | Play/Pause | La lecture demarre/se met en pause |
| 3.2 | Next/Previous | Piste suivante/precedente |
| 3.3 | Seek (clic sur la barre) | La position de lecture change |
| 3.4 | Pochette d'album | Affichee en grand (400x400), fond flou derriere |
| 3.5 | Infos piste | Titre, artiste, album affiches |
| 3.6 | Compteur de temps | Position et duree affiches, progression en temps reel |
| 3.7 | Shuffle | Le bouton s'allume en bleu, lecture aleatoire activee |
| 3.8 | Repeat | Cycle : off → loop → loop_one → off |
| 3.9 | Auto Radio | Le bouton s'allume en bleu, radio Roon activee |

### 4. File d'attente (Queue)

| # | Test | Resultat attendu |
|---|------|-------------------|
| 4.1 | Onglet "File d'attente" | La liste des morceaux en queue s'affiche |
| 4.2 | Morceau en cours | Surbrille avec fond bleu accent (opacity 0.15) |
| 4.3 | Pochette mini | 40x40, coins arrondis, a gauche de chaque item |
| 4.4 | Titre et artiste | Affiches sur deux lignes |
| 4.5 | Duree | Affichee a droite en format m:ss |
| 4.6 | Tap sur un morceau | La lecture reprend depuis ce morceau |
| 4.7 | Changement de zone | La queue se vide puis se recharge pour la nouvelle zone |
| 4.8 | Queue vide | Message "File d'attente vide" avec icone |

### 5. Bibliotheque (Browse)

| # | Test | Resultat attendu |
|---|------|-------------------|
| 5.1 | Onglet "Bibliotheque" | Bouton "Parcourir la bibliotheque" |
| 5.2 | Clic sur le bouton | Liste des categories (Albums, Artistes, etc.) |
| 5.3 | Navigation dans une categorie | Liste des items avec pochettes |
| 5.4 | Bouton retour | Remonte d'un niveau |
| 5.5 | Bouton home | Revient a la racine |
| 5.6 | Recherche | Filtre les resultats affiche |
| 5.7 | Action sur un item | Lecture ou sous-navigation selon le hint |

### 6. Historique

| # | Test | Resultat attendu |
|---|------|-------------------|
| 6.1 | Lecture d'un morceau | Apparait en haut de l'historique |
| 6.2 | Clic sur un morceau | Recherche et lecture dans la bibliotheque Roon |
| 6.3 | Bouton effacer | L'historique est vide |
| 6.4 | Redemarrage de l'app | L'historique est restaure (persistence fichier) |

### 7. Vues Browse specialisees

| # | Test | Resultat attendu |
|---|------|-------------------|
| 7.1 | Clic sur Genres dans la sidebar | Grille de cartes genre avec gradients colores |
| 7.2 | Clic sur un genre | Navigation vers les sous-genres ou albums (grille normale) |
| 7.3 | Clic sur TIDAL dans la sidebar | Carousel par sections avec cartes icones (mode Roon) |
| 7.3b | Onglet TIDAL dans la sidebar Player | Carousels compacts 100px depuis le cache disque |
| 7.3c | Onglet Qobuz dans la sidebar Player | Carousels compacts 100px depuis le cache disque |
| 7.3d | Tap sur une carte streaming (Player) | Navigation vers l'album dans la section Bibliotheque |
| 7.4 | Clic sur Morceaux dans la sidebar | Tableau de morceaux avec pochettes (pas de header playlist) |
| 7.5 | Scroll dans la vue Morceaux | Les pochettes se chargent en avance (prefetch) |
| 7.6 | Clic sur Compositeurs dans la sidebar | Grille circulaire avec initiales |
| 7.7 | Bouton bascule mode (sidebar) | Passage du mode Roon au mode Player |

### 8. macOS Now Playing (Control Center)

| # | Test | Resultat attendu |
|---|------|-------------------|
| 8.1 | Lecture d'un morceau | Titre, artiste, album dans le Control Center macOS |
| 8.2 | Pochette dans Control Center | La pochette de l'album s'affiche |
| 8.3 | Bouton play/pause du Control Center | La lecture demarre/se met en pause |
| 8.4 | Bouton next/prev du Control Center | Piste suivante/precedente |
| 8.5 | Barre de progression Control Center | Position mise a jour, seek possible |
| 8.6 | Changement de piste | Les infos se mettent a jour automatiquement |

### 9. Parametres

| # | Test | Resultat attendu |
|---|------|-------------------|
| 9.1 | Ouvrir Parametres (Cmd+,) | Fenetre de parametres |
| 9.2 | Connexion manuelle Core | Le Core se paire |
| 9.3 | Bouton Reconnecter | Deconnexion puis reconnexion SOOD |
| 9.4 | Zone par defaut | Picker liste les zones, choix persiste au redemarrage |
| 9.5 | Nombre de playlists sidebar | Picker 5/10/20/50/Toutes, applique immediatement |

## Verification du build

```bash
cd "Roon client/RoonController"
xcodebuild -scheme RoonController -configuration Debug build 2>&1 | tail -5
```

Resultat attendu :
```
** BUILD SUCCEEDED **
```

## Tests automatises (Swift / XCTest)

Le projet inclut des tests unitaires dans la target `RoonControllerTests`.

### Lancer les tests

```bash
cd "Roon client/RoonController"
xcodebuild test -project RoonController.xcodeproj \
  -scheme RoonControllerTests \
  -destination 'platform=macOS'
```

Ou depuis Xcode : **Product > Test** (Cmd+U).

### Fichiers de tests

| Fichier | Description |
|---------|-------------|
| `Tests/RoonModelsTests.swift` | Decodage JSON des modeles (BrowseItem, InputPrompt, QueueItem, PlaybackHistoryItem, RoonZone, BrowseResult) |
| `Tests/RoonServiceTests.swift` | Logique du service (browse guard, historique, selection de zone, URL image) et protocole MOO (parsing, construction, request ID) |
| `Tests/ViewBehaviorTests.swift` | Tests comportement des vues (zone par defaut, filtrage playlists, mode UI, vues browse specialisees, Now Playing, onglets streaming) |

### Detail des tests

**RoonModelsTests** :
- `testBrowseItemDecodesInputPromptAsObject` — input_prompt decode comme objet
- `testBrowseItemDecodesWithoutInputPrompt` — input_prompt optionnel
- `testBrowseItemIdUsesItemKey` / `testBrowseItemIdFallsBackToTitle` — logique Identifiable
- `testWSBrowseResultDecodesWithInputPromptItems` — decodage complet d'un browse_result mixte
- `testBrowseResultItemsAreMutable` — items et offset modifiables (pagination)
- `testPlaybackHistoryItemRoundTrip` — encodage/decodage JSON avec dates ISO 8601
- `testRoonZoneEqualityIncludesNowPlaying` / `testRoonZoneEqualityIncludesSeekPosition` — Equatable correct
- `testQueueItemDecoding` — decodage QueueItem complet
- `testInputPromptDecoding` — decodage InputPrompt

**RoonServiceTests** (`@MainActor`) :
- `testBrowsePendingKeyBlocksDuplicate` — un meme item_key ne declenche pas deux browse
- `testBrowseDifferentKeyPassesGuard` — un item_key different passe le garde
- `testBrowseBackResetsPendingKey` / `testBrowseHomeResetsPendingKey` — la navigation reset le garde
- `testBrowseWithoutItemKeySkipsGuard` — le browse racine n'est jamais bloque
- `testHistoryIsInitiallyEmpty` / `testClearHistoryRemovesAll` — gestion de l'historique
- `testHistoryDeduplicationPreventsConsecutiveSameTrack` — pas de doublon consecutif
- `testSelectZoneClearsQueue` — changer de zone vide la queue
- `testImageURLGeneration` / `testImageURLReturnsNilForNilKey` — construction d'URL image
- `testMOOMessageParseRequest` / `ParseContinue` / `ParseComplete` — parsing des 3 verbes MOO
- `testMOOMessageBuildRequest` / `BuildComplete` — construction et round-trip
- `testMOOMessageParseInvalidReturnsNil` / `ParseMissingRequestIdReturnsNil` — cas d'erreur
- `testMOORequestIdGeneratorIncrementsAtomically` — generateur d'IDs atomique

### Note sur le nom du module

Le module Swift s'appelle `Roon_Controller` (avec underscore) car le PRODUCT_NAME est "Roon Controller" (avec espace). Les imports de test utilisent `@testable import Roon_Controller`.

### Pistes d'amelioration

- **Tests d'integration** : simuler un serveur WebSocket mock pour tester `RoonService` end-to-end
- **Tests SOOD** : paquet SOOD mock pour valider le parsing des reponses
- **Tests UI** : XCUITest pour les parcours utilisateur critiques
- **CI** : `xcodebuild test` dans une GitHub Action
