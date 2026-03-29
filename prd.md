# Éveil — Product Requirements Document
**App Version:** 1.0  
**Last Updated:** March 2026  
**Status:** Pre-development  

---

## 1. Overview

### 1.1 Product Summary

Éveil is a hardware-paired iOS app designed for people who have difficulty physically getting out of bed — a pattern especially common in ADHD, sleep inertia disorders, and dysania. The app pairs with the Éveil under-mattress sensor device to monitor sleep in real time and run a smart alarm system that only dismisses when the user has physically left the bed.

The alarm is not just smarter than a phone alarm — it is structurally different. It cannot be dismissed by tapping a screen. Dismissal requires standing up.

### 1.2 The Problem

Standard alarms solve the wrong problem. They assume the user wants to wake up and just needs a nudge. For many people — particularly those with ADHD or high sleep inertia — the obstacle is not awareness that it is time to get up. It is the physical inability to initiate the action of leaving the bed, even when fully aware of the need.

Snooze culture is a symptom, not a habit failure. Éveil treats it as a physiological challenge.

### 1.3 The Solution

Éveil combines:
- A pressure/force sensor array under the mattress that knows whether the user is in bed
- Sleep cycle detection that identifies the optimal moment to wake within a user-defined window
- A calendar-aware alarm engine that understands the stakes of each morning
- An alarm that escalates, pauses to prevent habituation, and re-triggers — and only turns off when the bed is empty
- A personal sleep report that builds understanding of each user's sleep patterns over time

---

## 2. Target Users

### Primary
- People with ADHD who struggle with sleep inertia and morning transitions
- People who chronically oversleep despite wanting to wake earlier
- People who have tried every alarm app and still rely on another person to wake them

### Secondary
- Heavy sleepers without a clinical diagnosis
- People with irregular schedules who need context-aware alarms (shift workers, freelancers)
- Partners who are woken by the other person's alarm and want a smarter system

---

## 3. Hardware Dependency

The Éveil app is designed primarily as a companion to the Éveil hardware device. Core features — sleep tracking, pressure-based alarm dismissal, and the onboard speaker fallback — require the device. A subset of features (manual alarms, calendar sync, sleep history) are available without hardware via a software-only mode.

**Hardware specs (relevant to app):**
- 4x FSR sensor array with 3D-printed force concentrator plate
- ESP32 microcontroller with BLE + WiFi
- Onboard speaker for hardware-side alarm fallback
- Under-mattress form factor (~45cm wide, ~20cm deep, ~8–10mm thick)
- Communicates with app over BLE; syncs history over WiFi

---

## 4. Core Features

### 4.1 Device Setup & Calibration

**Onboarding calibration flow:**

1. User places device under mattress topper
2. App guides user through baseline capture (empty bed reading across all 4 zones)
3. User lies down in normal sleeping position — app captures occupied reading
4. App stores per-zone pressure thresholds: empty baseline, occupied baseline, motion variance range
5. Calibration can be re-run at any time (e.g. after moving, new mattress, new sleeping partner)

### 4.2 Sleep Tracking

The app passively monitors the pressure and motion readings from the device throughout the night to build a picture of each sleep session.

**What it tracks:**
- Time in bed (from when pressure first registers to when bed is empty)
- Movement events — restlessness, position shifts, periods of stillness
- Sleep stage inference — using motion variance as a proxy for light vs deep sleep cycles (supplemented by HealthKit data if available)
- Wake events — partial pressure drops suggesting sitting up without leaving
- Time of final bed exit

**HealthKit integration:**
- Imports heart rate, respiratory rate, and Apple Watch sleep data if available
- Éveil sensor data and HealthKit data are fused for improved sleep stage accuracy
- Writes sleep session summaries back to HealthKit

### 4.3 Calendar Integration

Calendar context is central to Éveil's alarm intelligence. The app is not just an alarm — it is a morning planning layer.

