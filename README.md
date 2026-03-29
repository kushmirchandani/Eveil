# Éveil

**The alarm that only stops when you leave the bed.**

Éveil is an iOS app paired with a custom under-mattress pressure-sensor device. It targets people who struggle to physically get out of bed -particularly those with ADHD, sleep inertia, or dysania. Unlike conventional alarms that can be silenced with a tap, Éveil's alarm only dismisses when sustained zero pressure is detected across all sensor zones, meaning you've actually stood up.

![Éveil](Eveil.png)

---

## How It Works

1. **Pressure sensing** -A 4-zone FSR (force-sensitive resistor) array sits under the mattress and streams live readings to the app over BLE.
2. **Smart wake window** -The app reads your calendar, calculates when you need to be up, and uses an on-device Foundation Models session to estimate a realistic wake buffer for each event.
3. **Escalating alarm** -When AlarmKit fires the system alarm and you dismiss it without leaving the bed, a 10-second countdown begins. If you're still in bed when it hits zero, the hardware speaker fires a forced alarm that only stops when the bed is empty.
4. **No snooze button** -By design, not by oversight.

---

## Tech Stack

| Layer | Technology |
|---|---|
| Language | Swift 5 |
| UI | SwiftUI |
| Persistence | SwiftData |
| Alarms | AlarmKit |
| Health data | HealthKit |
| On-device AI | Foundation Models (`FoundationModels` / `@Generable`) |
| Hardware comms | CoreBluetooth (Nordic UART Service) |
| Calendar | EventKit |
| Auth | Sign in with Apple |
| Cloud sync | CloudKit (entitlement configured) |
| Min deployment | iOS 26 |

---

## Project Structure

```
Eveil/
├── EveilApp.swift              # App entry point, SwiftData container, BLE + alarm bootstrap
├── ContentView.swift           # Root view: onboarding gate, tab router, escalation & success overlays
├── Info.plist                  # Background modes (BLE, audio, fetch, processing), AlarmKit usage, URL scheme
├── Eveil.entitlements          # HealthKit, CloudKit, Sign in with Apple, push notifications
│
├── Models/
│   ├── AlarmConfig.swift       # SwiftData model -alarm schedule, escalation timing, sound pack
│   ├── CalibrationProfile.swift# SwiftData model -per-zone empty/occupied pressure baselines
│   └── SleepSession.swift      # SwiftData model -bed/wake times, movement events, wake accuracy
│
├── Managers/
│   ├── BLEManager.swift        # CoreBluetooth central -scan, connect, UART send/receive, auto-reconnect
│   ├── AlarmOrchestrator.swift # Watches AlarmKit state, runs escalation countdown, triggers device alarm
│   ├── HealthKitManager.swift  # Reads sleep stages, HR, HRV, respiratory rate; computes daily breakdowns
│   └── WakeBufferEstimator.swift # On-device LLM call to estimate wake-up lead time from calendar events
│
├── Views/
│   ├── LaunchScreenView.swift  # Animated dot-wave launch screen with haptic pulses
│   ├── Onboarding/
│   │   ├── OnboardingView.swift        # Sign in with Apple + video background
│   │   ├── PermissionsView.swift       # Health, Bluetooth, Notifications, Calendar permission requests
│   │   ├── NameInputView.swift         # User name entry
│   │   ├── AgeInputView.swift          # Age input
│   │   ├── MorningStrugglesView.swift  # Morning difficulty self-assessment
│   │   ├── PreparationTimeView.swift   # Default wake buffer configuration
│   │   ├── GreetingTransitionView.swift# Personalized welcome transition
│   │   └── LoopingVideoPlayer.swift    # AVPlayer wrapper for background video
│   ├── Today/
│   │   └── TodayView.swift     # Dashboard -alarm status, next event, sleep summary, device status
│   ├── Sleep/
│   │   └── SleepView.swift     # Sleep history, stage charts, weekly trends, health metrics
│   ├── Alarm/
│   │   └── AlarmView.swift     # Alarm configuration -schedule, sounds, escalation settings
│   ├── Device/
│   │   └── DeviceView.swift    # BLE pairing, live sensor view, calibration flow, UART console
│   └── Settings/
│       └── SettingsView.swift  # Account, preferences, integrations
│
└── Assets.xcassets/            # App icon, brand images, background
```

---

## Hardware

The app communicates with an ESP32-based device over **BLE using the Nordic UART Service** (NUS). The device runs a custom firmware that sends FSR readings in the format:

```
FSR0:1024 FSR1:2048 FSR2:512 FSR3:3072
```

Values are raw 12-bit ADC readings (0-4095), normalized to 0.0-1.0 in the app.

**Key UART commands the app sends:**

| Command | Purpose |
|---|---|
| `ARM` | Start streaming sensor readings |
| `FORCE ALARM` | Trigger the onboard hardware speaker |
| `ALARM KILL` | Stop the hardware alarm |
| `INFO` | Request firmware version (`FW:x.y.z` response) |

The device also has an onboard speaker as a redundant alarm path independent of the phone.

---

## Alarm Flow

```
AlarmKit fires system alarm
         │
         ▼
   User taps "I'm up"
         │
         ▼
  ┌──────────────────┐
  │ Bed empty?       │──── Yes ──→ Success overlay ("You're up!")
  └──────────────────┘
         │ No
         ▼
  10-second countdown
  (checks pressure each second)
         │
         ▼
  ┌──────────────────┐
  │ Still in bed?    │──── No ──→ Success
  └──────────────────┘
         │ Yes
         ▼
  FORCE ALARM → device speaker
  (loops until bed is empty for 2+ seconds)
```

---

## Key Features

**On-device AI wake buffer** -`WakeBufferEstimator` uses Apple's `FoundationModels` framework with a `@Generable` struct to ask an on-device language model how many minutes before a calendar event the user should wake up, taking into account event type, time, and context.

**HealthKit integration** -Reads sleep stages (deep, core, REM, awake), heart rate, HRV, respiratory rate, and SpO2 from Apple Watch / Oura Ring data. Displays nightly breakdowns and weekly trends.

**Calibration system** -The `CalibrationProfile` stores per-zone empty and occupied baselines. Occupancy detection uses a 40% threshold between empty and occupied readings per zone.

**Background BLE** -Uses `CBCentralManager` state restoration (`willRestoreState`) and the `bluetooth-central` background mode for persistent device connectivity. Auto-reconnects on unexpected disconnects.

**Escalation overlays** -Full-screen countdown overlay with large numeric display that turns red at 3 seconds. Success overlay with spring animation when the user gets up.

---

## Permissions

| Permission | Reason |
|---|---|
| Bluetooth | Device communication via BLE |
| Notifications | Alarm delivery and escalation alerts |
| HealthKit | Sleep and heart rate data import |
| Calendar | Wake window calculation from events |
| Background Modes | `bluetooth-central`, `audio`, `fetch`, `processing`, `remote-notification` |

---

## Getting Started

1. Open `Eveil.xcodeproj` in Xcode
2. Select your development team under Signing & Capabilities
3. Build and run on a physical iOS device (BLE requires real hardware)
4. On first launch, sign in with Apple and grant permissions through the onboarding flow
5. Pair your Éveil hardware device from the **MyEveil** tab

> **Note:** The simulator cannot use CoreBluetooth. A physical device is required for full functionality.

---

## Build Requirements

- Xcode 26+
- iOS 26+
- Physical iOS device for BLE features

---

*Éveil -named for Eva, who knew exactly when to knock.*
