# Guide d'installation

## Prerequis

| Composant | Version minimale |
|-----------|-----------------|
| macOS | 15.0 (Sequoia) |
| Xcode | 16.0 |
| Node.js | 18.x |
| npm | 9.x |
| Roon Core | 2.x |

## 1. Backend Node.js

### Installation

```bash
cd "Roon client/node-backend"
npm install
```

Les dependances installees :
- `node-roon-api` — API Roon principale (decouverte, pairing)
- `node-roon-api-transport` — Controle transport (play, pause, seek, queue...)
- `node-roon-api-browse` — Navigation bibliotheque
- `node-roon-api-image` — Proxy images (pochettes)
- `node-roon-api-status` — Status de l'extension
- `express` — Serveur HTTP (proxy image)
- `ws` — Serveur WebSocket

### Lancement

```bash
node server.js
```

Sortie attendue :
```
[Server] HTTP + WebSocket listening on port 3333
[Server] Image proxy: http://localhost:3333/api/image/:key
[Server] Status:      http://localhost:3333/api/status
[Server] WebSocket:   ws://localhost:3333

[Roon] Starting discovery...
```

### Configuration du port

Par defaut, le serveur ecoute sur le port **3333**. Pour changer :

```bash
PORT=4444 node server.js
```

### Autorisation dans Roon

Au premier lancement, l'extension apparait dans **Roon > Parametres > Extensions** comme "Roon Controller macOS". Cliquez sur **Autoriser** pour activer le pairing.

L'etat de pairing est sauvegarde dans `node-backend/config/roon-state.json` et persiste entre les redemarrages.

### Verification

Ouvrez dans un navigateur :

```
http://localhost:3333/api/status
```

Reponse attendue (une fois paire) :
```json
{
  "connected": true,
  "core_name": "NomDeVotreCore",
  "core_version": "2.x.x",
  "zone_count": 3,
  "zones": [...],
  "version": "1.0.0"
}
```

## 2. App macOS (Swift)

### Build avec Xcode

```bash
cd "Roon client/RoonController"
open RoonController.xcodeproj
```

1. Selectionnez la target **RoonController**
2. Selectionnez **My Mac** comme destination
3. **Cmd+R** pour build & run

### Build en ligne de commande

```bash
cd "Roon client/RoonController"
xcodebuild -scheme RoonController -configuration Debug build
```

### Configuration du backend

Par defaut, l'app se connecte a `ws://localhost:3333`. Pour modifier :

1. Lancez l'app
2. Allez dans **Roon Controller > Parametres** (ou Cmd+,)
3. Modifiez l'hote et/ou le port
4. Cliquez "Appliquer et reconnecter"

Les parametres sont stockes dans `UserDefaults` (`backendHost`, `backendPort`).

## 3. Topologie reseau

```
┌──────────────────┐
│    Mac (dev)     │
│                  │
│  ┌────────────┐  │       reseau local       ┌──────────────┐
│  │ App macOS  │──┼──── ws://localhost:3333 ──│              │
│  └────────────┘  │                           │  Backend     │
│                  │                           │  Node.js     │──── SOOD/TCP ──── Roon Core
│  ou bien :       │                           │  (port 3333) │
│  ┌────────────┐  │                           └──────────────┘
│  │ App macOS  │──┼── ws://192.168.x.x:3333 ─────────┘
│  └────────────┘  │
└──────────────────┘
```

L'app et le backend peuvent tourner sur la meme machine ou sur des machines differentes du reseau local. Le backend doit pouvoir joindre le Roon Core via le reseau.

## Depannage

### Le backend ne trouve pas le Core

- Verifiez que le Roon Core est allume et sur le meme reseau
- Utilisez la connexion manuelle par IP dans l'app (ecran de connexion ou Parametres)
- Verifiez qu'aucun pare-feu ne bloque le port 9330 (Roon) ou 3333 (backend)

### L'app ne se connecte pas au backend

- Verifiez que le backend est lance (`node server.js`)
- Verifiez le port dans Parametres (par defaut : 3333)
- Verifiez la sortie console de l'app pour les messages `[WS]`

### L'extension n'apparait pas dans Roon

- Relancez le backend
- Verifiez `config/roon-state.json` — supprimez-le pour repartir de zero
- Attendez 10-20 secondes pour la decouverte SOOD

### Erreur de build Xcode

- Verifiez que la target est macOS (pas iOS)
- Deployment target : macOS 15.0
- Swift version : 6.0
