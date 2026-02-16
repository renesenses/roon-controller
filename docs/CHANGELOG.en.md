> English | **[Version francaise](CHANGELOG.md)**

# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

```mermaid
timeline
    title Version History
    2026-02-11 : v1.0.0
                : Initial native app
                : SOOD + MOO/1
                : Player, queue, history
                : CI/CD
    2026-02-12 : v1.0.1
                : Fix macOS Tahoe 26.3
                : Fix seek bar
    2026-02-13 : v1.0.2
                : Roon UI redesign
                : Playlists
                : Homebrew Cask
    2026-02-13 : v1.0.3
                : Universal binary
                : +63 tests (203)
                : Remove Node.js
    2026-02-14 : v1.0.4
                : Roon-style playlists
                : 4 Browse views (Genres, TIDAL, Tracks, Composers)
                : macOS Now Playing (Control Center)
                : Default zone setting
                : +41 tests (244)
    2026-02-15 : v1.0.5
                : TIDAL/Qobuz tabs in Player
                : Streaming pre-fetch + disk cache
                : My Live Radio
                : +29 tests (273)
    2026-02-15 : v1.0.6
                : macOS 12 (Monterey) support
                : #available extensions
                : +5 tests (278)
    2026-02-16 : v1.0.7
                : Settings in sidebar (cogwheel)
                : Profile picker
                : Seek sync fix
                : Clickable stat boxes
                : New Qobuz & TIDAL icons
                : +8 tests (286)
    2026-02-16 : v1.1.0
                : Volume in Player view
                : +/- repeat-on-hold buttons
                : Default Home screen
                : 293 tests
```

## [Unreleased]

## [1.1.0] - 2026-02-16

### Added

- Volume control in Player view: mute toggle, custom slider, +/− buttons with repeat-on-hold, dB display (`3e7ef78`)
- `adjustVolume(outputId:delta:)`: relative volume API for step buttons (`3e7ef78`)
- `VolumeRepeatButton`: button component that fires on tap and repeats every 200ms while held (`3e7ef78`)

### Changed

- App always starts on the Home screen (Roon UI mode, Home section) regardless of last state (`060cdb4`)

### Fixed

- `changeVolume`: use `Int(value.rounded())` instead of `Int(value)` to avoid truncation errors (`3e7ef78`)

### Technical

- Full multilingual UI (English source + fr/es/de/it translations) (`c7407a8`)
- Sidebar toggle button + Cmd+\ shortcut in Player mode (`00f20ed`)
- Album tile click opens detail instead of playing (`4dd34cc`)
- Track recently added albums locally via Browse API full scan (`b07eb29`)

## [1.0.7] - 2026-02-16

### Added

- Settings gear icon in both Player and Roon mode sidebars (`37de864`)
- Profile picker in Settings: list and switch Roon profiles (`450f05d`)
- Clickable stat boxes on Home page: navigate to Artists, Albums, Tracks (`2b39e57`)
- Close button and Escape key to dismiss Now Playing fullscreen view (`40f8264`)
- Disk cache size limit (200 MB default) with LRU eviction, visible in Settings (`c285d73`)
- TIDAL and Qobuz brand icons in sidebar (`267a9b0`, `cf4da9a`)
- 8 new unit tests (286 total)

### Changed

- Qobuz icon: custom vinyl/Q design replacing brand logo (copyright safe) (`cf4da9a`)
- Qobuz icon rendering intent changed from template to original (`cf4da9a`)
- Album column hidden when viewing tracks of a single album (`620a548`)

### Fixed

- Seek timer overflow when position exceeds track duration (`00348dd`)
- Seek sync from external controllers: local interpolation timer yields to server-side `zones_seek_changed` events (`00348dd`)

## [1.0.6] - 2026-02-15

### Changed

- Deployment target lowered from macOS 15 (Sequoia) to macOS 12 (Monterey) (`730927d`)
- `.tint()` replaced with `.accentColor()` for macOS 12 compatibility (11 occurrences) (`730927d`)
- `NavigationSplitView` replaced with `NavigationView` + `.navigationViewStyle(.columns)` (`730927d`)
- `.onChange(of:) { old, new in }` replaced with `.onChangeCompat(of:)` using `#available` wrapper (`730927d`)
- `.tracking()` replaced with `.trackingCompat()` with `.kerning()` fallback (14 occurrences) (`730927d`)
- `.scrollContentBackground(.hidden)` and `.formStyle(.grouped)` wrapped in `#available` extensions (`730927d`)
- `.defaultSize()` removed (`.frame(minWidth:minHeight:)` sufficient) (`730927d`)
- `onTapGesture { location in }` replaced with `DragGesture(minimumDistance: 0)` (`730927d`)
- `String.split(separator: String)` replaced with `range(of:)` for macOS 12 (`730927d`)

