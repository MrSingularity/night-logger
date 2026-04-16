# NightLogger 🌙

An on-device sleep sound monitor for iOS. NightLogger passively listens overnight and detects respiratory events — coughing, snoring, sneezing, gasping, and sleep talking — entirely on your iPhone. No audio is ever sent to the cloud.

---

## Requirements

| | |
|---|---|
| Xcode | 15.0 or later |
| iOS | 17.0 or later |
| Device | Real iPhone (microphone required) |

---

## Setup & Run

1. Unzip the project and open `night-logger.xcodeproj` in Xcode
2. Select the `night-logger` target → **Signing & Capabilities**
3. Check **Automatically manage signing** and select your Apple ID under **Team**
4. Connect your iPhone via USB and select it as the run target
5. Press **⌘R**
6. On first launch: **iPhone Settings → General → VPN & Device Management → [your Apple ID] → Trust**

> **Important:** Before recording, go to **iPhone Settings → Display & Brightness → Auto-Lock → Never** and keep the device on charge. The Neural Engine used for sound classification cannot run while the screen is locked.

---

## Using the App

### Recording
1. Open the **Record** tab
2. Tap **Start Recording**
3. Place the phone on your bedside table
4. Tap **Stop Recording** in the morning

### Dashboard
1. Open the **Dashboard** tab and tap your session
2. Review the event breakdown and hourly timeline
3. Under **Review These Sounds**, tap ▶ to listen to uncertain clips
4. Tap ✓ to confirm or ✗ to delete each event
5. **Sleep talking** events always have a playable 15-second clip

### Confidence levels

| Level | Confidence | Behaviour |
|---|---|---|
| High | ≥ 70% | Counted immediately |
| Medium | 45–69% | Flagged for review, 15s clip saved |
| Discarded | < 45% | Silently ignored |

---

## Architecture

```
Microphone
    ↓
AVAudioEngine
    ↓
SNClassifySoundRequest v1 (on-device Neural Engine)
    ↓
AudioEvent saved to Documents/ as JSON
    ↓
Dashboard reads live from SessionStore
```

### Detected classes
`cough` · `snoring` · `sneeze` · `speech / whispering` (sleep talking) · `gasp` · `unknown`

### Fallback
If the Neural Engine is unavailable (Simulator), a rule-based RMS + ZCR heuristic takes over so the UI remains fully demonstrable.

---

## Privacy
- All classification runs on-device — no audio leaves the device
- Only event metadata (class, confidence, timestamp) is persisted
- Audio clips are stored in the app's private Documents directory and deleted when dismissed

---

## Known Limitations
- Auto-Lock must be set to **Never** — the Neural Engine cannot run in the background when the screen is locked (iOS restriction)
- The classifier was not trained specifically on sleep audio; quiet sounds near the confidence boundary may be missed

---

## Report
See `NightLogger_Report.pdf` for the full 1-page lab report.
