# Reply for Roon Community Forum — v1.2.1

## Post text (English)

---

Hi everyone, and **@Roland** in particular — thank you for the thorough testing and detailed reports in posts #19, #31 and #33. Every single bug you listed has been addressed.

### Download

**[RoonController.dmg — v1.2.1](https://github.com/renesenses/roon-controller/releases/tag/v1.2.1)**

Universal binary (arm64 + x86_64) — macOS 12 (Monterey) and newer.

**Important — the app is unsigned.** On first launch:
```
xattr -cr "/Applications/Roon Controller.app"
```
Or: System Settings > Privacy & Security > Open Anyway.
(Right-click > Open does **not** work on macOS Sequoia/Tahoe.)

Or via Homebrew:
```
brew tap renesenses/roon-controller
brew install --cask roon-controller
```
If you already have it: `brew upgrade --cask roon-controller`

### Root cause — why you weren't seeing the fixes

The DMG attached to all previous GitHub releases **contained a stale v1.0.2 binary** from February 13th — not the version shown in the release tag. So whether you downloaded the DMG directly or used Homebrew, you were running code that predated all the fixes. This is now corrected: the v1.2.1 DMG contains the real v1.2.1 binary (verified by mounting and reading `CFBundleShortVersionString`).

### Roland's bugs — status

| # | Bug | Status |
|---|-----|--------|
| 1 | Profile name shows macOS username instead of Roon profile | **Fixed** — displays the Roon profile name |
| 2 | Switching profiles breaks in Roon mode | **Fixed** — uses title matching instead of stale session keys (`4af4a6b`) |
| 3 | Empty history = blank page | **Fixed** — shows an empty state message |
| 4 | No gear icon for Settings | **Fixed** — gear icon in sidebar + Player toolbar, Cmd+, shortcut (`ef3d3b3`) |
| 5 | "Recently Added" sorted alphabetically | **Fixed** — local tracking via full album scan, new albums shown newest-first (`b07eb29`) |
| 6 | Stat boxes not clickable | **Fixed** — clicking Artists/Albums/Tracks navigates to the corresponding view (`2b39e57`) |
| 7 | No sidebar toggle in Player mode | **Fixed** — toggle button + Cmd+\\ shortcut (`00f20ed`) |

### What else is new since v1.1.0

**v1.1.1** — Community feedback fixes:
- Heart toggle for Roon library favorites (Browse API)
- Mouse back button support for browse navigation
- Volume 0–100 scale option and startup view setting
- Responsive layout on window resize
- Seek sync fix: server updates take priority over local timer
- 326 tests

**v1.2.0** — Genre navigation:
- Genre grid view with breadcrumb and leaf genre cards
- Explicit message when the extension is not yet authorized in Roon
- Sidebar reorganization (Genres in Library, My Live Radio in Explorer)

**v1.2.1** — Release fixes:
- Rebuilt DMG with correct binary
- Homebrew Cask updated (version, sha256, macOS 12+ dependency)
- About window now shows "Version 1.2.1" (no longer displays a redundant build number)
- Documentation: prerequisites split into "To use the app" vs "To build from source" — Xcode is **not** needed to run the app

### Prerequisite clarification

You only need:
- **macOS 12** (Monterey) or newer
- A **Roon Core** on your local network

Xcode is only required if you want to compile from source. The DMG and Homebrew install do not require Xcode.

### Feedback welcome

If anything still doesn't work after updating, please let me know — include the version number shown in Settings > About so we can confirm you're on v1.2.1.

Full [changelog here](https://github.com/renesenses/roon-controller/blob/main/docs/CHANGELOG.md).

Happy listening!

Bertrand
