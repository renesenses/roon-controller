# Troubleshooting

## 1. Decouverte du Core (SOOD)

### L'app ne trouve pas le Roon Core

**Symptome** : L'app reste sur l'ecran de connexion, aucune zone n'apparait.

**Solutions** :
- Verifiez que le Roon Core est allume et sur le meme reseau local
- Verifiez qu'aucun pare-feu ne bloque le port UDP **9003** (protocole SOOD) et le port TCP **9330** (WebSocket Roon)
- La decouverte SOOD utilise le multicast UDP sur `239.255.90.90:9003` — certains routeurs bloquent le multicast entre VLANs
- Tentez une connexion manuelle : **Parametres** (Cmd+,) > entrez l'adresse IP du Core
- Attendez 10 a 30 secondes : la decouverte peut prendre du temps au premier lancement

### L'extension n'apparait pas dans Roon

**Symptome** : L'app tourne mais "Roon Controller macOS" n'est pas visible dans Roon > Parametres > Extensions.

**Solutions** :
- Attendez 10-20 secondes apres le demarrage de l'app
- Relancez l'app
- Verifiez la console systeme (Console.app) pour des messages `RoonController`
- L'extension doit etre autorisee dans **Roon > Parametres > Extensions** — cliquez sur **Autoriser**

### La connexion se coupe de maniere intermittente

**Symptome** : Les zones disparaissent puis reapparaissent periodiquement.

**Solutions** :
- Verifiez la stabilite de votre reseau local (Wi-Fi vs Ethernet)
- L'app reconnecte automatiquement avec un backoff exponentiel (jusqu'a 30s)
- Si le Core a change d'adresse IP, l'app relance la decouverte SOOD automatiquement

---

## 2. Enregistrement et autorisation

### L'app affiche "Connexion en cours" indefiniment

**Symptome** : L'app decouvre le Core mais ne passe jamais a l'etat "Connecte".

**Solutions** :
- Verifiez dans **Roon > Parametres > Extensions** si "Roon Controller macOS" attend une autorisation
- Cliquez sur **Autoriser** pour activer l'extension
- Si l'extension n'apparait pas du tout, consultez la section "L'extension n'apparait pas dans Roon" ci-dessus

### Re-autorisation apres mise a jour du Core

**Symptome** : L'app etait connectee mais ne se reconnecte plus apres une mise a jour du Core.

**Solutions** :
- Le token d'autorisation peut avoir ete invalide par la mise a jour
- L'app va automatiquement se re-enregistrer — verifiez dans Roon > Extensions si une nouvelle autorisation est requise
- Si le probleme persiste, effacez le token sauvegarde : dans Terminal, lancez `defaults delete com.bertrand.RoonController roon_core_token`

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
- Les radios en streaming n'ont pas de seek

### Le volume ne change pas

**Symptome** : Le slider de volume bouge mais le volume reel ne change pas.

**Solutions** :
- Verifiez que la zone a bien un output avec controle de volume (certains DAC n'exposent pas de volume a Roon)
- Le changement de volume est envoye a l'output specifique — verifiez que l'output_id est correct

### La file d'attente (queue) est vide

**Symptome** : L'onglet "File d'attente" affiche "File d'attente vide" alors qu'un morceau est en lecture.

**Solutions** :
- Changez de zone puis revenez — cela force une re-souscription a la queue
- Si la connexion WebSocket a ete coupee et retablie, la souscription est renouvelee automatiquement
- La queue est limitee a 100 items

---

## 4. Bibliotheque (Browse)

### Cliquer sur un element ne fait rien

**Symptome** : Cliquer sur Albums, Artists, etc. dans la bibliotheque n'affiche rien.

**Solutions** :
- Si la bibliotheque est tres volumineuse (>10 000 items), le chargement peut prendre quelques secondes
- Essayez de revenir a l'accueil (icone maison) puis de re-naviguer
- Un mecanisme anti-doublon empeche les clics multiples sur le meme item — attendez la reponse

### La recherche ne trouve pas de resultats

**Symptome** : Le champ de recherche ne filtre rien.

**Solutions** :
- La recherche locale filtre uniquement les elements deja charges
- Pour une recherche dans toute la bibliotheque Roon, utilisez l'item **Recherche** (avec l'icone loupe) en haut de la liste — un dialogue de recherche Roon s'ouvre

