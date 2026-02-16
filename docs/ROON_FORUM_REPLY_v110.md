# Reply for Roon Community Forum — v1.1.0

## Post text (English)

---

Hi everyone,

Quick update — **v1.1.0 is out**, with a few quality-of-life improvements.

### Download

**[RoonController.dmg — v1.1.0](https://github.com/renesenses/roon-controller/releases/tag/v1.1.0)**

Universal binary (arm64 + x86_64) — macOS 12 (Monterey) and newer.
Unsigned: right-click > Open on first launch.

Or via Homebrew:
```
brew tap renesenses/roon-controller && brew install --cask roon-controller
```

### What's new in v1.1.0

**Volume control in Player view** — You can now adjust volume directly from the Player without switching to the Roon UI or the sidebar. The volume row includes a mute toggle, a draggable slider, and +/− buttons. Hold down +/− for continuous adjustment — no more clicking 20 times to go from quiet to loud. The current level is displayed in dB.

**Always starts on Home** — The app now always opens on the Home screen (Accueil), regardless of which view you were on when you last quit. No more landing on a stale Player view.

**Full multilingual UI** — The entire UI is now in English by default, with full translations for French, Spanish, German and Italian. Previous versions had French hardcoded in some places — that's cleaned up.

**Other improvements since v1.0.7** — Sidebar toggle button in Player mode (Cmd+\\), album tiles open detail instead of auto-playing, recently added albums tracked locally.

### Bug fix

Fixed a subtle volume bug where `Int()` truncation could cause the volume buttons to silently send the same value back to the Core. Now using proper rounding.

### Stats

293 unit tests, 0 failures. Full [changelog here](https://github.com/renesenses/roon-controller/blob/main/docs/CHANGELOG.en.md).

### Your feedback matters — even the small stuff

I'm really keen to hear what you think, even on things that might seem minor. UI details, small annoyances, features that feel slightly off, things you expected to work differently — **all of that is valuable**. It doesn't have to be a bug report. If something feels awkward, unintuitive, or just "not quite right", I'd love to know.

A few things I'm particularly curious about:
- **Volume control UX** — Does the slider + buttons layout feel natural? Is the repeat speed (200ms) right, or should it be faster/slower?
- **Navigation flow** — Does always starting on Home feel right, or would you prefer the app to remember where you left off?
- **Player view layout** — Is the information density good? Too much, too little?
- **Anything missing?** — What's the one thing you wish it did that it doesn't?

Don't hesitate to share screenshots or quick descriptions — even a one-liner like "the X button feels too small" is actionable feedback.

Thanks to everyone who's been testing and reporting. This project moves fast because of your input.

Happy listening!

Bertrand
