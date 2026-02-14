> **[English version](ISSUES.en.md)** | Francais

# Registre des incidents

Adapte du "Issue Register" PRINCE2. Le suivi actif se fait sur [GitHub Issues](https://github.com/renesenses/roon-controller/issues) ; ce fichier est le registre consolide.

```mermaid
pie title Repartition par severite
    "Critique" : 5
    "Majeur" : 8
    "Mineur" : 13
```

```mermaid
timeline
    title Chronologie des incidents
    2026-02-10 : ISS-001 SOOD multicast 🔴
               : ISS-002 SOOD Big Endian 🟠
               : ISS-003 SOOD unicast 🟠
               : ISS-004 MOO services 🟠
               : ISS-006 Browse decodage 🟡
               : ISS-007 Historique doublons 🟡
               : ISS-010 CI Xcode 🟡
    2026-02-11 : ISS-005 Queue param 🟠
    2026-02-12 : ISS-008 Tahoe ATS 🔴
               : ISS-009 Seek bar 🟡
               : ISS-011 Boucle connexion 🟠
    2026-02-13 : ISS-012 Browse cles session 🟠
               : ISS-013 WS timeout 🔴
               : ISS-014 Flash reconnexion 🟡
               : ISS-015 Pochettes null 🟡
               : ISS-016 CI permissions 🟡
    2026-02-14 : ISS-017 Recherche playlists 🟠
               : ISS-018 Pagination playlists 🟠
               : ISS-019 Playlists en grille 🟡
               : ISS-020 Detection playlist 🟡
               : ISS-021 Compteur morceaux 🟡
               : ISS-022 Play Playlist visible 🟡
               : ISS-023 Flash changement piste 🟡
               : ISS-024 Crash MPRemoteCommand 🔴
               : ISS-025 Crash MPMediaItemArtwork 🔴
               : ISS-026 Tracks detecte playlist 🟡
```

| ID | Date | Description | Severite | Statut | Resolution | Ref. |
|----|------|-------------|----------|--------|------------|------|
| ISS-001 | 2026-02-10 | SOOD : Network.framework necessite un entitlement multicast signe Apple, bloquant la decouverte UDP | Critique | Resolu | Remplacement par sockets POSIX (`dfb29d2`) | [L-006](LESSONS_LEARNED.md#l-006) |
| ISS-002 | 2026-02-10 | SOOD : encodage Big Endian du port dans le paquet query, non documente | Majeur | Resolu | Correction du format paquet avec encodage BE (`dfb29d2`) | [L-002](LESSONS_LEARNED.md#l-002) |
| ISS-003 | 2026-02-10 | SOOD : reponses unicast non recues car envoyees sur un socket different de celui d'ecoute | Majeur | Resolu | Ecoute sur le socket d'envoi pour les reponses unicast (`c61c94a`) | [L-003](LESSONS_LEARNED.md#l-003) |
| ISS-004 | 2026-02-10 | MOO : noms de services codes en dur incorrects, empechant la registration | Majeur | Resolu | Reverse-engineering des noms exacts depuis le protocole (`221393c`) | [L-004](LESSONS_LEARNED.md#l-004) |
| ISS-005 | 2026-02-11 | Queue : parametre `zone_or_output_id` manquant dans le body de subscription | Majeur | Resolu | Ajout du parametre dans le body JSON (`cd6a3dc`) | — |
| ISS-006 | 2026-02-10 | Browse : decodage `input_prompt` comme string au lieu d'objet + requetes en double | Mineur | Resolu | Decodage polymorphe + deduplication des requetes (`7dfbc43`) | — |
| ISS-007 | 2026-02-10 | Historique : entrees dupliquees au redemarrage de l'app | Mineur | Resolu | Deduplication par ID au chargement (`abb0db4`) | — |
| ISS-008 | 2026-02-12 | macOS Tahoe 26.3 : connexion WebSocket echoue silencieusement (ATS bloque HTTP local) | Critique | Resolu | Ajout exception ATS localhost + fix handshake WS (`a37d78f`) | [L-010](LESSONS_LEARNED.md#l-010) |
| ISS-009 | 2026-02-12 | Seek bar pas remise a zero au changement de piste | Mineur | Resolu | Reset du seek a 0 sur chaque changement de piste (`033ba0b`) | — |
| ISS-010 | 2026-02-10 | CI : erreurs de build Xcode 16.4 sur les runners GitHub | Mineur | Resolu | Correction des flags de build et du nom de module (`a587c83`) | [L-016](LESSONS_LEARNED.md#l-016) |
| ISS-011 | 2026-02-12 | Premiere connexion : boucle connect/disconnect quand l'extension n'est pas encore approuvee | Majeur | Resolu | Gestion de l'etat `waitingForApproval` (`4e577d6`) | — |
| ISS-012 | 2026-02-13 | Browse : cles API (`item_key`) liees a la session, invalides apres reconnexion | Majeur | Resolu | Utilisation de cles de session fraiche pour chaque requete (`9db489e`) | [L-005](LESSONS_LEARNED.md#l-005) |
| ISS-013 | 2026-02-13 | WebSocket : timeout ressource de 15s coupe la connexion lors de periodes d'inactivite | Critique | Resolu | Configuration du timeout ressource URLSession a 300s (`45a3436`) | — |
| ISS-014 | 2026-02-13 | Reconnexion : flash rouge/vert de l'indicateur de statut a chaque reconnexion | Mineur | Resolu | Lissage de l'affichage de l'etat de connexion (`0420e5b`) | — |
| ISS-015 | 2026-02-13 | Pochettes : `image_key` null dans historique et favoris (pas dans le cache) | Mineur | Resolu | Extension du cache pochettes a tous les ecrans (`a7f34ac`) | — |
| ISS-016 | 2026-02-13 | CI : workflow Claude Code echoue — permission `id-token` manquante, timeout mal place | Mineur | Resolu | Ajout permission `id-token: write` et deplacement du timeout au niveau job (`d1b75a5`) | [L-015](LESSONS_LEARNED.md#l-015) |
| ISS-017 | 2026-02-14 | Recherche playlists sidebar effectuait une recherche globale Browse au lieu d'un filtre local | Majeur | Resolu | Filtre local par `localizedCaseInsensitiveContains` (`8b0932b`) | — |
| ISS-018 | 2026-02-14 | Seulement 100 playlists chargees dans la sidebar et le Browse (pas de pagination) | Majeur | Resolu | Pagination en boucle avec `load(offset:count:)` (`d0c8438`) | — |
| ISS-019 | 2026-02-14 | Playlists affichees en grille au lieu de liste (detection `shouldShowGrid` incorrecte) | Mineur | Resolu | Ajout `isPlaylistListView` et exclusion des containers playlist de la grille (`d0c8438`) | — |
| ISS-020 | 2026-02-14 | Detection playlist echouait si `image_key` absent au niveau list (playlist sans pochette) | Mineur | Resolu | Suppression du requirement `image_key` dans `isPlaylistView` (`d0c8438`) | — |
| ISS-021 | 2026-02-14 | Compteur de morceaux incorrect : le filtre basé sur `subtitle` non vide excluait des morceaux | Mineur | Resolu | Filtre par `hint == "action_list"` (`d0c8438`) | — |
| ISS-022 | 2026-02-14 | "Play Playlist" apparaissait comme premier element de la liste de morceaux | Mineur | Resolu | Exclusion des items `hint == "action"` du filtre morceaux (`d0c8438`) | — |
| ISS-023 | 2026-02-14 | Flash de l'ancien morceau lors du changement de piste (next/previous/searchAndPlay) | Mineur | Resolu | Activation de `playbackTransitioning` avec dimming opacity dans les vues (`d0c8438`) | — |
| ISS-024 | 2026-02-14 | Crash au demarrage : closures MPRemoteCommandCenter appelaient des methodes @MainActor depuis la queue interne du framework MediaPlayer | Critique | Resolu | Dispatch via `Task { @MainActor in }` dans chaque closure addTarget (`5caaaf8`) | — |
| ISS-025 | 2026-02-14 | Crash Now Playing : closure MPMediaItemArtwork heritait de l'isolation @MainActor du Task parent, appelée depuis la queue interne MPNowPlayingInfoCenter | Critique | Resolu | Extraction dans `nonisolated static func makeArtwork(data:size:)` (`5caaaf8`) | — |
| ISS-026 | 2026-02-14 | Vue Tracks (Morceaux) detectee a tort comme playlist, affichant un header playlist inutile | Mineur | Resolu | Ajout `isTrackListView` teste avant `isPlaylistView` dans la chaine de rendu (`5caaaf8`) | — |
