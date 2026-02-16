# Reply for Roon Community Forum — v1.0.7

## Post text (English)

---

Hi @Roland_von_Unruh, @Nepherte, @Dirk-Pitt, and everyone following this little adventure!

Wow — the feedback on v1.0.6 was amazing. Roland, your 10-point report was like a proper QA session, and Nepherte, your UX eye caught things I completely missed. This is exactly what makes open-source fun. Thank you both, seriously.

So here we go — **v1.0.7 is ready**, and it's packed with your suggestions.

### Download

**[RoonController.dmg — v1.0.7 (beta)](https://github.com/renesenses/roon-controller/releases/tag/v1.0.7)**

Universal binary (arm64 + x86_64) — macOS 12 (Monterey) and newer.
Unsigned: right-click > Open on first launch.

Or if you prefer Homebrew:
```
brew tap renesenses/roon-controller && brew install --cask roon-controller
```

### What's new in v1.0.7

Here's what changed — and who inspired each fix:

**Settings accessible from sidebar** — Roland and Nepherte, you were both right: burying Settings under Library was a bad idea. There's now a gear icon at the bottom of the sidebar in both Player and Roon modes. One click, done.

**Profile picker** — Roland, you flagged the "roonserver" profile name. The app now lists all your Roon profiles in Settings and lets you switch between them. No more guessing which profile you're on!

**Clickable stat boxes** — Both of you expected the Artists / Albums / Tracks counters on the Home page to be clickable. Honestly, so did I when I looked at them again. They now navigate to the matching library section.

**Now Playing: proper exit** — Nepherte, you pointed out there was no obvious way to leave the fullscreen Now Playing view. Fair point! There's now a close button in the corner, and Escape works too.

**Album column cleaned up** — When you're already looking at an album's tracks, showing the album name on every row was just noise. Removed, as Nepherte suggested.

**Seek sync fixed** — Roland, remember when seeking from the Roon app didn't update the position here? Fixed. The local timer now properly listens to the Core's seek events. Also squashed an overflow bug that could cause the progress bar to jump around.

**Disk cache with limits** — The streaming cache now has a configurable size cap (default 200 MB) with automatic cleanup of oldest entries. You can see and adjust it in Settings.

**New Qobuz & TIDAL icons** — Roland, good call on the copyright concern. The Qobuz icon is now a custom vinyl/Q design — recognizable but safely ours. TIDAL gets its own icon too.

### Still on my list

A few items I haven't cracked yet — being transparent here:

**"Recently added" sort** — Roland, the sort order comes straight from the Roon Browse API, and it doesn't seem to offer a sort parameter. Still digging into this one.

**Album click behavior** — Right now clicking an album card starts playback. I want to add a way to just *open* the album without playing it. Working on the right UX for this.

**Sidebar recovery** — If the sidebar disappears in Player mode, there's no easy way to bring it back. A toggle button is coming.

**English UI** — Nepherte, point taken. The app is French by default because that's what I use daily, but the beta audience is international. I've started translating everything — full English is coming soon.

**Tooltips** — On the list for a future update. Small thing, big difference.

### Stats

286 unit tests, 0 failures. The codebase keeps growing but nothing is broken — that's always a good sign.

Full [changelog here](https://github.com/renesenses/roon-controller/blob/main/docs/CHANGELOG.en.md).

As always, I'm here if you hit any issues. Happy listening!

Bertrand