**What it does:**
- Reads the user's calendar (Apple Calendar / Google Calendar via OAuth)
- Identifies the first event of each day and calculates the latest possible wake time
- Builds a wake window: latest wake time minus a user-configurable preparation buffer (default: 60 minutes)
- If no events exist, falls back to a user-set default wake time or skips alarm entirely

**User controls:**
- Set preparation buffer per event type (e.g. 90 min for in-person, 30 min for remote calls)
- Mark certain calendars as ignored (personal, holidays)
- Override: set a manual earliest wake time independent of calendar

### 4.4 Smart Alarm Engine

The alarm engine combines sleep cycle data, calendar context, and pressure sensing to determine when and how to wake the user.

**Wake window logic:**
- Alarm will not fire before the user-set earliest time
- Alarm targets light sleep phases within the wake window
- If the user is in deep sleep at the start of the window, the engine waits up to 20 minutes for a lighter phase
- If no lighter phase is detected within the buffer, the alarm fires at the hard deadline regardless

**Alarm escalation:**
1. Alarm fires — phone notification sound + vibration + hardware speaker (simultaneously)
2. Timer starts (configurable, default 45 seconds)
3. If no pressure drop detected after timer: alarm stops (habituation prevention)
4. System waits for a motion event or a fixed interval (configurable, default 3 minutes), then re-triggers
5. Loop repeats, optionally increasing volume or changing alarm sound on each cycle
6. Hard deadline mode: if within 15 minutes of latest wake time, escalation shortens and volume maxes
7. At the 5 minute before a wake up time the actual in device alarm should sound

**Dismissal:**
- Alarm is dismissed only when sustained zero pressure is detected across all relevant zones
- Sustained zero = pressure below threshold for a configurable hold period (default: 8 seconds)
- Dismissal is logged with timestamp

**Snooze:**
- There is no snooze button
- This is a product decision, not an oversight

### 4.5 Alarm Sound & Habituation Prevention

A fixed alarm sound heard repeatedly becomes background noise. Éveil addresses this in two ways:

- **Auto-stop on non-response** — alarm stops after ~45 seconds of no exit detected, preventing the user from sleeping through it as ambient sound
- **Sound variation** — each re-trigger cycle can use a different alarm tone from the user's selected set, maintaining stimulus novelty
- **Re-trigger on motion** — if the hardware detects movement after the alarm stops, it interprets this as stirring and re-fires sooner than the fixed interval

User-selectable alarm sound packs will be available in-app. Default sounds are chosen for arousal effectiveness, not pleasantness.

### 4.6 Sleep Reports

Each sleep session generates a report. Over time, reports build a personal sleep profile.

**Per-session report includes:**
- Movement timeline (visualized as a waveform across the night)
- Sleep stage distribution pulled from HealthKit (for users who also have an apple watch/oura ring or any sleep tracker)
- Number of alarm cycles before dismissal
- Wake time vs target wake time — a "wake accuracy" score

**Weekly and monthly summaries:**
- Average sleep duration and consistency
- Wake accuracy trend
- Correlation between calendar pressure (busy next-day schedule) and sleep quality
- Insights written in plain language ("You sleep best when you go to bed before 11pm" / "You take 3x longer to exit bed on Mondays")

**Personal sleep profile:**
- Built over 30+ nights of data
- Used by the alarm engine to refine cycle predictions
- Shown to user as a readable breakdown of their sleep tendencies

### 4.7 Notifications & Daily Briefing

On alarm dismissal (when the user gets up), the app sends a morning briefing notification:

- First calendar event of the day and time until it starts
- Current weather (location-based)
- A brief sleep quality summary from the night ("You got 6h 40m, mostly light sleep after 3am")

This is delivered as a notification — not a screen the user has to open — to reduce friction right after waking.

---

## 5. App Structure

### 5.1 Tab Navigation

| Tab | Purpose |
|---|---|
| Today | Current alarm status, tonight's plan, morning briefing |
| Sleep | Sleep history, session reports, personal profile |
| Alarm | Alarm configuration, schedule, sound settings |
| Device | Hardware status, calibration, sensor diagnostics |
| Settings | Account, integrations, notifications, preferences |

