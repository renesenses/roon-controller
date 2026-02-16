# Reply for Roon Community Forum — v1.0.5

## Post text (English)

---

Hi @Roland_von_Unruh and everyone following along! 👋

First off — a big thank you to Roland for the incredibly thorough testing and to the community for the encouraging feedback. It really helps shape this project, and I appreciate every report.

I'm happy to share a **new beta release: v1.0.5**, with quite a few improvements driven directly by your input.

### Download

🎵 **[RoonController.dmg — v1.0.5 (beta)](https://github.com/renesenses/roon-controller/releases/tag/v1.0.5)**

Universal binary (arm64 + x86_64). Unsigned: run `xattr -cr "/Applications/Roon Controller.app"` in Terminal before first launch, or go to **System Settings > Privacy & Security > Open Anyway** after macOS blocks it.

### What's new in v1.0.5

**TIDAL & Qobuz tabs in Player mode**

This one I'm really excited about — the Player sidebar now has dedicated TIDAL and Qobuz tabs (when these services are available in your Roon setup). Each tab shows compact carousels with album cards that load from a 24-hour disk cache, so they appear instantly even before the Core responds. Tapping a card takes you straight to the album in Library.

The old segmented picker has been replaced by a compact icon bar (SF Symbols) to fit everything nicely in the 250px sidebar.

**Streaming pre-fetch & disk cache**

On connection, the app now pre-fetches TIDAL and Qobuz sections in the background and caches them to disk. On relaunch, you see your content immediately while fresh data loads behind the scenes — it makes the app feel much snappier.

**My Live Radio**

New grid view for My Live Radio stations with direct playback. Simple and clean. 📻

### Bug fixes

- **TIDAL/Qobuz navigation** — Fixed a bug where navigation would break after returning from an album (session keys expired). Navigation now uses title-matching instead of cached session keys.
- **Playlist playback** — Fixed track play using API level tracking instead of counting browse pushes.
- **Cover art flickering** — Fixed artwork briefly disappearing on track changes.
- **Image server** — Fixed async port retry on startup.

### Responses to your reported issues

Roland, here's where things stand on each of the items you raised on Feb 15:

1. **Profile name showing "roonserver"** — Good catch. The profile name comes from the Roon Core's registration response, so if the Core runs headless (e.g. on a dedicated server), it may just report the machine hostname. That's what Roon sends us — I'll dig into whether there's a way to fetch the actual user profile name separately.

2. **"Recently played" differs between machines** — This is actually by design: playback history is stored locally per instance and isn't synced from the Core. Unfortunately the Roon Browse API doesn't expose a server-side "recently played" list, so each Roon Controller instance tracks what it observes playing. I agree it can be confusing though — I'll think about how to make this clearer in the UI.

3. **Album art not displaying on the Roon Server machine** — Thanks for reporting this one. It's likely a localhost image routing issue — the app runs a local HTTP server for artwork caching, and when running on the same machine as the Core, there can be a port or loopback conflict. I've improved the port retry logic in v1.0.5 — please give it a try and let me know if it helps! If not, a few details about your setup would help me debug further (is the Core running as a different user? Different network interface?).

4. **Artwork disappearing from Now Playing when paused** — Starting with v1.0.4, the app preserves existing artwork when updating Now Playing on pause. Please check if v1.0.5 still shows this issue — it may have been a race condition that's since been resolved. Let me know!

5. **Qobuz navigation state persisting** — Great news here: the TIDAL/Qobuz navigation has been significantly reworked in v1.0.5. Navigation now resets properly when switching sections and uses title-based matching instead of stale session keys. This should be fully resolved — looking forward to your confirmation. ✅

6. **Seek position not syncing from other controllers** — The app subscribes to `zones_seek_changed` events from the Core and should update the position. However, the local seek interpolation timer (for smooth progress bar animation) may override incoming values in some edge cases. I'll investigate this further — it might need a priority mechanism for server-side seek updates. Definitely want to get this right.

### Stats

273 unit tests, 0 failures. Full [changelog here](https://github.com/renesenses/roon-controller/blob/main/docs/CHANGELOG.en.md).

Really looking forward to your feedback on v1.0.5 — enjoy! 🎶

Bertrand
