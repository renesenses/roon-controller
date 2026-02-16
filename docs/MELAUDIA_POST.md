# Roon Controller macOS — client natif leger, cherche beta-testeurs

Bonjour a tous,

## Roon, pour ceux qui ne connaissent pas

[Roon](https://roon.app) est un logiciel de lecture musicale haut de gamme pour audiophiles. Il s'articule autour d'un **Roon Core** (serveur qui gere la bibliotheque, le streaming Tidal/Qobuz, et le DSP) et de **clients de controle** (telecommandes) sur differents appareils. Le Core envoie l'audio vers des endpoints (DAC USB, streamers reseau, etc.) via le protocole proprietaire RAAT.

## Mon setup et le probleme

Mon Roon Core tourne sur un **Mac mini late 2012** — une machine modeste mais largement suffisante pour ce role. Mon poste de travail est un **Mac Studio** avec un DAC connecte en USB. Le probleme : **l'app officielle Roon sur le Mac Studio ne detecte pas le Core** sur le Mac mini. Connexion impossible, que ce soit en decouverte automatique ou en IP manuelle. J'ai fini par me resoudre a developper mon propre client.

## Roon Controller

C'est une application macOS native (SwiftUI) qui remplace le client officiel Roon.app (~500 Mo, Electron) par une app legere (~5 Mo) se connectant directement au Roon Core. Elle n'a pas vocation a tout faire — la partie **Roon Settings** (configuration du Core, gestion des dossiers musicaux, DSP, comptes streaming) n'est pas abordee. C'est un controleur de lecture, pas une console d'administration.

**Ce que fait l'app :**

- Decouverte automatique du Roon Core sur le reseau local (protocole SOOD)
- Controle complet : play/pause, next/previous, seek, volume, shuffle, repeat
- Navigation dans la bibliotheque Roon (albums, artistes, playlists, radios)
- File d'attente avec lecture depuis un point
- Historique de lecture avec replay (morceaux et radios live)
- Pochettes d'album avec fond flou
- Theme sombre style Roon

**Ce que ca ne fait PAS :**

- Pas de configuration du Core (Roon Settings)
- Pas de sortie audio — pour ca, **Roon Bridge** fait le travail (gratuit, ~37 Mo, daemon sans interface qui expose le DAC au Core)
- Pas de gestion de bibliotheque (import, edition de tags)

## Technique (pour les curieux)

Zero dependance externe. Les protocoles Roon (SOOD discovery + MOO/1 messaging) ont ete reimplementes en Swift pur par reverse-engineering du SDK Node.js officiel. L'app communique directement avec le Core via WebSocket, sans intermediaire.

Le code source est ouvert : https://github.com/renesenses/roon-controller

## Recherche de beta-testeurs

L'app fonctionne bien chez moi (macOS Sequoia, Roon 2.x, DAC connecte via Roon Bridge), mais j'aimerais la tester avec d'autres configurations :

- Differents DAC / endpoints (USB, reseau, AirPlay)
- Plusieurs zones
- Grandes bibliotheques
- macOS 15.x sur differents Mac (M1, M2, M3, Intel ?)

Si vous utilisez Roon et avez un Mac sous macOS 15+, le DMG est telechareable ici : https://github.com/renesenses/roon-controller/releases/tag/v1.0.0

L'app n'est pas signee Apple (pas de compte Developer). Au premier lancement : ouvrez un Terminal et lancez `xattr -cr "/Applications/Roon Controller.app"`, ou bien lancez l'app, macOS la bloquera, puis allez dans **Reglages Systeme > Confidentialite et securite > Ouvrir quand meme**.

N'hesitez pas si vous avez des questions ou des retours !

Bertrand
