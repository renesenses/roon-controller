# TODO

## Fait (v1.2.x)

- [x] Deplacer "Genres" de la section Explorer vers Ma Bibliotheque Musicale
- [x] Traduire "My Live Radio" en francais ("Mes radios live")
- [x] Afficher le chemin complet dans la barre de navigation des genres (breadcrumb)
- [x] Vue en grille pour les sous-genres (genre cards)
- [x] Afficher un message explicite si l'extension n'est pas autorisee dans Roon Core
- [x] Favoris Roon (coeur/toggle) pour les albums de la bibliotheque
- [x] Corriger la version extension envoyee au Roon Core (etait bloquee a 1.1.1)

## Fait (v1.2.3-beta)

- [x] #1 — Profil : retry fetchProfileName (3x avec delai) si Browse API pas pret
- [x] #2 — Section Dernierement visible quand au moins un onglet a du contenu
- [x] #3 — Engrenage Settings : fallback via menu app si sendAction echoue
- [x] #4 — Stat boxes multilingues (DE/IT/ES/SV/NL/JA/KO)
- [x] #5 — Seek : mise a jour du Media Center macOS apres seek
- [x] #9 — Clic album : utilise le champ album au lieu du titre du morceau
- [x] #12 — Vue de demarrage : @AppStorage au lieu de @SceneStorage
- [x] #13 — Breadcrumb genre : condition alternative via stack.first + traductions
- [x] #17 — Bouton MORE conditionnel selon l'onglet actif
- [x] #19 — "My Live Radio" traduit via String(localized:) (DE/IT/ES/FR)
- [x] Fil d'ariane genre : racine "Genres" au lieu de "Bibliotheque", navigation limitee aux genres
- [x] Traduction de tous les titres d'actions browse (Play Artist, Play Album, Add to Library, etc.)
- [x] Grille affichee des 1 item avec image (seuil abaisse de 3)
- [x] Transport bar centree verticalement

## Fait (v1.2.4)

- [x] Infobulles (tooltips) sur tous les boutons icones (~35 boutons, 7 fichiers)
- [x] Version bumpee 1.2.3 → 1.2.4

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
- ~~**Seek macOS Now Playing**~~ : corrige en v1.2.3-beta (`updateNowPlayingInfo()` appele apres seek).

### Reseau / Distribution

- **Multicast UDP** : `Network.framework` necessite un entitlement multicast signe par Apple (non disponible aux devs tiers). Contournement : sockets POSIX pour la decouverte SOOD.
- **App non signee** : pas de Developer ID. Sur macOS Sequoia/Tahoe, `xattr -cr` est obligatoire. Le "clic droit > Ouvrir" ne fonctionne plus.
- **ATS sur macOS Tahoe** : App Transport Security bloque les connexions HTTP/WS vers localhost par defaut. Exception ATS dans Info.plist necessaire.

## A faire

### UI

- [x] ~~Augmenter la hauteur de la zone en bas (transport bar / now playing)~~ — contenu centre verticalement
- ~~Badge des sources (Tidal/Qobuz/Bibliotheque) dans la section Dernierement de l'accueil~~ — **Limitation API** : l'API Roon n'expose aucun champ `source`/`provider` dans BrowseItem, NowPlaying ou PlaybackHistoryItem

### Bugs remontes par Roland (v1.2.0 — post #38)

Tous corriges en v1.2.3-beta (voir section "Fait" ci-dessus).
