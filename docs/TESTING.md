# Guide de test

## Prerequis

- Backend Node.js lance (`node server.js`)
- Roon Core actif et paire avec l'extension
- App macOS buildee et lancee

## Tests manuels

### 1. Connexion

| # | Test | Resultat attendu |
|---|------|-------------------|
| 1.1 | Lancer le backend puis l'app | L'app affiche "Connecte", les zones apparaissent |
| 1.2 | Lancer l'app SANS backend | Ecran de connexion, "Deconnecte du backend" |
| 1.3 | Lancer l'app puis le backend | Reconnexion automatique, zones apparaissent |
| 1.4 | Arreter le backend pendant l'utilisation | Reconnexion automatique avec backoff |
| 1.5 | Connexion manuelle par IP | Le Core se paire, les zones apparaissent |
| 1.6 | Modifier host/port dans Parametres | Reconnexion au nouveau backend |

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

### 6. Parametres

| # | Test | Resultat attendu |
|---|------|-------------------|
| 6.1 | Ouvrir Parametres (Cmd+,) | Fenetre de parametres |
| 6.2 | Modifier le port | Apres "Appliquer", reconnexion sur le nouveau port |
| 6.3 | Connexion manuelle Core | Le Core se paire |

## Verification du build

```bash
cd "Roon client/RoonController"
xcodebuild -scheme RoonController -configuration Debug build 2>&1 | tail -5
```

Resultat attendu :
```
** BUILD SUCCEEDED **
```

## Verification du backend

```bash
cd "Roon client/node-backend"
node -e "require('./server.js')" &
sleep 3
curl -s http://localhost:3333/api/status | python3 -m json.tool
kill %1
```

Le endpoint `/api/status` doit repondre avec un JSON valide.

## Tests automatises (Swift / XCTest)

Le projet inclut 20 tests unitaires dans la target `RoonControllerTests`.

### Lancer les tests

```bash
cd "Roon client/RoonController"
xcodebuild test -project RoonController.xcodeproj \
  -scheme RoonControllerTests \
  -destination 'platform=macOS'
```

Ou depuis Xcode : **Product > Test** (Cmd+U).

### Fichiers de tests

| Fichier | Tests | Description |
|---------|-------|-------------|
| `Tests/RoonModelsTests.swift` | 11 tests | Decodage JSON des modeles (BrowseItem, InputPrompt, QueueItem, PlaybackHistoryItem, RoonZone, BrowseResult) |
| `Tests/RoonServiceTests.swift` | 9 tests | Logique du service (garde anti-doublon browse, historique, selection de zone, generation d'URL image) |

### Detail des tests

**RoonModelsTests** :
- `testBrowseItemDecodesInputPromptAsObject` — input_prompt decode comme objet (pas String)
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

### Note sur le nom du module

Le module Swift s'appelle `Roon_Controller` (avec underscore) car le PRODUCT_NAME est "Roon Controller" (avec espace). Les imports de test utilisent `@testable import Roon_Controller`.

### Pistes d'amelioration

- **Tests backend** : ajouter des tests Jest pour `server.js` (necessite un refactoring pour exporter les handlers)
- **Tests d'integration** : simuler un serveur WS mock pour tester `RoonService` end-to-end
- **Tests UI** : XCUITest pour les parcours utilisateur critiques
- **CI** : `xcodebuild test` dans une GitHub Action
