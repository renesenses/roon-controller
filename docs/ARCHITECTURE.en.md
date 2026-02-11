# Technical Architecture

## Overview

```
+----------------------------+     SOOD (UDP multicast)     +--------------+
|    macOS App (Swift)       |  ---------------------------> |  Roon Core   |
|    SwiftUI - native        |                               |  (server)    |
|                            |  <------------------------->  |              |
|  SOOD - MOO/1 - WS        |     WebSocket (MOO/1)         |  port 9330   |
+----------------------------+                               +--------------+

+----------------------------+         RAAT (audio)         +--------------+
|    Roon Bridge (daemon)    |  <--------------------------  |  Roon Core   |
|    exposes DAC/audio       |                               |              |
+----------------------------+                               +--------------+
```

The app connects directly to the Roon Core with no intermediary. It natively implements the Roon protocols in Swift.
**Roon Bridge** (separate app) exposes the Mac's audio outputs (USB DAC, etc.) to the Core via the RAAT protocol:

1. **SOOD** — Core discovery via UDP multicast
2. **MOO/1** — Binary messaging protocol over WebSocket
3. **Registry** — Extension registration handshake

## Protocol Stack

```
+---------------------------------+
|         RoonService             |  @MainActor ObservableObject
|    (UI/logic orchestrator)      |
+---------------------------------+
|        RoonConnection           |  Actor — full lifecycle
|  discovery -> WS -> registration |  -> message routing
+----------+----------+-----------+
|   SOOD   |   MOO    |  Registry |
| Discovery| Transport| Registration|
| (UDP)    | (WS)     | (handshake)|
+----------+----------+-----------+
```

## SOOD Protocol (Discovery)

### Format

SOOD uses UDP multicast on `239.255.90.90:9003` with a proprietary binary format:

```
+------+---------+------+----------------+
| SOOD | version | type |  properties... |
| 4B   |  1B     | 1B   |  variable      |
+------+---------+------+----------------+
```

- **Magic**: `0x53 0x4F 0x4F 0x44` ("SOOD")
- **Version**: `0x02`
- **Type**: `0x51` (Query) or `0x52` (Reply)

### Properties

Each property is encoded as:

```
key_length (1 byte) + key + value_length (2 bytes BE) + value
```

- `0xFFFF` for value_length = null sentinel
- `0x0000` for value_length = empty string

### Query

The app periodically sends (every 5s) a Query packet containing:

| Property | Value |
|----------|-------|
| `_tid` | Unique UUID per request |
| `query_service_id` | `00720724-5143-4a9b-abac-0e50cba674bb` |

The query is sent both as multicast (`239.255.90.90`) and broadcast on each network interface.

### Reply

The Core responds with a Reply packet containing:

| Property | Description |
|----------|-------------|
| `service_id` | Unique Core identifier |
| `display_name` | Core display name |
| `http_port` | WebSocket port (usually `9330`) |
| `_replyaddr` | Core IP address (optional) |

### Implementation (`SOODDiscovery.swift`)

- Uses POSIX (BSD) sockets instead of Network.framework to avoid needing the `com.apple.developer.networking.multicast` entitlement
- Send socket: `SOCK_DGRAM` with `SO_BROADCAST` and `IP_MULTICAST_TTL=1`
- Receive socket: bind on port 9003 with `SO_REUSEADDR`/`SO_REUSEPORT`, join multicast on all interfaces
- Also listens for unicast replies on the send socket (ephemeral port)

## MOO/1 Protocol (Messaging)

### Format

MOO/1 messages are sent as binary WebSocket frames:

```
MOO/1 {VERB} {name}\n
Request-Id: {id}\n
Content-Type: application/json\n     (optional, if body present)
Content-Length: {length}\n           (optional, if body present)
\n
{JSON body}
```

### Verbs

| Verb | Direction | Description |
|------|-----------|-------------|
| `REQUEST` | bidirectional | Request (app -> Core or Core -> app) |
| `COMPLETE` | response | Final response to a request |
| `CONTINUE` | response | Partial response / subscription notification |

### Request/Response Cycle

