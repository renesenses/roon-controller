---
marp: true
theme: default
paginate: true
backgroundColor: #141414
color: #e0e0e0
style: |
  section {
    font-family: -apple-system, BlinkMacSystemFont, 'SF Pro', sans-serif;
  }
  h1, h2 {
    color: #4285F4;
  }
  h3 {
    color: #ffffff;
  }
  code {
    background: #1e1e1e;
    color: #d4d4d4;
  }
  pre {
    background: #1e1e1e !important;
    border-radius: 8px;
  }
  table {
    color: #e0e0e0;
    font-size: 0.85em;
  }
  th {
    background: #1a3a6a;
    color: #ffffff;
  }
  td {
    background: #1a1a1a;
  }
  a {
    color: #4285F4;
  }
  strong {
    color: #ffffff;
  }
  blockquote {
    border-left-color: #4285F4;
    color: #a0a0a0;
  }
---

# Roon Controller

### D'un prototype Node.js a une app macOS native

Reimplementation de protocoles proprietaires en Swift 6

---

## Le besoin

### Roon = serveur audio audiophile

- Bibliotheque musicale, streaming (Tidal, Qobuz), pilotage DAC
- Architecture **Core** (serveur) + **Clients** (telecommandes)

### Le probleme

- Client officiel macOS = **Electron** (~500 Mo, 300+ Mo RAM, lent)
- Pas de client natif macOS

### L'objectif

- Controleur **SwiftUI natif**, leger, rapide
- Zero dependances externes
- Protocoles non documentes → **reverse-engineering**

---

## Architecture v1 : Node.js + SwiftUI

```
┌─────────────┐   WebSocket   ┌──────────────┐   MOO/1   ┌───────────┐
│  SwiftUI    │◄────────────►│  Node.js     │◄────────►│ Roon Core │
│  App        │  :3000       │  Backend     │  :9330   │           │
└─────────────┘              └──────────────┘          └───────────┘
                                    │
                              5 packages npm
                              node-roon-api
```

### Avantages
- Prototypage rapide avec le SDK officiel
- Toutes les features implementees en quelques heures

### Limitations
- Double processus (Node + App)
- Latence ajoutee, point de defaillance unique
- Deploiement complexe, pas distribuable

---

## Architecture v2 : Swift natif

```
┌──────────────────────────────────────────────┐
│              RoonController.app                │
│                                                │
│  SwiftUI ◄──► RoonService ◄──► Protocol Layer │
│  Views        @MainActor       (actors)       │
│                    │                           │
│            ┌───────┴────────┐                 │
│            │                │                 │
│     SOODDiscovery    MOOTransport             │
│     (UDP POSIX)      (WebSocket)              │
└────────────┼────────────────┼─────────────────┘
             │                │
        UDP multicast    WebSocket TCP
       239.255.90.90     ws://core:9330
             │                │
        ┌────┴────────────────┴────┐
        │        Roon Core          │
        └──────────────────────────┘
```

**Un seul processus. Zero dependances. ~5 Mo.**

---

## v1 vs v2

| Aspect | v1 (Node.js) | v2 (Swift natif) |
|--------|-------------|-----------------|
| Processus | 2 | **1** |
| Dependances | 5 npm | **0** |
| Latence | App → Node → Core | **App → Core** |
| Deploiement | Node.js requis | **Juste l'app** |
| Taille | ~100 Mo | **~5 Mo** |
| App Store | Impossible | **Possible** |

---

## Protocole SOOD : decouverte

### UDP multicast sur `239.255.90.90:9003`

```
Paquet SOOD (binaire) :
┌──────┬─────────┬──────┬─────────────────────────┐
│ SOOD │ Version │ Type │ Proprietes              │
│ 4B   │ 0x02    │ Q/R  │ key_len(1B) key          │
│      │         │      │ val_len(2B BE) value     │
└──────┴─────────┴──────┴─────────────────────────┘
```

### Flux de decouverte

```
App                              Core
 │                                │
 │── Query (multicast) ─────────►│
 │   query_service_id + _tid     │
 │                                │
 │◄─ Reply (unicast) ───────────│
 │   name, http_port, tid        │
```

> Non documente — reverse-engineer a partir de `node-roon-api`

---

## Protocole MOO/1 : communication

### WebSocket binaire sur `ws://core:9330/api`

```
MOO/1 {VERB} {service:version/method}
Request-Id: {id}
Content-Type: application/json

{JSON body}
```

### 3 verbes

