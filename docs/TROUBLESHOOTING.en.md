# Troubleshooting

## 1. Core Discovery (SOOD)

### App can't find the Roon Core

**Symptom**: The app stays on the connection screen, no zones appear.

**Solutions**:
- Verify that the Roon Core is running and on the same local network
- Check that no firewall blocks UDP port **9003** (SOOD protocol) and TCP port **9330** (Roon WebSocket)
- SOOD discovery uses UDP multicast on `239.255.90.90:9003` — some routers block multicast between VLANs
- Try a manual connection: **Settings** (Cmd+,) > enter the Core's IP address
- Wait 10 to 30 seconds: discovery may take time on first launch

### Extension doesn't appear in Roon

**Symptom**: The app is running but "Roon Controller macOS" is not visible in Roon > Settings > Extensions.

**Solutions**:
- Wait 10-20 seconds after the app starts
- Restart the app
- Check the system console (Console.app) for `RoonController` messages
- The extension must be authorized in **Roon > Settings > Extensions** — click **Authorize**

### Connection drops intermittently

**Symptom**: Zones disappear then reappear periodically.

**Solutions**:
- Check the stability of your local network (Wi-Fi vs Ethernet)
- The app reconnects automatically with exponential backoff (up to 30s)
- If the Core's IP address changed, the app restarts SOOD discovery automatically

---

## 2. Registration and Authorization

### App shows "Connecting" indefinitely

**Symptom**: The app discovers the Core but never transitions to "Connected" state.

**Solutions**:
- Check in **Roon > Settings > Extensions** if "Roon Controller macOS" is waiting for authorization
- Click **Authorize** to enable the extension
- If the extension doesn't appear at all, see the "Extension doesn't appear in Roon" section above

### Re-authorization after Core update

**Symptom**: The app was connected but no longer reconnects after a Core update.

**Solutions**:
- The authorization token may have been invalidated by the update
- The app will automatically re-register — check Roon > Extensions if a new authorization is required
- If the problem persists, clear the saved token: in Terminal, run `defaults delete com.bertrand.RoonController roon_core_token`

---

## 3. Playback and Controls

### Play/pause/next buttons do nothing

**Symptom**: Clicking transport controls has no effect.

**Solutions**:
- Verify that a zone is selected in the sidebar (highlighted in blue)
- Check that the zone is in a compatible state: `is_play_allowed` / `is_pause_allowed` must be `true`
- Some zones (stopped with no queue) don't support play — first launch a track from the library

### Seek (progress bar) doesn't work

**Symptom**: Clicking the progress bar doesn't change the playback position.

**Solutions**:
- Check that `is_seek_allowed` is `true` for the zone (some sources like radio don't support seeking)
- Streaming radio doesn't have seek capability

### Volume doesn't change

**Symptom**: Volume slider moves but actual volume doesn't change.

**Solutions**:
- Verify the zone has an output with volume control (some DACs don't expose volume to Roon)
- Volume changes are sent to the specific output — verify the output_id is correct

### Queue is empty

**Symptom**: The "Queue" tab shows "Empty queue" while a track is playing.

**Solutions**:
- Switch zones and come back — this forces a queue re-subscription
- If the WebSocket connection was interrupted and restored, the subscription is renewed automatically
- The queue is limited to 100 items

---

## 4. Library (Browse)

### Clicking an item does nothing

**Symptom**: Clicking Albums, Artists, etc. in the library shows nothing.

**Solutions**:
- If the library is very large (>10,000 items), loading may take a few seconds
- Try going back to home (house icon) then re-navigating
- A duplicate-click guard prevents multiple clicks on the same item — wait for the response

### Search returns no results

**Symptom**: The search field doesn't filter anything.

**Solutions**:
- Local search only filters already-loaded items
- For a search across the entire Roon library, use the **Search** item (magnifying glass icon) at the top of the list — a Roon search dialog opens

---

## 5. Playback History

### History is empty

**Symptom**: The "History" tab shows no tracks.

**Solutions**:
- History only fills with tracks played while the app is open
- History only tracks zones in "playing" state with valid track information
- History is persisted in `~/Library/Caches/playback_history.json`

### Clicking a history track doesn't replay it

**Symptom**: Nothing happens when clicking a track in the history.

**Solutions**:
- Verify a zone is selected (playback starts on the current zone)
- The track is searched in the Roon library by title — if the exact title no longer exists, playback can't be started
- Live radio tracks cannot be replayed

---

## 6. Images and Artwork

### Album artwork doesn't display

**Symptom**: Artwork appears grey/empty in the app.

**Solutions**:
- Artwork is fetched directly from the Roon Core via the MOO protocol and served locally on port 9150
- Test in a browser: `http://localhost:9150/image/<an_image_key>?width=300&height=300`
- Verify the app is connected to the Core
- Artwork is cached in memory (LRU). Restarting the app clears the cache

---

## 7. Audio Devices

### USB DAC doesn't appear as a zone

**Symptom**: A USB-connected DAC on the Mac is not visible in Roon zones.

**Solutions**:
- The DAC must be managed by **Roon** to appear as a zone:
  1. Install and run **Roon** (the full client) on the Mac where the DAC is connected
  2. Or install **Roon Bridge** on the Mac
- Verify the DAC is recognized by macOS: **System Settings > Sound > Output**
- In Roon, go to **Settings > Audio** to enable the corresponding output

### USB DAC volume is not controllable

**Symptom**: Volume slider has no effect on a USB DAC.

**Solutions**:
- Some DACs handle volume internally and don't expose it to Roon
- In Roon, check **Settings > Audio > (your DAC) > Volume Control Mode**:
  - "Device Volume" uses the DAC's volume
  - "DSP Volume" uses Roon's digital signal processing
  - "Fixed Volume" disables volume control

---

## 8. Build and Development

### Xcode compilation error

**Symptom**: `xcodebuild` fails with Swift errors.

**Solutions**:
- Check Xcode version: minimum **16.0**
- Check target: **macOS** (not iOS/iPadOS)
- Check settings: Deployment Target **macOS 15.0**, Swift **6.0**
- If the project is out of sync, regenerate it: `cd RoonController && xcodegen generate`

### `Unable to find module dependency: 'RoonController'` in tests

**Symptom**: Tests don't compile with an import error.

**Solutions**:
- The module is named `Roon_Controller` (with underscore) because the PRODUCT_NAME contains a space
- Test files must use: `@testable import Roon_Controller`

### Tests fail

**Symptom**: `xcodebuild test` reports failures.

**Solutions**:
- Run tests: `xcodebuild test -project RoonController.xcodeproj -scheme RoonControllerTests -destination 'platform=macOS'`
- Unit tests don't require a Roon Core — they test models and service logic in isolation
- Verify you haven't modified data structures without updating the tests

---

## Useful Diagnostic Commands

```bash
# Check that the app can reach the Core (port 9330)
nc -zv <core_ip> 9330

# Check SOOD multicast (port 9003)
sudo tcpdump -i any udp port 9003

# View app logs
log stream --process "Roon Controller" --level debug

# Clear the authorization token
defaults delete com.bertrand.RoonController roon_core_token

# Run Swift tests
cd RoonController && xcodebuild test -project RoonController.xcodeproj \
  -scheme RoonControllerTests -destination 'platform=macOS' 2>&1 | \
  grep -E "(Test Case|TEST)"

# Check the local image server
curl -o /dev/null -w "%{http_code}" http://localhost:9150/image/test_key?width=100\&height=100
```