```
App                                    Core
 |                                      |
 |  REQUEST com.roonlabs.registry:1/info|
 | ----------------------------------->|
 |                                      |
 |  COMPLETE Success                    |
 | <-----------------------------------|
 |                                      |
 |  REQUEST .../subscribe_zones         |
 | ----------------------------------->|
 |                                      |
 |  CONTINUE Subscribed (zones data)    |
 | <-----------------------------------|  (repeats on each change)
 |                                      |
 |  REQUEST com.roonlabs.ping:1/ping    |
 | <-----------------------------------|  (Core keepalive)
 |                                      |
 |  COMPLETE Success                    |
 | ----------------------------------->|
```

### Implementation (`MOOMessage.swift`, `MOOTransport.swift`)

- `MOOMessage`: binary message construction and parsing
- `MOOTransport`: actor managing the WebSocket (`URLSessionWebSocketTask`), ping/pong keepalive every 10s, async receive loop
- `MOORequestIdGenerator`: atomic request ID generator (thread-safe with `NSLock`)

## Registration (Registry)

### Handshake

1. **`registry:1/info`** -> receives Core info and available service names
2. **`registry:1/register`** -> sends extension info + saved token
3. The Core responds `Registered` (with token) or waits for user authorization

### Registration Payload

```json
{
    "extension_id": "com.bertrand.rooncontroller",
    "display_name": "Roon Controller macOS",
    "display_version": "1.0.0",
    "publisher": "Bertrand",
    "required_services": [
        "com.roonlabs.transport:2",
        "com.roonlabs.browse:1",
        "com.roonlabs.image:1"
    ],
    "optional_services": [],
    "provided_services": [
        "com.roonlabs.ping:1",
        "com.roonlabs.status:1"
    ],
    "token": "..."
}
```

### Token Persistence

The authorization token is saved in `UserDefaults` (`roon_core_token`). On restart, the extension is re-authorized automatically without user intervention.

## RoonConnection (Orchestrator)

### States

```
disconnected -> discovering -> connecting -> registering -> connected
                                                              |
                                                         disconnected
                                                              |
                                                       (scheduleReconnect)
```

### Responsibilities

| Function | Description |
|----------|-------------|
| `connect()` | Starts SOOD discovery |
| `connectDirect(host:port:)` | Manual IP connection |
| `disconnect()` | Clean disconnection |
| `performRegistration()` | Handshake registry:1/info + registry:1/register |
| `handleMessage()` | Incoming message routing (responses, subscriptions, Core requests) |
| `subscribeZones()` | Subscribe to zone updates |
| `subscribeQueue(zoneId:)` | Subscribe to a zone's queue |
| `sendRequestData(name:bodyData:)` | Send a request with async continuation (10s timeout) |

### Reconnection

- Exponential backoff: delay = `min(2^attempt, 30)` seconds
- If host/port are known: direct reconnection
- Otherwise: restart SOOD discovery

## Roon Services

### RoonTransportService

Transport control via `com.roonlabs.transport:2`:

| Method | Endpoint | Description |
|--------|----------|-------------|
| `control()` | `/control` | play, pause, playpause, stop, previous, next |
| `seek()` | `/seek` | absolute or relative |
| `changeVolume()` | `/change_volume` | absolute, relative, relative_step |
| `mute()` | `/mute` | mute, unmute, toggle |
| `changeSettings()` | `/change_settings` | shuffle, loop, auto_radio |
| `playFromHere()` | `/play_from_here` | Play from a queue item |
| `subscribeQueue()` | via `RoonConnection` | Subscribe to a zone's queue |

### RoonBrowseService

Library navigation via `com.roonlabs.browse:1`:

| Method | Endpoint | Description |
|--------|----------|-------------|
| `browse()` | `/browse` | Navigate, search, execute actions |
| `load()` | `/load` | Load a results page (pagination) |

### RoonImageService

Artwork retrieval via `com.roonlabs.image:1`:

| Method | Endpoint | Description |
|--------|----------|-------------|
| `getImage()` | `/get_image` | Retrieve an image by key, size, and format |

Images are served locally via `LocalImageServer` (HTTP on port 9150) and cached by `RoonImageCache` (LRU).