### Added

- `CompatibilityModifiers.swift`: centralized compatibility extensions (`onChangeCompat`, `hideScrollBackground`, `groupedFormStyleCompat`, `trackingCompat`) (`730927d`)
- 5 new unit tests (278 total) (`730927d`)

**Roon native UI**
- Artist detail pages (discography, bio) and album pages (tracks, hero header)
- Global library search (artists, albums, tracks, composers)
- Playlist management: create, rename, delete, reorder
- Tag and genre navigation
- Sort and filter options in grid/list views
- Keyboard shortcuts (space, arrows, Cmd+F, Cmd+L)

**Core Settings**
- Refactored SettingsView with tabs (Connection, Zones, Playback, Streaming, Extensions, About)
- Audio zone and output configuration (group/ungroup, volume)
- DSP chain display per zone
- Streaming account status (TIDAL, Qobuz)
- Installed extension management

**Radio Favorites**
- Model refactoring: Browse hierarchy for reliable replay
- Playback via Browse API `internet_radio` instead of text search
- Roon playlist creation from favorites
- Simplified UX: swipe-to-delete, sort, filter by station

## [1.0.5] - 2026-02-15

### Added

- TIDAL and Qobuz tabs in Player sidebar with compact carousels (`a157663`)
- SF Symbols icon bar replacing segmented Picker (5 fixed + dynamic services) (`a157663`)
- Per-service streaming view: sections in `LazyVStack`, horizontal 100px card carousels (`a157663`)
- Card tap → album navigation in Browse section via `browseToStreamingAlbum()` (`a157663`)
- `cachedStreamingSectionsForService()`: filtered streaming cache read per service (`a157663`)
- `streamingCacheVersion`: reactive counter to signal cache updates to UI (`a157663`)
- Streaming sections pre-fetch with 24h disk cache (`8744236`)
- Sidebar categories disk cache for instant display on launch (`8744236`)
- My Live Radio grid view with station playback (`200b4e5`)
- 29 new unit tests (273 total): SidebarSection round-trip, streaming cache, album navigation (`a157663`, `cb8218a`)

### Changed

- `SidebarSection` refactored with `.streaming(serviceName:)` associated value and custom `RawRepresentable` (`a157663`)
- Tab bar padding reduced to accommodate dynamic icons (`a157663`)

### Fixed

- TIDAL/Qobuz navigation by title instead of session keys (expired keys) (`d767492`)
- Playlist track playback: use API level instead of counting pushes (`232f09b`)
- Streaming album back: restore carousels without reload (`cb8218a`)
- Cover art flickering fix on track change (`8744236`)
- Image server: async port retry with dynamic port test (`cdff283`)
- Fix pbxproj: remove duplicate group references (`a48060c`)

## [1.0.4] - 2026-02-14

### Added

- Roon-style playlist list view (64px thumbnails, duration subtitles) (`d0c8438`)
- Full playlist pagination in sidebar and Browse (200+ playlists) (`d0c8438`)
- Default playback zone setting (persisted by `display_name`) (`5163eb9`)
- Sidebar playlist count setting (5/10/20/50/all) (`d0c8438`)
- Placeholder artwork for playlists without cover art (`d0c8438`)
- 4 specialized Browse views: Genres (gradient cards), TIDAL/streaming (carousel with sections), Tracks (table with cover prefetch), Composers (circular grid with initials) (`5caaaf8`)
- macOS Now Playing integration: track info, artwork and media controls in Control Center (`5caaaf8`)
- Mode toggle button (Roon → Player) in sidebar (`5caaaf8`)
- Cover art prefetch in Tracks view (NSCache + RoonImageProvider, 100 images ahead) (`5caaaf8`)
- `StreamingSection` model for streaming service categories (`5caaaf8`)
- 41 new unit tests (244 total): specialized Browse views, genre/streaming/tracks/composer detection, Now Playing, mode toggle (`5caaaf8`)

### Changed