| Verbe | Usage |
|-------|-------|
| **REQUEST** | Envoyer une requete (bidirectionnel) |
| **COMPLETE** | Reponse finale |
| **CONTINUE** | Reponse streaming (subscriptions) |

---

## Flux MOO/1 : enregistrement + controle

```
App                                     Core
 │                                       │
 │─── REQUEST registry:1/info ─────────►│
 │◄── COMPLETE {services} ─────────────│
 │                                       │
 │─── REQUEST registry:1/register ────►│
 │◄── CONTINUE {token} ───────────────│  ← persiste
 │                                       │
 │─── REQUEST transport:2/subscribe ──►│
 │◄── CONTINUE {zones} ───────────────│  ← etat initial
 │◄── CONTINUE {zones_changed} ───────│  ← temps reel
 │                                       │
 │─── REQUEST transport:2/play_pause ─►│
 │◄── COMPLETE (200) ─────────────────│
```

---

## Probleme 1 : Network.framework

### Entitlement multicast

- `NWConnection` UDP multicast → necessite `com.apple.developer.networking.multicast`
- Requiert demande formelle a Apple + compte Developer payant

### Solution : POSIX sockets

```swift
// Sockets BSD — pas besoin d'entitlement
let fd = socket(AF_INET, SOCK_DGRAM, 0)

var mreq = ip_mreq()
mreq.imr_multiaddr.s_addr = inet_addr("239.255.90.90")
mreq.imr_interface.s_addr = inet_addr(iface.address)
setsockopt(fd, IPPROTO_IP, IP_ADD_MEMBERSHIP,
           &mreq, socklen_t(MemoryLayout.size(ofValue: mreq)))
```

---

## Probleme 2 : paquets SOOD ignores

### Encodage Big Endian

Les longueurs de valeurs doivent etre en **Big Endian**, pas Little Endian :

```swift
// ✗ Avant (LE) — Core ignore les paquets
data.append(contentsOf: withUnsafeBytes(of: UInt16(count)) { ... })

// ✓ Apres (BE) — fonctionne
data.append(contentsOf: withUnsafeBytes(of: UInt16(count).bigEndian) { ... })
```

> Subtil : les cles courtes (< 256) ont le meme encodage en LE et BE

---

## Probleme 3 : reponses unicast

### Le Core repond en unicast, pas multicast

```
App (port 9003)  ──Query──►  Core
App (port 9003)  ◄── ???     Core repond sur port SOURCE du query
```

Le query est envoye depuis un port **ephemere** (ex. 52341), pas depuis 9003.

### Solution : dual-socket

```swift
// Ecouter sur DEUX sockets en parallele
startReceiveLoop(on: recvFd, label: "multicast")  // port 9003
startReceiveLoop(on: sendFd, label: "unicast")     // port ephemere
```

---

## Probleme 4 : enregistrement MOO

### Noms de services dynamiques

```swift
// ✗ Noms codes en dur
"com.roonlabs.transport:2"

// ✓ Extraits de registry:1/info
let services = infoResponse["services"] // → noms reels
```

Les noms de services (`transport`, `browse`, `image`) sont decouverts dynamiquement a l'enregistrement — ils peuvent varier selon la version du Core.

---

## Probleme 5 : Swift 6 strict concurrency

### Tout doit etre `Sendable`

| Pattern | Utilisation |
|---------|------------|
| `actor` | SOODDiscovery, MOOTransport, RoonConnection |
| `@MainActor` | RoonService (bridge UI) |
| `@Sendable` closures | Callbacks entre actors |
| `@unchecked Sendable` | Wrappers `[String: Any]` |
| Passage de `Data` | Callbacks passent du `Data` brut |
| `NSLock` | Generateur atomique d'IDs |

```swift
// Callback Sendable qui passe du Data brut
var onZonesData: (@Sendable (Data) -> Void)?
```

---

## Architecture Swift 6

### Pile protocolaire

```
┌───────────────────────────────────┐
│         SwiftUI Views             │  @MainActor
├───────────────────────────────────┤
│        RoonService                │  @MainActor, ObservableObject
│   @Published zones, queue, ...    │  Bridge actors ↔ UI
├───────────┬───────┬───────┬───────┤
│ Transport │Browse │ Image │Status │  Services metier
├───────────┴───────┴───────┴───────┤
│      RoonConnection (actor)       │  Lifecycle + routing
├─────────────┬─────────────────────┤
│SOODDiscovery│    MOOTransport     │  Protocoles reseau
│(POSIX UDP)  │    (WebSocket)      │
├─────────────┴─────────────────────┤
│     Darwin / Foundation           │  Systeme
└───────────────────────────────────┘
```