---

## 5. Historique de lecture

### L'historique est vide

**Symptome** : L'onglet "Historique" n'affiche aucun morceau.

**Solutions** :
- L'historique ne se remplit qu'avec les morceaux joues pendant que l'app est ouverte
- L'historique ne suit que les zones en etat "playing" avec des informations de piste valides
- L'historique est persiste dans `~/Library/Caches/playback_history.json`

### Cliquer sur un morceau de l'historique ne le relance pas

**Symptome** : Rien ne se passe quand on clique sur un morceau de l'historique.

**Solutions** :
- Verifiez qu'une zone est selectionnee (la lecture se lance sur la zone courante)
- Le morceau est recherche dans la bibliotheque Roon par son titre — si le titre exact n'existe plus, la lecture ne pourra pas etre lancee
- Les morceaux de radio en direct ne peuvent pas etre rejoues

---

## 6. Images et pochettes

### Les pochettes d'album ne s'affichent pas

**Symptome** : Les pochettes sont grises/vides dans l'app.

**Solutions** :
- Les pochettes sont recuperees directement depuis le Roon Core via le protocole MOO et servies localement sur le port 9150
- Testez dans un navigateur : `http://localhost:9150/image/<une_image_key>?width=300&height=300`
- Verifiez que l'app est bien connectee au Core
- Les pochettes sont mises en cache en memoire (LRU). Un redemarrage de l'app vide le cache

---

## 7. Peripheriques audio

### Un DAC USB n'apparait pas comme zone

**Symptome** : Un DAC branche en USB sur le Mac n'est pas visible dans les zones Roon.

**Solutions** :
- Le DAC doit etre gere par **Roon** pour apparaitre comme zone :
  1. Installer et lancer **Roon** (le client lourd) sur le Mac ou est branche le DAC
  2. Ou installer **Roon Bridge** sur le Mac
- Verifiez que le DAC est reconnu par macOS : **Reglages Systeme > Son > Sortie**
- Dans Roon, allez dans **Parametres > Audio** pour activer la sortie correspondante

### Le volume d'un DAC USB n'est pas controlable

**Symptome** : Le slider de volume n'a pas d'effet sur un DAC USB.

**Solutions** :
- Certains DAC gerent le volume en interne et ne l'exposent pas a Roon
- Dans Roon, verifiez **Parametres > Audio > (votre DAC) > Volume Control Mode** :
  - "Device Volume" utilise le volume du DAC
  - "DSP Volume" utilise le traitement numerique de Roon
  - "Fixed Volume" desactive le controle de volume

---

## 8. Build et developpement

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
- Le module s'appelle `Roon_Controller` (avec underscore) car le PRODUCT_NAME contient un espace
- Les fichiers de test doivent utiliser : `@testable import Roon_Controller`

### Les tests echouent

**Symptome** : `xcodebuild test` rapporte des echecs.

**Solutions** :
- Lancez les tests : `xcodebuild test -project RoonController.xcodeproj -scheme RoonControllerTests -destination 'platform=macOS'`
- Les tests unitaires ne necessitent pas de Core Roon — ils testent les modeles et la logique du service en isolation
- Verifiez que vous n'avez pas modifie les structures de donnees sans mettre a jour les tests

---

## Commandes de diagnostic utiles

```bash
# Verifier que l'app peut joindre le Core (port 9330)
nc -zv <ip_du_core> 9330

# Verifier le multicast SOOD (port 9003)
sudo tcpdump -i any udp port 9003

# Voir les logs de l'app
log stream --process "Roon Controller" --level debug

# Effacer le token d'autorisation
defaults delete com.bertrand.RoonController roon_core_token

# Lancer les tests Swift
cd RoonController && xcodebuild test -project RoonController.xcodeproj \
  -scheme RoonControllerTests -destination 'platform=macOS' 2>&1 | \
  grep -E "(Test Case|TEST)"

# Verifier le serveur image local
curl -o /dev/null -w "%{http_code}" http://localhost:9150/image/test_key?width=100\&height=100
```
