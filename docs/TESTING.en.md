# Testing Guide

## Requirements

- Active Roon Core paired with the extension
- macOS app built and running

## Manual Tests

### 1. Connection

| # | Test | Expected result |
|---|------|-----------------|
| 1.1 | Launch app with a Core on the network | SOOD discovery, automatic connection, zones appear |
| 1.2 | Launch app without a Core on the network | Connection screen, periodic discovery attempts |
| 1.3 | Shut down the Core during use | Automatic reconnection with exponential backoff |
| 1.4 | Restart the Core | Automatic reconnection, zones reappear |
| 1.5 | Manual IP connection (Settings) | Core pairs, zones appear |
| 1.6 | First launch (no token) | Extension appears in Roon > Extensions, waiting for authorization |

### 2. Zones

| # | Test | Expected result |
|---|------|-----------------|
| 2.1 | Select a zone | Zone is highlighted, player shows its content |
| 2.2 | Zone playing | Green "play" indicator in the sidebar |
| 2.3 | Zone paused | Orange "pause" indicator in the sidebar |
| 2.4 | Zone stopped | Grey "stop" indicator in the sidebar |
| 2.5 | Mini artwork in sidebar | 40x40 artwork next to current track title |
| 2.6 | Volume slider | Slider moves, volume changes in Roon |
| 2.7 | Mute button | Icon turns red, sound is muted |

### 3. Player

| # | Test | Expected result |
|---|------|-----------------|
| 3.1 | Play/Pause | Playback starts/pauses |
| 3.2 | Next/Previous | Next/previous track |
| 3.3 | Seek (click on bar) | Playback position changes |
| 3.4 | Album artwork | Displayed large (400x400), blurred background |
| 3.5 | Track info | Title, artist, album displayed |
| 3.6 | Time counter | Position and duration displayed, real-time progress |
| 3.7 | Shuffle | Button lights up blue, shuffle enabled |
| 3.8 | Repeat | Cycle: off -> loop -> loop_one -> off |
| 3.9 | Auto Radio | Button lights up blue, Roon radio enabled |

### 4. Queue

| # | Test | Expected result |
|---|------|-----------------|
| 4.1 | "Queue" tab | Queue track list is displayed |
| 4.2 | Current track | Highlighted with blue accent background (opacity 0.15) |
| 4.3 | Mini artwork | 40x40, rounded corners, left of each item |
| 4.4 | Title and artist | Displayed on two lines |
| 4.5 | Duration | Displayed on the right in m:ss format |
| 4.6 | Tap on a track | Playback resumes from that track |
| 4.7 | Zone change | Queue clears then reloads for the new zone |
| 4.8 | Empty queue | "Empty queue" message with icon |

### 5. Library (Browse)

| # | Test | Expected result |
|---|------|-----------------|
| 5.1 | "Library" tab | "Browse Library" button |
| 5.2 | Click the button | Category list (Albums, Artists, etc.) |
| 5.3 | Navigate into a category | Item list with artwork |
| 5.4 | Back button | Goes up one level |
| 5.5 | Home button | Returns to root |
| 5.6 | Search | Filters displayed results |
| 5.7 | Action on an item | Playback or sub-navigation depending on hint |

### 6. History

| # | Test | Expected result |
|---|------|-----------------|
| 6.1 | Play a track | Appears at the top of history |
| 6.2 | Click on a track | Search and playback in Roon library |
| 6.3 | Clear button | History is emptied |
| 6.4 | Restart the app | History is restored (file persistence) |

### 7. Settings

| # | Test | Expected result |
|---|------|-----------------|
| 7.1 | Open Settings (Cmd+,) | Settings window |
| 7.2 | Manual Core connection | Core pairs |
| 7.3 | Reconnect button | Disconnects then reconnects via SOOD |
| 7.4 | Default zone | Picker lists zones, choice persists across restarts |
| 7.5 | Sidebar playlist count | Picker 5/10/20/50/All, applies immediately |

## Build Verification

```bash
cd "Roon client/RoonController"
xcodebuild -scheme RoonController -configuration Debug build 2>&1 | tail -5
```

Expected result:
```
** BUILD SUCCEEDED **
```

## Automated Tests (Swift / XCTest)

The project includes unit tests in the `RoonControllerTests` target.

### Running tests

```bash
cd "Roon client/RoonController"
xcodebuild test -project RoonController.xcodeproj \
  -scheme RoonControllerTests \
  -destination 'platform=macOS'
```

Or from Xcode: **Product > Test** (Cmd+U).

### Test files

| File | Description |
|------|-------------|
| `Tests/RoonModelsTests.swift` | JSON decoding of models (BrowseItem, InputPrompt, QueueItem, PlaybackHistoryItem, RoonZone, BrowseResult) |
| `Tests/RoonServiceTests.swift` | Service logic (browse guard, history, zone selection, image URL) and MOO protocol (parsing, construction, request ID) |
| `Tests/ViewBehaviorTests.swift` | View behavior tests (default zone, playlist filtering, UI mode, browse views) |

### Test Details

**RoonModelsTests**:
- `testBrowseItemDecodesInputPromptAsObject` — input_prompt decoded as object
- `testBrowseItemDecodesWithoutInputPrompt` — optional input_prompt
- `testBrowseItemIdUsesItemKey` / `testBrowseItemIdFallsBackToTitle` — Identifiable logic
- `testWSBrowseResultDecodesWithInputPromptItems` — full decode of mixed browse_result
- `testBrowseResultItemsAreMutable` — mutable items and offset (pagination)
- `testPlaybackHistoryItemRoundTrip` — JSON encode/decode with ISO 8601 dates
- `testRoonZoneEqualityIncludesNowPlaying` / `testRoonZoneEqualityIncludesSeekPosition` — correct Equatable
- `testQueueItemDecoding` — full QueueItem decoding
- `testInputPromptDecoding` — InputPrompt decoding

**RoonServiceTests** (`@MainActor`):
- `testBrowsePendingKeyBlocksDuplicate` — same item_key doesn't trigger two browses
- `testBrowseDifferentKeyPassesGuard` — different item_key passes the guard
- `testBrowseBackResetsPendingKey` / `testBrowseHomeResetsPendingKey` — navigation resets guard
- `testBrowseWithoutItemKeySkipsGuard` — root browse is never blocked
- `testHistoryIsInitiallyEmpty` / `testClearHistoryRemovesAll` — history management
- `testHistoryDeduplicationPreventsConsecutiveSameTrack` — no consecutive duplicates
- `testSelectZoneClearsQueue` — zone change clears queue
- `testImageURLGeneration` / `testImageURLReturnsNilForNilKey` — image URL construction
- `testMOOMessageParseRequest` / `ParseContinue` / `ParseComplete` — parsing of 3 MOO verbs
- `testMOOMessageBuildRequest` / `BuildComplete` — construction and round-trip
- `testMOOMessageParseInvalidReturnsNil` / `ParseMissingRequestIdReturnsNil` — error cases
- `testMOORequestIdGeneratorIncrementsAtomically` — atomic ID generator

### Note on Module Name

The Swift module is named `Roon_Controller` (with underscore) because the PRODUCT_NAME is "Roon Controller" (with space). Test imports use `@testable import Roon_Controller`.

### Improvement Areas

- **Integration tests**: simulate a mock WebSocket server to test `RoonService` end-to-end
- **SOOD tests**: mock SOOD packet to validate reply parsing
- **UI tests**: XCUITest for critical user flows
- **CI**: `xcodebuild test` in a GitHub Action
