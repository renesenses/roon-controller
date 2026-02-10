# Roon Controller

Application macOS native (SwiftUI) pour controler un systeme audio [Roon](https://roon.app), via un backend Node.js qui se connecte a l'API Roon.

## Architecture

```
┌──────────────────────┐      WebSocket       ┌───────────────────┐      Roon API      ┌──────────────┐
│   App macOS (Swift)  │  ←────────────────→  │  Backend Node.js  │  ←───────────────→  │  Roon Core    │
│   SwiftUI · port WS  │     JSON messages     │  Express · WS     │     SOOD/TCP       │  (serveur)    │
└──────────────────────┘                       └───────────────────┘                     └──────────────┘
```

- **App macOS** : interface SwiftUI, communique avec le backend via WebSocket (JSON)
- **Backend Node.js** : passerelle entre l'app et l'API Roon (transport, browse, image, queue)
- **Roon Core** : serveur Roon sur le reseau local, decouvert automatiquement (SOOD) ou par IP manuelle

## Fonctionnalites

- Decouverte automatique du Roon Core ou connexion manuelle par IP
- Affichage de toutes les zones avec etat de lecture et volume
- Lecteur complet : play/pause, next/previous, seek, shuffle, repeat, radio
- Pochette d'album avec fond flou en arriere-plan
- Navigation dans la bibliotheque Roon (Browse API)
- Recherche dans les resultats de navigation
- File d'attente (queue) avec lecture depuis un morceau
- Controle du volume par sortie (slider + mute)
- Reconnexion automatique backend et Core
- Theme sombre style Roon

## Prerequis

- **macOS 15.0** (Sequoia) ou superieur
- **Xcode 16** ou superieur
- **Node.js 18+**
- Un **Roon Core** actif sur le reseau local

## Installation rapide

```bash
# 1. Cloner le depot
git clone https://github.com/renesenses/roon-controller.git
cd roon-controller

# 2. Installer et lancer le backend
cd node-backend
npm install
node server.js

# 3. Ouvrir et lancer l'app
cd ../RoonController
open RoonController.xcodeproj
# Puis Build & Run (Cmd+R) dans Xcode
```

> Voir [docs/INSTALL.md](docs/INSTALL.md) pour les instructions detaillees.

## Utilisation

1. Lancez le backend Node.js (`node server.js`) — il ecoute sur le port 3333
2. Lancez l'app macOS depuis Xcode
3. L'app se connecte automatiquement au backend WebSocket
4. Le backend decouvre le Roon Core via SOOD (ou connectez-vous manuellement par IP)
5. Autorisez l'extension "Roon Controller macOS" dans **Roon > Parametres > Extensions**
6. Les zones apparaissent dans la barre laterale — selectionnez-en une pour commencer

## Structure du projet

```
Roon client/
├── node-backend/
│   ├── server.js              # Serveur Express + WebSocket + API Roon
│   ├── package.json
│   └── config/                # Etat persistant Roon (auto-genere)
│
├── RoonController/
│   ├── RoonControllerApp.swift    # Point d'entree de l'app
│   ├── Models/
│   │   └── RoonModels.swift       # Modeles de donnees (Zone, NowPlaying, Queue, Browse...)
│   ├── Services/
│   │   └── RoonService.swift      # Service WebSocket + logique metier
│   ├── Views/
│   │   ├── ContentView.swift      # Vue racine (connexion ou lecteur)
│   │   ├── ConnectionView.swift   # Ecran de connexion
│   │   ├── PlayerView.swift       # Lecteur principal (pochette, controles, seek)
│   │   ├── SidebarView.swift      # Barre laterale (zones, bibliotheque, queue)
│   │   ├── QueueView.swift        # File d'attente
│   │   ├── SettingsView.swift     # Preferences (host/port backend)
│   │   └── Helpers/
│   │       └── RoonColors.swift   # Palette de couleurs Roon
│   ├── RoonController.entitlements
│   └── RoonController.xcodeproj/
│
└── docs/
    ├── INSTALL.md             # Guide d'installation complet
    ├── ARCHITECTURE.md        # Documentation technique
    └── TESTING.md             # Guide de test
```

## Documentation

| Document | Description |
|----------|-------------|
| [docs/INSTALL.md](docs/INSTALL.md) | Guide d'installation detaille |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Architecture technique, protocole WS, modeles |
| [docs/TESTING.md](docs/TESTING.md) | Procedures de test et checklist |

## Licence

Projet personnel. L'API Roon est fournie par [Roon Labs](https://roon.app).
