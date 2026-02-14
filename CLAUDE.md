# CLAUDE.md

## Projet

Roon Controller — app macOS native (SwiftUI) pour controler un systeme audio Roon. Se connecte directement au Roon Core via les protocoles natifs SOOD (discovery UDP) et MOO/1 (WebSocket).

## Structure

```
RoonController/
├── Models/RoonModels.swift           # Modeles de donnees
├── Services/RoonService.swift        # Orchestrateur principal (@MainActor)
├── Services/Roon/Core/               # Connexion, registration
├── Services/Roon/Protocol/           # SOOD, MOO/1
├── Services/Roon/Services/           # Transport, Browse, Image, Status
├── Services/Roon/Image/              # Serveur image local, cache
├── Views/                            # SwiftUI (Player, Sidebar, Queue, History, Favorites, etc.)
└── Tests/                            # Tests unitaires (218 tests)
```

## Build & Test

```bash
cd RoonController
xcodebuild build -scheme RoonController -destination 'platform=macOS' -quiet
xcodebuild test -scheme RoonController -destination 'platform=macOS'
```

## Deploy

```bash
# Build Release (Universal Binary arm64+x86_64), copier dans /Applications, generer DMG
xcodebuild build -scheme RoonController -destination 'generic/platform=macOS' -configuration Release -quiet
rm -rf "/Applications/Roon Controller.app"
cp -R "$(xcodebuild -scheme RoonController -configuration Release -showBuildSettings 2>/dev/null | grep ' BUILD_DIR' | awk '{print $3}')/Release/Roon Controller.app" /Applications/
hdiutil create -volname "Roon Controller" -srcfolder "/Applications/Roon Controller.app" -ov -format UDZO ~/Desktop/RoonController.dmg
```

## Stack audio

- **Roon Controller** : controle (cette app)
- **Roon Bridge** (`/Applications/RoonBridge.app`) : daemon exposant les sorties audio (DAC) du Mac au Roon Core via RAAT. Lance automatiquement au login. Roon.app n'est pas necessaire.
- **Roon Core** : serveur Roon sur le reseau local

## Conventions

- Langue du code : anglais
- Langue de l'UI et des docs : francais (sans accents dans les .md)
- Commits : message en anglais, imperatif, avec `Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>`
- Squash les commits lies avant push final
- Toujours lancer les tests apres modification

## Points d'attention

- `PlaybackHistoryItem.isRadio` : detecte via `zone.is_seek_allowed == false`. Backward-compatible (decode a `false` si absent du JSON)
- Radio replay : utilise la hierarchie `internet_radio` du Browse API, pas la recherche textuelle. Le nom de la station est dans `album` (si metadata dispo) ou `title` (sinon)
- `playBrowseItem()` accepte un parametre `hierarchy` pour supporter `internet_radio` en plus de `browse`
- `RadioFavorite` : stocke `title` (morceau), `artist`, `stationName` separement. Ancien format `"Artiste - Titre"` dans title avec artist vide est gere (backward-compatible)
- Export CSV favoris : format `Artist,Title` compatible Soundiiz. L'API Roon Browse ne supporte pas "Add to Playlist" pour les extensions
- Seek interpolation : timer local 1s quand state=="playing", resynchronise par `zones_seek_changed` du serveur
- L'app n'est pas signee (pas de Developer ID). Les utilisateurs doivent faire clic droit > Ouvrir la premiere fois