---

## Pattern cle : async/await + Continuation

```swift
// Transformer un callback WebSocket en appel async
func sendRequest(name: String, body: Data?) async throws -> MOOMessage {
    let id = idGenerator.next()
    return try await withCheckedThrowingContinuation { cont in
        pendingRequests[id] = cont
        Task { try await transport.send(data) }

        // Timeout 30s
        Task {
            try await Task.sleep(nanoseconds: 30_000_000_000)
            if let c = pendingRequests.removeValue(forKey: id) {
                c.resume(throwing: MOOTransportError.timeout)
            }
        }
    }
}
```

---

## Reconnexion : backoff exponentiel

```swift
// Delai : 1s, 2s, 4s, 8s, 16s, 30s, 30s, 30s...
let delay = min(pow(2.0, Double(reconnectAttempt)), 30.0)

Task {
    try await Task.sleep(nanoseconds: UInt64(delay * 1e9))
    if shouldReconnect { await connect() }
}
```

- Detection automatique de deconnexion (erreur WebSocket)
- Reset du compteur a la reconnexion reussie
- `shouldReconnect` = false quand deconnexion volontaire

---

## Tests : 36 tests unitaires

### 3 niveaux de couverture

| Niveau | Tests | Exemples |
|--------|-------|----------|
| **Modeles** | 15 | Decodage JSON, Equatable, dates ISO 8601 |
| **Services** | 13 | Anti-doublon browse, historique, navigation |
| **Protocole** | 8 | Parsing MOO/1, construction, round-trip, atomicite IDs |

```bash
xcodebuild test \
  -scheme RoonControllerTests \
  -destination 'platform=macOS'
# ✓ 36 tests passed
```

---

## CI/CD : GitHub Actions

### 3 workflows

**CI** (`ci.yml`) — build + test :
- Push main, PRs, **cron hebdomadaire** (lundi 8h)
- Runner `macos-15` (Sequoia)

**Claude Code** (`claude.yml`) — revue IA :
- Chaque PR, mentions `@claude`
- Focus : Swift best practices, thread safety

**Version Watch** (`version-watch.yml`) — veille :
- Cron hebdo (lundi 9h, apres CI)
- Detecte changements macOS, Xcode, Swift, Roon
- Ouvre une issue GitHub si nouvelle version

```
Lundi 08:00  CI build + tests (regressions Xcode)
Lundi 09:00  Version Watch (macOS, Xcode, Swift, Roon)
       PR →  Claude Code (revue IA automatique)
```

---

## Chiffres cles

| Metrique | Valeur |
|----------|--------|
| **Lignes Swift** | ~4 500 |
| **Fichiers Swift** | 25 |
| **Tests** | 36 |
| **Dependances** | **0** |
| **Commits** | 26 |
| **Actors** | 4 |
| **Taille app** | ~5 Mo |
| **Workflows CI** | 3 |

### 4 phases de developpement

```
Phase 1        Phase 2         Phase 3          Phase 4
Prototype      Natif           Stabilisation    CI/CD
───────────    ───────────     ───────────      ───────────
Node.js +      Rewrite         Fix SOOD         GitHub
SwiftUI        SOOD/MOO        Fix MOO          Actions +
5 npm deps     en Swift        POSIX sockets    Claude Code
```

---

## Ce qui a ete construit

- **SOOD natif** — UDP multicast, POSIX sockets, multi-interface, dual-socket
- **MOO/1 natif** — WebSocket binaire, 3 verbes, subscriptions
- **Enregistrement** — handshake complet, persistance token
- **Transport** — play, pause, next, prev, seek, shuffle, repeat
- **Browse** — navigation hierarchique, recherche, pagination
- **Queue** — temps reel, play-from-here
- **Historique** — tracking, deduplication, persistance JSON
- **Images** — serveur HTTP local, cache LRU, chargement async
- **Reconnexion** — backoff exponentiel, detection deconnexion

---

## Conclusion

### Un client Roon complet et natif

- **Protocoles proprietaires** reimplementes par reverse-engineering
- **Zero dependances** — Swift pur, pas de runtime externe
- **Swift 6 actors** — thread-safety garantie a la compilation
- **CI/CD** avec revue IA automatique

### Le passage Node.js → Swift natif a elimine :

- Un processus externe
- 5 dependances npm
- Une couche de latence
- La complexite de deploiement

> Un seul binaire macOS natif. Rien d'autre.
