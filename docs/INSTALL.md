> **[English version](INSTALL.en.md)** | Francais

# Guide d'installation

## Prerequis

| Composant | Version minimale |
|-----------|-----------------|
| macOS | 15.0 (Sequoia) |
| Xcode | 16.0 |
| Roon Core | 2.x |

> Aucun backend externe n'est necessaire. L'app se connecte directement au Roon Core via les protocoles natifs SOOD et MOO.

## 1. Build avec Xcode

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

## 2. Autorisation dans Roon

Au premier lancement, l'extension apparait dans **Roon > Parametres > Extensions** comme "Roon Controller macOS". Cliquez sur **Autoriser** pour activer le pairing.

Le token d'autorisation est sauvegarde dans `UserDefaults` et persiste entre les redemarrages. L'extension est re-autorisee automatiquement aux lancements suivants.

## 3. Topologie reseau

```
┌──────────────────┐
│    Mac (dev)      │
│                   │      reseau local        ┌──────────────┐
│  ┌─────────────┐  │                          │              │
│  │  App macOS  │──┼── SOOD (239.255.90.90) ──│  Roon Core   │
│  │  (SwiftUI)  │──┼── WebSocket :9330 ───────│  (serveur)   │
│  └─────────────┘  │                          │              │
│                   │                          └──────────────┘
└───────────────────┘
```

L'app et le Roon Core doivent etre sur le meme reseau local pour que la decouverte SOOD fonctionne. Si le Core est sur un sous-reseau different, utilisez la connexion manuelle par IP.

## 4. Connexion manuelle

Si la decouverte automatique echoue :

1. Lancez l'app
2. Ouvrez **Roon Controller > Parametres** (Cmd+,)
3. Entrez l'adresse IP du Roon Core
4. Cliquez "Connecter a ce Core"

## 5. Roon Bridge (sortie audio)

Pour utiliser un DAC connecte au Mac comme sortie audio Roon (zone endpoint), installez **Roon Bridge**. C'est une app gratuite qui tourne en arriere-plan et expose les peripheriques audio du Mac au Roon Core, independamment de Roon.app.

### Installation

```bash
# Telecharger
curl -L -o ~/Downloads/RoonBridge.dmg https://download.roonlabs.net/builds/RoonBridge.dmg

# Monter et copier
hdiutil attach ~/Downloads/RoonBridge.dmg
cp -R "/Volumes/RoonBridge/RoonBridge.app" /Applications/
hdiutil detach /Volumes/RoonBridge
```

### Lancement

```bash
open /Applications/RoonBridge.app
```

Roon Bridge est une app sans interface visible — elle tourne en arriere-plan. Le DAC connecte au Mac apparait comme zone disponible dans le Roon Core.

### Lancement automatique au demarrage

Ajoutez RoonBridge aux elements d'ouverture : **Reglages Systeme > General > Ouverture** ou via la ligne de commande :

```bash
osascript -e 'tell application "System Events" to make login item at end with properties {path:"/Applications/RoonBridge.app", hidden:true}'
```

### Roon.app vs Roon Bridge

| | Roon.app | Roon Bridge |
|---|---|---|
| Interface graphique | Oui (app complete) | Non (daemon) |
| Expose les DAC au Core | Oui | Oui |
| Taille | ~500 Mo | ~37 Mo |
| Usage recommande | Non necessaire si vous utilisez Roon Controller | Recommande comme endpoint audio |

> Avec **Roon Controller + Roon Bridge**, vous n'avez plus besoin de Roon.app sur le Mac.

## Depannage

Pour une liste complete des problemes connus et solutions, consultez **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)**.

Quelques verifications rapides :

- **L'app ne trouve pas le Core** : verifiez le reseau local et le port 9330, ou utilisez la connexion manuelle par IP
- **L'extension n'apparait pas dans Roon** : attendez 10-20 secondes, puis verifiez dans Roon > Parametres > Extensions
- **Erreur de build Xcode** : verifiez la target macOS, deployment target 15.0, Swift 6.0
