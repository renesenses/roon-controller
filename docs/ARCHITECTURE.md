# Architecture technique

## Vue d'ensemble

Roon Controller est compose de deux parties :

1. **Backend Node.js** — passerelle WebSocket/HTTP vers l'API Roon
2. **App macOS SwiftUI** — interface utilisateur native

Le backend encapsule toute la complexite de l'API Roon (protocole SOOD, souscriptions, callbacks) et expose une interface WebSocket simple en JSON que l'app Swift consomme.

## Backend Node.js

### Fichier : `node-backend/server.js`

#### Composants

| Module | Role |
|--------|------|
| `RoonApi` | Decouverte Core, pairing, gestion d'etat |
| `RoonApiTransport` | Zones, transport (play/pause/seek), queue, settings |
| `RoonApiBrowse` | Navigation bibliotheque |
| `RoonApiImage` | Recuperation des pochettes |
| `RoonApiStatus` | Status de l'extension |
| `Express` | Serveur HTTP pour le proxy image |
| `ws` | Serveur WebSocket pour la communication temps-reel |

#### Souscriptions Roon

Le backend maintient des souscriptions actives vers le Core :

- **`subscribe_zones`** : recoit les mises a jour des zones en temps reel (broadcast a tous les clients WS)
- **`subscribe_queue`** : souscription par client WS, recoit la file d'attente pour une zone (envoye uniquement au client concerne)

#### Endpoints HTTP

| Endpoint | Description |
|----------|-------------|
| `GET /api/status` | Etat de connexion, liste des zones |
| `GET /api/image/:key` | Proxy image avec cache (pochettes) |

### Protocole WebSocket

Tous les messages sont en JSON. Format : `{ "type": "...", ...payload }`.

#### Messages client → backend

| Type | Parametres | Description |
|------|-----------|-------------|
| `transport/control` | `zone_id`, `control` (play/pause/playpause/stop/previous/next) | Controle de lecture |
| `transport/seek` | `zone_id`, `how` (absolute/relative), `seconds` | Seek |
| `transport/volume` | `output_id`, `value`, `how` | Changement de volume |
| `transport/mute` | `output_id`, `how` (mute/unmute/toggle) | Mute |
| `transport/settings` | `zone_id`, `shuffle?`, `loop?`, `auto_radio?` | Parametres de zone |
| `transport/subscribe_queue` | `zone_id` | S'abonner a la queue d'une zone |
| `transport/play_from_here` | `zone_id`, `queue_item_id` | Lire depuis un element de la queue |
| `browse/browse` | `hierarchy`, `zone_id?`, `item_key?`, `input?`, `pop_levels?`, `pop_all?` | Naviguer dans la bibliotheque |
| `browse/load` | `hierarchy`, `offset`, `count` | Charger une page de resultats |
| `core/connect` | `ip` | Connexion manuelle au Core |
| `get_zones` | — | Demander la liste des zones |

#### Messages backend → client

| Type | Payload | Distribution |
|------|---------|-------------|
| `state` | `state` (connected/disconnected/connecting) | Broadcast |
| `zones` | `zones: [Zone]` | Broadcast |
| `zones_changed` | `zones: [Zone]` | Broadcast |
| `queue` | `zone_id`, `items: [QueueItem]` | Unicast (client abonne) |
| `browse_result` | `action`, `list`, `items`, `offset` | Unicast (client demandeur) |
| `error` | `message` | Unicast |

#### Gestion des souscriptions queue

- Chaque client WS peut avoir une souscription queue active (`ws.__queue_sub`)
- A chaque nouvelle `transport/subscribe_queue`, l'ancienne souscription est annulee
- La souscription est nettoyee a la deconnexion du client

## App macOS (SwiftUI)

### Modeles (`RoonModels.swift`)

```
RoonZone
├── zone_id: String
├── display_name: String
├── state: String?              // playing, paused, loading, stopped
├── now_playing: NowPlaying?
├── outputs: [RoonOutput]?
├── settings: ZoneSettings?
├── seek_position: Int?
└── is_play/pause/seek/previous/next_allowed: Bool?

NowPlaying
├── one_line / two_line / three_line: LineInfo?
├── length: Int?
├── seek_position: Int?
└── image_key: String?

NowPlaying.LineInfo
├── line1 / line2 / line3: String?

QueueItem
├── queue_item_id: Int
├── one_line / two_line / three_line: LineInfo?
├── length: Int?
└── image_key: String?

RoonOutput
├── output_id: String
├── display_name: String
├── zone_id: String?
└── volume: VolumeInfo?

BrowseItem
├── title / subtitle: String?
├── item_key: String?
├── hint: String?              // action, list, action_list
└── image_key: String?
```

### Service (`RoonService.swift`)

Classe `@MainActor ObservableObject` qui gere :

- **Connexion WebSocket** : connect/disconnect, boucle de reception async, reconnexion automatique avec backoff exponentiel
- **Etat publie** (`@Published`) :
  - `connectionState` — etat de la connexion au backend
  - `zones` — liste de toutes les zones
  - `currentZone` — zone selectionnee (mise a jour en temps reel)
  - `queueItems` — file d'attente de la zone courante
  - `browseResult` / `browseStack` — etat de navigation bibliotheque
  - `lastError` — derniere erreur
- **Actions** : play, pause, next, previous, seek, volume, mute, shuffle, loop, radio, browse, queue

#### Flux de donnees

```
WebSocket message (JSON)
    → handleMessage() decode le type
        → met a jour les @Published
            → SwiftUI re-render les vues concernees
```

### Vues

| Vue | Role |
|-----|------|
| `RoonControllerApp` | Point d'entree, cree `RoonService`, lance la connexion |
| `ContentView` | Routage : `ConnectionView` si deconnecte, sinon `NavigationSplitView` |
| `ConnectionView` | Ecran de connexion (status, IP manuelle, reconnexion) |
| `PlayerView` | Lecteur : pochette avec fond flou, infos piste, seek bar, controles transport, shuffle/repeat/radio |
| `SidebarView` | Barre laterale avec 3 onglets (picker segmente) : Zones, Bibliotheque, File d'attente |
| `QueueView` | Liste de la file d'attente, item en cours surbrille, tap pour jouer depuis un point |
| `SettingsView` | Preferences : hote/port backend, connexion manuelle Core |

#### Palette de couleurs (`RoonColors.swift`)

| Couleur | Hex | Usage |
|---------|-----|-------|
| `roonBackground` | #141414 | Fond principal |
| `roonSurface` | #1E1E1E | Surfaces elevees |
| `roonSidebar` | #1A1A1A | Fond barre laterale |
| `roonAccent` | #4285F4 | Accent (bleu Google) |
| `roonText` | #FFFFFF | Texte principal |
| `roonSecondary` | #AAAAAA | Texte secondaire |
| `roonTertiary` | #666666 | Texte tertiaire |

### Entitlements

- `com.apple.security.app-sandbox` : sandbox active
- `com.apple.security.network.client` : connexions sortantes (WS, HTTP)
- `com.apple.security.network.server` : connexions entrantes