- Default display mode: Roon UI (instead of Player) (`5163eb9`)
- Local playlist filtering in sidebar instead of global Browse search (`8b0932b`)
- Playlist detection no longer requires `image_key` at list level (`d0c8438`)
- Active Browse category tracked via `browseCategory` in RoonService (`5caaaf8`)

### Fixed

- Sidebar playlist search performed global Browse search instead of local filter (`8b0932b`)
- Only 100 playlists loaded (missing pagination) (`d0c8438`)
- Playlists displayed as grid instead of list (`d0c8438`)
- Playlist detection failed without list-level artwork (`d0c8438`)
- Track count mismatch (filter excluded tracks without subtitles) (`d0c8438`)
- "Play Playlist" appeared in the track list (`d0c8438`)
- Old track flash during track change (next/previous/searchAndPlay) (`d0c8438`)
- Startup crash: MPRemoteCommandCenter closures called @MainActor methods from internal queue (`5caaaf8`)
- Now Playing crash: MPMediaItemArtwork closure implicitly @MainActor-isolated, called from MPNowPlayingInfoCenter queue (`5caaaf8`)
- Tracks view incorrectly detected as playlist (unwanted playlist header on flat track list) (`5caaaf8`)

## [1.0.3] - 2026-02-13

### Added

- Universal binary (arm64 + x86_64) for Release configuration (`186a625`)
- Extended cover art cache to all screens (history, favorites, queue) (`a7f34ac`)
- 63 new unit tests (203 total): models, MOO protocol, cache, registration (`c37e604`, `a96672e`)

### Fixed

- WebSocket 15s resource timeout on reconnections (`45a3436`)
- Red/green flash during reconnection display (`0420e5b`)

### Removed

- Legacy Node.js backend (everything is native Swift) (`4294d49`)

## [1.0.2] - 2026-02-13

### Added

- Playlist detail view with hero header and track table (`581100b`, `ed8b75a`)
- Search within library browsing (`2a264d1`)
- Manual Core IP connection (persistent) (`07a245e`)
- Homebrew Cask for simplified installation (`b875642`)
- "Recently Added" tab from Roon Core (`40fb216`)

### Changed

- Complete UI redesign matching Roon native style (`ee2d5e6`, `24f569f`, `71cc27c`, `78b8588`)
- Zone selector moved to transport bar (`fdcd470`)
- Default display mode: player (`68aff5b`)

### Fixed

- Playlist track playback using session-bound keys (`9db489e`)
- First-pairing flow (waitingForApproval state) (`4e577d6`)
- Album art display and transport controls for playlists (`98f3b03`)

## [1.0.1] - 2026-02-12

### Fixed

- macOS Tahoe 26.3 compatibility: ATS, WebSocket handshake, logging (`a37d78f`)
- Seek bar not resetting to 0 on track change (`033ba0b`)

## [1.0.0] - 2026-02-11

### Added

- Native macOS application (SwiftUI) — zero external dependencies
- SOOD protocol: automatic Roon Core discovery (UDP multicast, POSIX sockets)
- MOO/1 protocol: binary WebSocket communication with the Core
- Full player: play/pause, next/prev, seek, shuffle, repeat, radio
- Album artwork with dynamic blurred background
- Roon library browsing (Browse API) with pagination
- Queue with play-from-here
- Per-output volume control (slider + mute)
- Playback history with replay (tracks and live radio)
- Radio favorites: save and CSV export (compatible with Soundiiz)
- Automatic reconnection with exponential backoff
- Local seek interpolation for smooth progress bar
- Dark theme matching Roon style
- French/English localization (follows system language)
- CI/CD with GitHub Actions and Claude Code integration
- Bilingual technical documentation

[Unreleased]: https://github.com/renesenses/roon-controller/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/renesenses/roon-controller/compare/v1.0.7...v1.1.0
[1.0.7]: https://github.com/renesenses/roon-controller/compare/v1.0.6...v1.0.7
[1.0.6]: https://github.com/renesenses/roon-controller/compare/v1.0.5...v1.0.6
[1.0.5]: https://github.com/renesenses/roon-controller/compare/v1.0.4...v1.0.5
[1.0.4]: https://github.com/renesenses/roon-controller/compare/v1.0.3...v1.0.4
[1.0.3]: https://github.com/renesenses/roon-controller/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/renesenses/roon-controller/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/renesenses/roon-controller/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/renesenses/roon-controller/releases/tag/v1.0.0
