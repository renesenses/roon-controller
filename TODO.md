# TODO

## Fait (v1.2.x)

- [x] Deplacer "Genres" de la section Explorer vers Ma Bibliotheque Musicale
- [x] Traduire "My Live Radio" en francais ("Mes radios live")
- [x] Afficher le chemin complet dans la barre de navigation des genres (breadcrumb)
- [x] Vue en grille pour les sous-genres (genre cards)
- [x] Afficher un message explicite si l'extension n'est pas autorisee dans Roon Core
- [x] Favoris Roon (coeur/toggle) pour les albums de la bibliotheque
- [x] Corriger la version extension envoyee au Roon Core (etait bloquee a 1.1.1)

## Limitations API Roon (points bloquants)

### Playlists

- **Pas de creation/edition de playlists via l'API Extension** : le Browse API ne supporte pas "Add to Playlist" pour les extensions tierces. Impossible de creer, modifier ou ajouter des morceaux a une playlist Roon depuis l'app.
- **Playlists TIDAL/Qobuz personnelles inaccessibles** : le Browse API expose les playlists editoriales (New Releases, Playlists, etc.) mais ne donne pas acces aux playlists personnelles de l'utilisateur TIDAL/Qobuz. Seul le client Roon officiel y accede via un chemin interne non disponible aux extensions.
- **Contournement** : export CSV des favoris radio au format `Artist,Title` compatible Soundiiz pour import dans les services de streaming.

### Browse API

- **Cles de navigation ephemeres** : les `item_key` du Browse API sont valides uniquement pour la session WebSocket courante. Apres reconnexion, toutes les cles sont invalides — il faut re-parcourir la hierarchie.
- **Hierarchies limitees** : seules `browse`, `internet_radio`, `search` et `settings` sont disponibles. Pas de hierarchie pour les playlists ou les favoris.
- **Recherche indirecte** : pas d'API de recherche directe — il faut naviguer dans le Browse, trouver l'item avec `input_prompt`, puis envoyer la requete de recherche via `browse()`.

### Transport / Lecture

- **Radio non seekable** : les flux radio ont `is_seek_allowed == false`. Le seek est desactive, et le replay radio utilise la hierarchie `internet_radio` (pas la recherche textuelle).
- **Seek macOS Now Playing** : le Media Center macOS (Now Playing dans la barre de menu) n'est pas notifie apres un seek manuel dans l'app.

### Reseau / Distribution

- **Multicast UDP** : `Network.framework` necessite un entitlement multicast signe par Apple (non disponible aux devs tiers). Contournement : sockets POSIX pour la decouverte SOOD.
- **App non signee** : pas de Developer ID. Sur macOS Sequoia/Tahoe, `xattr -cr` est obligatoire. Le "clic droit > Ouvrir" ne fonctionne plus.
- **ATS sur macOS Tahoe** : App Transport Security bloque les connexions HTTP/WS vers localhost par defaut. Exception ATS dans Info.plist necessaire.

## A faire

### UI

- [ ] Augmenter la hauteur de la zone en bas (transport bar / now playing)
- [ ] Badge des sources (Tidal/Qobuz/Bibliotheque) dans la section Dernierement de l'accueil
- [ ] Traduire "Tags" en francais ("Etiquettes" ou equivalent)

### Bugs remontes par Roland (v1.2.0 — post #38)

- [ ] #1 — Profil affiche le username macOS au lieu du profil Roon (possible pb de localisation allemande des titres Settings/Profile)
- [ ] #2 — Recently played vide : la boite violette disparait au clic
- [ ] #3 — Icone Settings (engrenage) : clic ne fonctionne pas (cmd+, marche)
- [ ] #4 — Stat boxes : Tracks et Composers ouvrent le mauvais layout (localisation ?)
- [ ] #5 — Seek : Now Playing macOS ne se met pas a jour apres un seek manuel
- [ ] #9 — Recently played → clic album ouvre la derniere vue Library au lieu de l'album
- [ ] #12 — Vue de demarrage ignore le reglage utilisateur (force toujours home)
- [ ] #13 — Breadcrumb genre partiel : fonctionne depuis la vue cartes mais disparait en vue liste
- [ ] #17 — Bouton MORE ouvre toujours l'historique meme si "recently added" est selectionne
- [ ] #19 — "My Live Radio" pas traduit en allemand