### 5.2 Today Tab

The primary screen the user sees. Shows:
- Status of tonight's alarm (active / no events / manual override)
- Next calendar event and target wake time
- Last night's sleep summary (post-wake)
- Device connection status

### 5.3 Alarm Tab

- Set earliest wake time
- Set preparation buffer
- Enable / disable calendar sync
- Configure escalation behavior (timer duration, re-trigger interval)
- Select alarm sounds
- Test alarm (triggers a 10-second preview)

### 5.4 Sleep Tab

- Session list (most recent first)
- Tap into any session for full report
- Weekly and monthly summary views
- Personal sleep profile card

### 5.5 Device Tab

- BLE connection status and signal strength
- Firmware version and update prompt
- Live sensor view (real-time pressure readings per zone — useful for calibration and troubleshooting)
- Re-run calibration
- Speaker test

---

## 6. Integrations

| Integration | Purpose | Required |
|---|---|---|
| Apple HealthKit | Sleep data import/export, heart rate fusion | Reccomended |
| Apple Calendar | Wake window calculation | Recommended |
| Apple Weather | Morning briefing | No |

---

## 7. Permissions

| Permission | Reason |
|---|---|
| Bluetooth | Hardware device communication |
| Local Network | WiFi sync for session history upload |
| Notifications | Alarm delivery, morning briefing |
| Calendar | Wake window calculation |
| Health (read) | Sleep and heart rate data import |
| Location (when in use) | Weather in morning briefing |

---

## 8. Technical Notes

### 8.1 Alarm Reliability

iOS background execution limits are a real constraint. Éveil will handle this by:
- Using AlarmKit for alarm delivery — surfaces as a full-screen system alarm interrupt (identical presentation to the native Clock app) rather than a standard notification banner. The only available action is "Open Éveil," which launches the app and begins the guided wake flow. There is no dismiss or snooze action exposed at the system level.
- Keeping the BLE connection alive via background modes (`bluetooth-central`)
- Hardware speaker as a redundant delivery path that does not depend on the phone

<!-- ### 8.2 Pressure Threshold Logic

Dismissal logic must account for edge cases:
- Pet on the bed (lower, more distributed pressure — distinguish by zone pattern)
- User sitting up without leaving (partial pressure drop — require sustained full zero)
- Partner still in bed (zone-specific thresholds per calibrated user profile)
- Device shifting position over time (recalibration prompt if readings drift from baseline) -->

### 8.3 Sleep Cycle Inference

Without a medical-grade sensor, Éveil's sleep stage inference is a proxy based on:
- Motion variance from FSR readings (high variance = lighter sleep or wake)
- Stillness duration (extended stillness often correlates with deep sleep)
- Time-of-night priors (deep sleep concentrates in the first half of the night)
- HealthKit heart rate variability and respiratory rate if available

This should be presented to users as an estimate, not a clinical reading. The actual user stages should be pulled from healthkit as the inteneded audience is using an oura ring/apple watch or some devcie.

---

## 10. Success Metrics

| Metric | Target |
|---|---|
| Alarm dismissal rate (user exits bed within alarm session) | >85% of mornings |
| Average cycles before dismissal | <3 |
| Daily active device connection | >90% of nights |
| 30-day retention | >60% |

---

## 11. Open Questions

1. What is the right default re-trigger interval between alarm cycles — 2 minutes, 3 minutes, or dynamic based on proximity to hard deadline?
2. Should users be able to see the live pressure sensor readings at all times, or only during calibration and diagnostics?
3. How do we handle the first night before enough sleep data exists to make cycle predictions?
4. Should the app support a "guest mode" for when the hardware is in someone else's room?
5. What is the right framing for sleep stage data given it is inferred, not measured — how do we communicate confidence levels?

---

*Éveil — named for Eva, who knew exactly when to knock.*