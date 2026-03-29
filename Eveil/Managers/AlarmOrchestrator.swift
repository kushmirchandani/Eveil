import Foundation
import AlarmKit
import SwiftUI
import UserNotifications

/// Watches AlarmKit for dismissed alarms, runs the escalation countdown,
/// fires the device alarm, and kills it once the bed is empty.
@Observable
@MainActor
final class AlarmOrchestrator {

    /// Non-nil while the 10-second escalation countdown is running.
    var escalationCountdown: Int? = nil

    /// True once FORCE ALARM has been sent to the device.
    var isDeviceAlarmActive = false

    /// True for 3 seconds after the user successfully gets up.
    var successState = false

    private var alertingIDs: Set<UUID> = []

    // MARK: - Start watching AlarmKit

    func beginWatching(ble: BLEManager) {
        Task { @MainActor in
            for await alarms in AlarmManager.shared.alarmUpdates {
                let activeIDs = Set(alarms.map(\.id))

                // Track alarms that have started alerting and arm the sensors
                for alarm in alarms where alarm.state == .alerting {
                    if alertingIDs.insert(alarm.id).inserted {
                        ble.send("ARM")
                    }
                }

                // If an alerting alarm has disappeared it was dismissed/stopped
                let dismissed = alertingIDs.subtracting(activeIDs)
                if !dismissed.isEmpty {
                    alertingIDs.subtract(dismissed)
                    // Only escalate once — don't stack if already running
                    guard escalationCountdown == nil, !isDeviceAlarmActive else { continue }
                    await escalate(ble: ble)
                }
            }
        }
    }

    // MARK: - Escalation

    private func escalate(ble: BLEManager) async {
        // If bed is already empty when the alarm is dismissed, succeed immediately.
        if isBedEmpty(ble) {
            await showSuccess()
            return
        }

        // Fire an immediate notification so the user can tap to open the app.
        await fireEscalationNotification()

        // 10-second countdown — poll BLE each second; succeed early if bed empties
        for i in stride(from: 10, through: 1, by: -1) {
            escalationCountdown = i
            try? await Task.sleep(for: .seconds(1))

            if isBedEmpty(ble) {
                escalationCountdown = nil
                await showSuccess()
                return
            }
        }

        // Countdown reached 0 — fire the device alarm, then re-arm sensors
        // so FSR readings keep streaming while the alarm audio plays.
        escalationCountdown = nil
        ble.send("FORCE ALARM")
        isDeviceAlarmActive = true

        // Poll inline — wait for bed to empty, then re-arm and watch for return.
        // If the user gets back into bed the alarm re-fires immediately.
        // Only marks success once bed has been empty for 30 consecutive seconds.
        while isDeviceAlarmActive {
            try? await Task.sleep(for: .seconds(1))
            guard isBedEmpty(ble) else { continue }

            // Confirm still empty after 2 s
            try? await Task.sleep(for: .seconds(2))
            guard isBedEmpty(ble) else { continue }

            // Kill the alarm and re-arm the sensor for return-to-bed detection
            ble.send("ALARM KILL")
            isDeviceAlarmActive = false
//            ble.send("ARM")

//            // Watch for 30 s — if pressure returns, re-fire the device alarm
//            var stayedUp = true
//            for _ in 0..<30 {
//                try? await Task.sleep(for: .seconds(1))
//                if !isBedEmpty(ble) {
//                    // User got back in bed — immediately re-fire alarm
//                    ble.send("FORCE ALARM")
//                    stayedUp = false
//                    break
//                }
//            }

//            if stayedUp {
//                isDeviceAlarmActive = false
//                await showSuccess()
//            }
            // If not stayedUp, the while loop continues with FORCE ALARM active
        }
    }

    // MARK: - Helpers

    /// Bed is empty when BLE is connected and all 4 zones read below 5%.
    /// Uses connectionState rather than isSynced so a brief gap in readings
    /// while the alarm audio plays doesn't block detection.
    private func isBedEmpty(_ ble: BLEManager) -> Bool {
        guard ble.connectionState == .connected else { return false }
        let readings = ble.liveReadings
        return readings.count == 4 && readings.allSatisfy { $0 < 0.05 }
    }

    private func showSuccess() async {
        successState = true
        try? await Task.sleep(for: .seconds(3))
        successState = false
    }

    // MARK: - Shared alarm presentation builder

    static func makePresentation() -> AlarmPresentation {
        let stopButton = AlarmButton(
            text: "I'm up",
            textColor: .white,
            systemImageName: "checkmark"
        )
        let alert = AlarmPresentation.Alert(
            title: "Time to wake up — Éveil",
            stopButton: stopButton
        )
        let countdown = AlarmPresentation.Countdown(title: "Your alarm is coming up…")
        return AlarmPresentation(alert: alert, countdown: countdown)
    }

    // MARK: - Escalation notification

    private func fireEscalationNotification() async {
        let content = UNMutableNotificationContent()
        content.title = "Get out of bed."
        content.body = "You have 10 seconds before the device alarm arms."
        content.sound = .defaultCritical
        content.interruptionLevel = .timeSensitive

        let request = UNNotificationRequest(
            identifier: "eveil.escalation",
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Manual cancel (dev / override)

    func cancel(ble: BLEManager) {
        escalationCountdown = nil
        isDeviceAlarmActive = false
        ble.send("ALARM KILL")
        ble.send("ARM")
    }
}
