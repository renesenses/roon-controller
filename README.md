# Roon Controller

Application macOS native (SwiftUI) pour controler un systeme audio [Roon](https://roon.app). L'app se connecte directement au Roon Core via les protocoles natifs SOOD et MOO, sans intermediaire.

## Architecture

```
┌──────────────────────────┐     SOOD (UDP multicast)     ┌──────────────┐
│    App macOS (Swift)     │  ──────────────────────────→  │  Roon Core   │
│    SwiftUI · native      │                               │  (serveur)   │
│                          │  ←────────────────────────→   │              │
│  SOOD · MOO/1 · WS      │     WebSocket (MOO/1)         │  port 9330   │
└──────────────────────────┘                               └──────────────┘
```

- **App macOS** : interface SwiftUI avec implementation native des protocoles Roon (SOOD discovery + MOO/1 sur WebSocket)
- **Roon Core** : serveur Roon sur le reseau local, decouvert automatiquement (SOOD) ou par IP manuelle

## Fonctionnalites

- Decouverte automatique du Roon Core via protocole SOOD ou connexion manuelle par IP
- Affichage de toutes les zones avec etat de lecture et volume
- Lecteur complet : play/pause, next/previous, seek, shuffle, repeat, radio
- Pochette d'album avec fond flou en arriere-plan
- Navigation dans la bibliotheque Roon (Browse API)
- Recherche dans les resultats de navigation
- File d'attente (queue) avec lecture depuis un morceau
- Controle du volume par sortie (slider + mute)
- Historique de lecture avec replay
- Reconnexion automatique avec backoff exponentiel
- Theme sombre style Roon

## Prerequis

- **macOS 15.0** (Sequoia) ou superieur
- **Xcode 16** ou superieur
- Un **Roon Core** actif sur le reseau local

## Installation rapide

```bash
# 1. Cloner le depot
git clone https://github.com/renesenses/roon-controller.git
cd roon-controller

# 2. Ouvrir et lancer l'app
cd RoonController
open RoonController.xcodeproj
# Puis Build & Run (Cmd+R) dans Xcode
```

> Voir [docs/INSTALL.md](docs/INSTALL.md) pour les instructions detaillees.

## Utilisation

1. Lancez l'app macOS depuis Xcode (Cmd+R)
2. L'app decouvre automatiquement le Roon Core via SOOD sur le reseau local
3. Autorisez l'extension "Roon Controller macOS" dans **Roon > Parametres > Extensions**
4. Les zones apparaissent dans la barre laterale — selectionnez-en une pour commencer

> Pour une connexion manuelle : ouvrez **Parametres** (Cmd+,) et entrez l'adresse IP du Core.

## Structure du projet

```
Roon client/
├── RoonController/
│   ├── RoonControllerApp.swift          # Point d'entree de l'app
│   ├── Models/
│   │   └── RoonModels.swift             # Modeles de donnees (Zone, NowPlaying, Queue, Browse...)
│   ├── Services/
│   │   ├── RoonService.swift            # Orchestrateur principal (@MainActor ObservableObject)
│   │   └── Roon/
│   │       ├── Core/
│   │       │   ├── RoonConnection.swift     # Cycle de vie complet : discovery → WS → registration → routing
│   │       │   └── RoonRegistration.swift   # Handshake d'enregistrement et persistence du token
│   │       ├── Protocol/
│   │       │   ├── SOODDiscovery.swift      # Decouverte SOOD (UDP multicast, sockets POSIX)
│   │       │   ├── MOOTransport.swift       # Transport WebSocket binaire (MOO/1)
│   │       │   └── MOOMessage.swift         # Construction et parsing des messages MOO/1
│   │       ├── Services/
│   │       │   ├── RoonTransportService.swift   # API transport (play, pause, seek, volume, queue)
│   │       │   ├── RoonBrowseService.swift      # API browse (navigation bibliotheque)
│   │       │   ├── RoonImageService.swift       # API image (pochettes)
│   │       │   └── RoonStatusService.swift      # API status
│   │       └── Image/
│   │           ├── LocalImageServer.swift       # Serveur HTTP local pour les pochettes
│   │           ├── RoonImageProvider.swift      # Fournisseur d'images async
│   │           └── RoonImageCache.swift         # Cache LRU pour les pochettes
│   ├── Views/
│   │   ├── ContentView.swift            # Vue racine (connexion ou lecteur)
│   │   ├── ConnectionView.swift         # Ecran de connexion
│   │   ├── PlayerView.swift             # Lecteur principal (pochette, controles, seek)
│   │   ├── SidebarView.swift            # Barre laterale (zones, bibliotheque, queue, historique)
│   │   ├── QueueView.swift              # File d'attente
│   │   ├── HistoryView.swift            # Historique de lecture
│   │   ├── SettingsView.swift           # Preferences (connexion manuelle)
│   │   └── Helpers/
│   │       └── RoonColors.swift         # Palette de couleurs Roon
│   └── Tests/
│       ├── RoonModelsTests.swift        # Tests modeles de donnees
│       └── RoonServiceTests.swift       # Tests service et protocole MOO
│
├── docs/
│   ├── INSTALL.md                   # Guide d'installation
│   ├── ARCHITECTURE.md              # Architecture technique
│   ├── TESTING.md                   # Guide de test
│   └── TROUBLESHOOTING.md          # Depannage
│
└── node-backend/                    # (legacy) Ancien backend Node.js — non utilise
```

## Documentation

| Document | Description |
|----------|-------------|
| [docs/INSTALL.md](docs/INSTALL.md) | Guide d'installation |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Architecture technique et protocoles |
| [docs/TESTING.md](docs/TESTING.md) | Procedures de test et checklist |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Depannage |

## Licence

Projet personnel. L'API Roon est fournie par [Roon Labs](https://roon.app).
