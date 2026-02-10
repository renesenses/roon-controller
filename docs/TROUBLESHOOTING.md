# Troubleshooting

## 1. Backend Node.js

### Le backend ne demarre pas

**Symptome** : `node server.js` ne produit aucune sortie ou plante immediatement.

**Solutions** :
- Verifiez que Node.js est installe : `node --version` (minimum 18.x)
- Verifiez que les dependances sont installees : `cd node-backend && npm install`
- Si l'erreur mentionne un module manquant : supprimez `node_modules` et relancez `npm install`

### Port 3333 deja utilise

**Symptome** : `Error: listen EADDRINUSE :::3333`

**Solutions** :
- Identifiez le processus qui occupe le port : `lsof -i :3333`
- Arretez-le : `kill <PID>`
- Ou utilisez un autre port : `PORT=4444 node server.js` (pensez a mettre a jour le port dans les Parametres de l'app)

### Le backend ne trouve pas le Core Roon

**Symptome** : Le backend affiche `[Roon] Starting discovery...` mais jamais `Core paired`.

**Solutions** :
- Verifiez que le Roon Core est allume et sur le meme reseau local
- Verifiez qu'aucun pare-feu ne bloque le port **9330** (protocole SOOD/Roon)
- Tentez une connexion manuelle depuis l'app : **Parametres > Adresse IP du Core** (ex: `192.168.1.29`)
- Si le Core est sur un sous-reseau different, la decouverte SOOD ne fonctionnera pas — utilisez la connexion manuelle
- Attendez 10 a 30 secondes : la decouverte peut prendre du temps au premier lancement

### L'extension n'apparait pas dans Roon

**Symptome** : Le backend tourne mais "Roon Controller macOS" n'est pas visible dans Roon > Parametres > Extensions.

**Solutions** :
- Attendez 10-20 secondes apres le demarrage du backend
- Redemarrez le backend
- Supprimez le fichier `node-backend/config/roon-state.json` pour forcer un nouveau pairing
- Relancez le backend et verifiez dans Roon > Parametres > Extensions
- Cliquez sur **Autoriser** pour activer l'extension

### Le backend se deconnecte du Core de maniere intermittente

**Symptome** : Les zones disparaissent puis reapparaissent, messages `core_unpaired` dans la console.

**Solutions** :
- Verifiez la stabilite de votre reseau local (Wi-Fi vs Ethernet)
- Connectez le backend en filaire si possible
- Le backend tente automatiquement de se reconnecter toutes les 5 secondes

---

## 2. App macOS

### L'app ne se connecte pas au backend

**Symptome** : L'app reste bloquee sur l'ecran de connexion "Deconnecte du backend".

**Solutions** :
- Verifiez que le backend est lance : `curl http://localhost:3333/api/status`
- Verifiez le host et le port dans **Parametres** (Cmd+,) — par defaut `localhost:3333`
- Si le backend est sur une autre machine, utilisez son adresse IP (ex: `192.168.1.10`)
- L'app reconnecte automatiquement avec un backoff exponentiel — attendez quelques secondes

### Le demarrage automatique du backend ne fonctionne pas

**Symptome** : L'app se lance mais le backend ne demarre pas automatiquement.

**Solutions** :
- Verifiez que Node.js est installe a l'un de ces emplacements :
  - `/opt/homebrew/bin/node` (Homebrew Apple Silicon)
  - `/usr/local/bin/node` (Homebrew Intel)
  - `/usr/bin/node`
- Verifiez le chemin du backend dans **Parametres > Dossier backend** — il doit pointer vers le dossier contenant `server.js`
- Si le champ est vide, l'app tente une detection automatique basee sur l'emplacement du bundle. Si ca echoue, renseignez le chemin manuellement (ex: `/Users/votrenom/DEV/Roon client/node-backend`)
- Verifiez que le fichier `server.js` existe dans le dossier indique

### Les zones n'apparaissent pas

**Symptome** : L'app est connectee au backend mais la liste des zones est vide.

**Solutions** :
- Verifiez que le backend est bien paire avec le Core Roon : `curl http://localhost:3333/api/status` doit afficher `"connected": true`
- Verifiez que des zones existent dans Roon (au moins un endpoint audio configure)
- Si vous venez de pairer l'extension, attendez quelques secondes pour que les zones soient transmises

### L'app ne repond plus / freeze

**Symptome** : L'interface se fige ou les controles ne reagissent plus.

**Solutions** :
- Fermez et relancez l'app
- Verifiez que le backend repond toujours (`curl http://localhost:3333/api/status`)
- Si le probleme persiste, redemarrez le backend

---

## 3. Lecture et controles

### Les boutons play/pause/next ne font rien

**Symptome** : Cliquer sur les controles de transport n'a aucun effet.

**Solutions** :
- Verifiez qu'une zone est selectionnee dans la sidebar (surlignee en bleu)
- Verifiez que la zone est dans un etat compatible : `is_play_allowed` / `is_pause_allowed` doivent etre `true`
- Certaines zones (arretees sans queue) ne supportent pas le play — lancez d'abord un morceau depuis la bibliotheque

### Le seek (barre de progression) ne fonctionne pas

**Symptome** : Cliquer sur la barre de progression ne change pas la position de lecture.

**Solutions** :
- Verifiez que `is_seek_allowed` est `true` pour la zone (certaines sources comme les radios ne supportent pas le seek)
- Les radios en streaming (FIP, Radio Classique...) n'ont pas de seek

### Le volume ne change pas

**Symptome** : Le slider de volume bouge mais le volume reel ne change pas.

**Solutions** :
- Verifiez que la zone a bien un output avec controle de volume (certains DAC n'exposent pas de volume a Roon)
- Le changement de volume est envoye a l'output specifique — verifiez que l'output_id est correct

### La file d'attente (queue) est vide

**Symptome** : L'onglet "File d'attente" affiche "File d'attente vide" alors qu'un morceau est en lecture.

**Solutions** :
- Changez de zone puis revenez — cela force une re-souscription a la queue
- La queue n'est envoyee qu'au client qui s'y est abonne — si la connexion WS a ete coupee et retablie, la souscription doit etre renouvelee
- Le backend limite la queue a 100 items

---

## 4. Bibliotheque (Browse)

### Cliquer sur un element ne fait rien

**Symptome** : Cliquer sur Albums, Artists, etc. dans la bibliotheque n'affiche rien.

**Solutions** :
- Verifiez que le backend tourne et repond (le message `browse/browse` est envoye via WebSocket)
- Si la bibliotheque est tres volumineuse (>10 000 items), le chargement peut prendre quelques secondes
- Essayez de revenir a l'accueil (icone maison) puis de re-naviguer
- Verifiez la console du backend pour des erreurs `Browse error`

### La recherche ne trouve pas de resultats

**Symptome** : Le champ de recherche local (en haut de la bibliotheque) ne filtre rien.

**Solutions** :
- La recherche locale filtre uniquement les elements deja charges. Si la liste est longue, les items supplementaires sont charges automatiquement en arriere-plan lors de la saisie
- Pour une recherche dans toute la bibliotheque Roon, utilisez l'item **Recherche** (avec l'icone loupe) en haut de la liste Library — un dialogue de recherche Roon s'ouvre

### Le defilement de la bibliotheque est lent

**Symptome** : La liste est longue et le scroll est saccade.

**Solutions** :
- Les elements sont charges par pages de 100. Le chargement de la page suivante se declenche automatiquement quand vous approchez de la fin de la liste
- Pour des bibliotheques tres volumineuses, utilisez la recherche pour reduire le nombre de resultats

---

## 5. Historique de lecture

### L'historique est vide

**Symptome** : L'onglet "Historique" n'affiche aucun morceau.

**Solutions** :
- L'historique ne se remplit qu'avec les morceaux joues pendant que l'app est ouverte
- L'historique ne suit que les zones en etat "playing" avec des informations de piste valides
- Les radios (FIP, etc.) sont aussi tracees si elles fournissent les metadonnees du morceau en cours

### Des doublons apparaissent dans l'historique

**Symptome** : Le meme morceau apparait plusieurs fois de suite.

**Solutions** :
- Un mecanisme de deduplication empeche les doublons consecutifs pour la meme zone
- Si le meme morceau est joue sur deux zones differentes, il apparaitra deux fois (comportement normal)
- Le bouton **Effacer** supprime tout l'historique

### Cliquer sur un morceau de l'historique ne le relance pas

**Symptome** : Rien ne se passe quand on clique sur un morceau de l'historique.

**Solutions** :
- Verifiez qu'une zone est selectionnee (la lecture se lance sur la zone courante)
- Le morceau est recherche dans la bibliotheque Roon par son titre — si le titre exact n'existe plus (morceau supprime, radio), la lecture ne pourra pas etre lancee
- Les morceaux de radio en direct ne peuvent pas etre rejoues (ils n'existent pas dans la bibliotheque)

---

## 6. Peripheriques audio

### Un DAC USB n'apparait pas comme zone

**Symptome** : Un DAC branche en USB sur le Mac n'est pas visible dans les zones Roon.

**Solutions** :
- Le DAC doit etre gere par **Roon** pour apparaitre comme zone. Deux options :
  1. Installer et lancer **Roon** (le client lourd) sur le Mac ou est branche le DAC — il devient alors un endpoint
  2. Installer **Roon Bridge** sur le Mac — il expose les sorties audio du Mac au Core Roon
- Verifiez que le DAC est reconnu par macOS : **Reglages Systeme > Son > Sortie**
- Dans Roon, allez dans **Parametres > Audio** pour activer la sortie correspondante

### Le volume d'un DAC USB n'est pas controlable

**Symptome** : Le slider de volume n'a pas d'effet sur un DAC USB.

**Solutions** :
- Certains DAC gerent le volume en interne et ne l'exposent pas a Roon
- Dans Roon, verifiez **Parametres > Audio > (votre DAC) > Volume Control Mode** :
  - "Device Volume" utilise le volume du DAC
  - "DSP Volume" utilise le traitement numerique de Roon (perte de qualite)
  - "Fixed Volume" desactive le controle de volume

---

## 7. Build et developpement

### Erreur de compilation Xcode

**Symptome** : `xcodebuild` echoue avec des erreurs Swift.

**Solutions** :
- Verifiez la version d'Xcode : minimum **16.0**
- Verifiez la target : **macOS** (pas iOS/iPadOS)
- Verifiez les settings : Deployment Target **macOS 15.0**, Swift **6.0**
- Si le projet est desynchronise, regenerez-le : `cd RoonController && xcodegen generate`

### Erreur `Unable to find module dependency: 'RoonController'` dans les tests

**Symptome** : Les tests ne compilent pas avec une erreur d'import.

**Solutions** :
- Le module s'appelle `Roon_Controller` (avec underscore) car le PRODUCT_NAME contient un espace ("Roon Controller")
- Les fichiers de test doivent utiliser : `@testable import Roon_Controller`
- Si vous regenerez le projet avec xcodegen, verifiez que `project.yml` contient bien la target `RoonControllerTests`

### Les tests echouent

**Symptome** : `xcodebuild test` rapporte des echecs.

**Solutions** :
- Lancez les tests : `xcodebuild test -project RoonController.xcodeproj -scheme RoonControllerTests -destination 'platform=macOS'`
- Les tests unitaires ne necessitent pas de backend en fonctionnement — ils testent les modeles et la logique du service en isolation
- Verifiez que vous n'avez pas modifie les structures de donnees (RoonModels) sans mettre a jour les tests

---

## 8. Problemes reseau

### L'app fonctionne en local mais pas a distance

**Symptome** : L'app se connecte quand le backend est sur la meme machine, mais pas depuis une autre machine.

**Solutions** :
- Le backend ecoute sur toutes les interfaces (port 3333 par defaut)
- Verifiez que le pare-feu macOS autorise les connexions entrantes sur le port 3333
- Dans l'app, remplacez `localhost` par l'adresse IP du Mac qui fait tourner le backend (ex: `192.168.1.10`)
- Verifiez que les deux machines sont sur le meme sous-reseau

### Les pochettes d'album ne s'affichent pas

**Symptome** : Les pochettes sont grises/vides dans l'app.

**Solutions** :
- Les pochettes sont servies par le proxy image du backend : `http://<host>:3333/api/image/<key>`
- Testez dans un navigateur : `http://localhost:3333/api/image/<une_image_key>` (l'image_key est visible dans les logs ou le JSON des zones)
- Verifiez que le backend est connecte au Core Roon (`"connected": true` dans `/api/status`)
- Les pochettes sont mises en cache cote navigateur/app (Cache-Control: 86400s). Un redemarrage de l'app peut etre necessaire si le Core a change

---

## Commandes de diagnostic utiles

```bash
# Verifier que le backend tourne
curl -s http://localhost:3333/api/status | python3 -m json.tool

# Verifier le port 3333
lsof -i :3333

# Voir les processus backend
pgrep -fl "node server.js"

# Arreter tous les backends
pkill -f "node server.js"

# Tester une image
curl -o /dev/null -w "%{http_code}" http://localhost:3333/api/image/test_key

# Lancer les tests Swift
cd RoonController && xcodebuild test -project RoonController.xcodeproj \
  -scheme RoonControllerTests -destination 'platform=macOS' 2>&1 | \
  grep -E "(Test Case|TEST)"

# Verifier la version de Node.js
node --version

# Reinstaller les dependances du backend
cd node-backend && rm -rf node_modules && npm install
```
