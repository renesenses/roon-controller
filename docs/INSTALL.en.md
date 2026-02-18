# Installation Guide

## Requirements to use the app

| Component | Minimum version |
|-----------|----------------|
| macOS | 12.0 (Monterey) or later — compatible with macOS 26.x (Tahoe) |
| Roon Core | 2.x |

> No external backend is needed. The app connects directly to the Roon Core via native SOOD and MOO protocols.

## Requirements to build from source

| Component | Minimum version |
|-----------|----------------|
| Xcode | 16.0 |

## 1. Install from DMG

Download the **RoonController.dmg** file from the [Releases page](https://github.com/renesenses/roon-controller/releases), then:

1. Open the DMG and drag **Roon Controller.app** into `/Applications`
2. **First launch** — the app is not code-signed (no Developer ID). macOS will block it. Two options:
   - **Option A (recommended)**: open Terminal and run:
     ```bash
     xattr -cr "/Applications/Roon Controller.app"
     ```
     Then launch the app normally.
   - **Option B**: double-click the app, macOS shows a block message. Go to **System Settings > Privacy & Security**, scroll down and click **Open Anyway**.
3. Authorize the extension in **Roon > Settings > Extensions**

> **Note**: on macOS Sequoia (15) and Tahoe (26), "right-click > Open" no longer works for unsigned applications. You must use `xattr -cr` or Privacy & Security.

## 2. Build with Xcode

```bash
cd "Roon client/RoonController"
open RoonController.xcodeproj
```

1. Select the **RoonController** target
2. Select **My Mac** as the destination
3. **Cmd+R** to build & run

### Command-line build

```bash
cd "Roon client/RoonController"
xcodebuild -scheme RoonController -configuration Debug build
```

## 3. Authorization in Roon

On first launch, the extension appears in **Roon > Settings > Extensions** as "Roon Controller macOS". Click **Authorize** to enable pairing.

The authorization token is saved in `UserDefaults` and persists across restarts. The extension is re-authorized automatically on subsequent launches.

## 4. Network topology

```
+--------------------+
|    Mac (dev)        |
|                     |      local network        +--------------+
|  +---------------+  |                            |              |
|  |  macOS App   |---+-- SOOD (239.255.90.90) ---|  Roon Core   |
|  |  (SwiftUI)   |---+-- WebSocket :9330 --------|  (server)    |
|  +---------------+  |                            |              |
|                     |                            +--------------+
+---------------------+
```

The app and the Roon Core must be on the same local network for SOOD discovery to work. If the Core is on a different subnet, use manual IP connection.

## 5. Manual connection

If automatic discovery fails:

1. Launch the app
2. Open **Roon Controller > Settings** (Cmd+,)
3. Enter the Roon Core's IP address
4. Click "Connect to this Core"

## 6. Roon Bridge (audio output)

To use a DAC connected to the Mac as a Roon audio output (zone endpoint), install **Roon Bridge**. It's a free app that runs in the background and exposes the Mac's audio devices to the Roon Core, independently from Roon.app.

### Installation

```bash
# Download
curl -L -o ~/Downloads/RoonBridge.dmg https://download.roonlabs.net/builds/RoonBridge.dmg

# Mount and copy
hdiutil attach ~/Downloads/RoonBridge.dmg
cp -R "/Volumes/RoonBridge/RoonBridge.app" /Applications/
hdiutil detach /Volumes/RoonBridge
```

### Launch

```bash
open /Applications/RoonBridge.app
```

Roon Bridge is a headless app — it runs in the background. The DAC connected to the Mac appears as an available zone in the Roon Core.

### Auto-start at login

Add RoonBridge to login items: **System Settings > General > Login Items** or via the command line:

```bash
osascript -e 'tell application "System Events" to make login item at end with properties {path:"/Applications/RoonBridge.app", hidden:true}'
```

### Roon.app vs Roon Bridge

| | Roon.app | Roon Bridge |
|---|---|---|
| GUI | Yes (full app) | No (daemon) |
| Exposes DACs to Core | Yes | Yes |
| Size | ~500 MB | ~37 MB |
| Recommended usage | Not needed if using Roon Controller | Recommended as audio endpoint |

> With **Roon Controller + Roon Bridge**, you no longer need Roon.app on the Mac.

## Troubleshooting

For a complete list of known issues and solutions, see **[TROUBLESHOOTING.en.md](TROUBLESHOOTING.en.md)**.

Quick checks:

- **App can't find the Core**: check the local network and port 9330, or use manual IP connection
- **Extension doesn't appear in Roon**: wait 10-20 seconds, then check Roon > Settings > Extensions
- **Xcode build error**: check the macOS target, deployment target 15.0, Swift 6.0