## macOS App (SwiftUI)

### RoonService (`RoonService.swift`)

`@MainActor ObservableObject` class that orchestrates everything:

- **Connection**: creates `RoonConnection` and services (transport, browse, image)
- **Published state** (`@Published`):
  - `connectionState` — connection state to the Core
  - `zones` — list of all zones
  - `currentZone` — selected zone (updated in real time)
  - `queueItems` — current zone's queue
  - `browseResult` / `browseStack` — library browse state
  - `playbackHistory` — playback history (persistent)
  - `lastError` — last error
- **Actions**: play, pause, next, previous, seek, volume, mute, shuffle, loop, radio, browse, queue

### History Replay

History replay distinguishes two cases:

**Tracks**: `searchAndPlay()` performs a text search (album then title) via the Browse API and plays the first matching result.

**Live radio**: detected by `zone.is_seek_allowed == false` when recording to history (`isRadio` field). On replay, `playRadioStation()` navigates the `internet_radio` Browse API hierarchy, finds the station by name (in `album` or `title` depending on available metadata), and navigates the action menu to start playback.

```
History -> searchAndPlay(isRadio: true)
              -> playRadioStation()
                  -> browse(hierarchy: "internet_radio", popAll: true)
                  -> match station by name
                  -> playBrowseItem(hierarchy: "internet_radio")
                      -> select the "Play" action
```

### Data Flow

```
Roon Core (WebSocket MOO/1)
    -> RoonConnection (message routing)
        -> RoonService callbacks (Data)
            -> decode JSON, update @Published
                -> SwiftUI re-renders views
```

### Models (`RoonModels.swift`)

```
RoonZone
+-- zone_id: String
+-- display_name: String
+-- state: String?              // playing, paused, loading, stopped
+-- now_playing: NowPlaying?
+-- outputs: [RoonOutput]?
+-- settings: ZoneSettings?
+-- seek_position: Int?
+-- is_play/pause/seek/previous/next_allowed: Bool?

NowPlaying
+-- one_line / two_line / three_line: LineInfo?
+-- length: Int?
+-- seek_position: Int?
+-- image_key: String?

QueueItem
+-- queue_item_id: Int
+-- one_line / two_line / three_line: LineInfo?
+-- length: Int?
+-- image_key: String?

RoonOutput
+-- output_id: String
+-- display_name: String
+-- zone_id: String?
+-- volume: VolumeInfo?

BrowseItem
+-- title / subtitle: String?
+-- item_key: String?
+-- hint: String?              // action, list, action_list
+-- image_key: String?
+-- input_prompt: InputPrompt?
```

### Views

| View | Role |
|------|------|
| `RoonControllerApp` | Entry point, creates `RoonService`, starts connection |
| `ContentView` | Routing: `ConnectionView` if disconnected, otherwise `NavigationSplitView` |
| `ConnectionView` | Connection screen (status, reconnection) |
| `PlayerView` | Player: artwork with blurred background, track info, seek bar, transport controls, shuffle/repeat/radio |
| `SidebarView` | Sidebar with 4 tabs: Zones, Library, Queue, History |
| `QueueView` | Queue list, current item highlighted, tap to play from a point |
| `HistoryView` | Playback history with artwork, title, artist, zone, time. Tap to replay (tracks and radio) |
| `SettingsView` | Manual Core connection by IP |

### Color Palette (`RoonColors.swift`)

| Color | Hex | Usage |
|-------|-----|-------|
| `roonBackground` | #141414 | Main background |
| `roonSurface` | #1E1E1E | Elevated surfaces |
| `roonSidebar` | #1A1A1A | Sidebar background |
| `roonAccent` | #4285F4 | Accent (Google blue) |
| `roonText` | #FFFFFF | Primary text |
| `roonSecondary` | #AAAAAA | Secondary text |
| `roonTertiary` | #666666 | Tertiary text |

### Entitlements

- `com.apple.security.app-sandbox`: disabled
- `com.apple.security.network.client`: outgoing connections (WebSocket, HTTP)
- `com.apple.security.network.server`: incoming connections (local image server)
