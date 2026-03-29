import SwiftUI
import SwiftData
import HealthKit
import EventKit
import UIKit
import AlarmKit

// Minimal AlarmKit metadata — no custom data needed
struct EveilAlarmMetadata: AlarmMetadata {}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(BLEManager.self) private var ble: BLEManager?
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("morningBriefingEnabled") private var morningBriefingEnabled = true

    // Reflects actual system authorization status
    @State private var healthKitStatus: HKAuthorizationStatus = .notDetermined
    @State private var calendarStatus: EKAuthorizationStatus = .notDetermined
    @State private var softAlarmCountdown: Int? = nil
    @State private var loudAlarmCountdown: Int? = nil

    private let hkStore = HKHealthStore()

    var body: some View {
        NavigationStack {
            Form {
                // Integrations
                Section("Integrations") {
                    // HealthKit
                    HStack {
                        Label("Apple Health", systemImage: "heart.fill")
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { healthKitStatus == .sharingAuthorized },
                            set: { enabled in
                                if enabled {
                                    Task { await requestHealthKit() }
                                } else {
                                    openAppSettings()
                                }
                            }
                        ))
                        .labelsHidden()
                        .tint(.green)
                    }
                    if healthKitStatus == .sharingDenied {
                        Text("Access denied. Tap the toggle to open Settings and re-enable.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else if healthKitStatus == .sharingAuthorized {
                        Text("Imports sleep stages, heart rate, and HRV.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Calendar
                    HStack {
                        Label("Apple Calendar", systemImage: "calendar")
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { calendarStatus == .fullAccess },
                            set: { enabled in
                                if enabled {
                                    Task { await requestCalendar() }
                                } else {
                                    openAppSettings()
                                }
                            }
                        ))
                        .labelsHidden()
                        .tint(.green)
                    }
                    if calendarStatus == .denied || calendarStatus == .restricted {
                        Text("Access denied. Tap the toggle to open Settings and re-enable.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else if calendarStatus == .fullAccess {
                        Text("Used to calculate your wake window from tomorrow's first event.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Notifications
                Section("Notifications") {
                    Toggle(isOn: $morningBriefingEnabled) {
                        Label("Morning Briefing", systemImage: "bell.badge.fill")
                    }
                    .tint(.green)
                    Text("Sent when you exit bed — includes your first event and last night's summary.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Alarm
                Section("Alarm") {
                    NavigationLink {
                        AlarmSettingsView()
                    } label: {
                        Label("Alarm Settings", systemImage: "alarm.fill")
                    }
                }

                // Developer Tools
                Section("Developer Tools") {
                    // Soft (in-app) alarm demo
                    Button {
                        scheduleSoftAlarmDemo()
                    } label: {
                        Label(
                            softAlarmCountdown != nil ? "Scheduling…" : "Soft Alarm in 10s",
                            systemImage: "bell.fill"
                        )
                        .foregroundStyle(softAlarmCountdown != nil ? .orange : .white)
                    }
                    .disabled(softAlarmCountdown != nil)

                    // Loud (device) alarm demo
                    Button {
                        scheduleLoudAlarmDemo()
                    } label: {
                        Label(
                            loudAlarmCountdown.map { "Device alarm in \($0)s…" } ?? "Loud Device Alarm in 10s",
                            systemImage: "alarm.waves.left.and.right.fill"
                        )
                        .foregroundStyle(loudAlarmCountdown != nil ? .orange : .red)
                    }
                    .disabled(loudAlarmCountdown != nil || ble?.connectionState != .connected)

                    if ble?.connectionState != .connected {
                        Text("Connect a device to test the loud alarm.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Account
                Section("Account") {
                    Button(role: .destructive) {
                        hasCompletedOnboarding = false
                        dismiss()
                    } label: {
                        Label("Reset & Re-run Onboarding", systemImage: "arrow.counterclockwise")
                    }
                }

                // About
                Section("About") {
                    LabeledContent("Version") {
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                    Link(destination: URL(string: "https://eveil.app/privacy")!) {
                        Label("Privacy Policy", systemImage: "hand.raised.fill")
                    }
                    .foregroundStyle(.white)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await refreshStatuses() }
        }
    }

    // MARK: - Permission helpers

    private func refreshStatuses() async {
        // HealthKit
        if HKHealthStore.isHealthDataAvailable(),
           let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            healthKitStatus = hkStore.authorizationStatus(for: sleepType)
        }
        // Calendar
        calendarStatus = EKEventStore.authorizationStatus(for: .event)
    }

    private func requestHealthKit() async {
        await HealthKitManager.shared.requestAuthorization()
        await refreshStatuses()
    }

    private func requestCalendar() async {
        let store = EKEventStore()
        _ = try? await store.requestFullAccessToEvents()
        await refreshStatuses()
    }

    private func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Demo alarm helpers

    private func scheduleSoftAlarmDemo() {
        softAlarmCountdown = 10
        Task {
            do {
                try await AlarmManager.shared.requestAuthorization()

                let stopButton = AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.fill")
                let alert = AlarmPresentation.Alert(title: "Time to wake up — Éveil", stopButton: stopButton)
                let countdown = AlarmPresentation.Countdown(title: "Alarm in 10 seconds…")
                let presentation = AlarmPresentation(alert: alert, countdown: countdown)
                let attributes = AlarmAttributes<EveilAlarmMetadata>(
                    presentation: presentation,
                    tintColor: .green
                )
                // .timer fires after `duration` seconds — AlarmKit shows the countdown on Lock Screen
                let configuration = AlarmManager.AlarmConfiguration<EveilAlarmMetadata>.timer(
                    duration: 10,
                    attributes: attributes
                )
                try await AlarmManager.shared.schedule(id: UUID(), configuration: configuration)
            } catch {}
            await MainActor.run { softAlarmCountdown = nil }
        }
    }

    private func scheduleLoudAlarmDemo() {
        loudAlarmCountdown = 10
        Task {
            for remaining in stride(from: 9, through: 0, by: -1) {
                try? await Task.sleep(for: .seconds(1))
                await MainActor.run { loudAlarmCountdown = remaining == 0 ? nil : remaining }
            }
            ble?.send("FORCE ALARM")
        }
    }
}

#Preview {
    SettingsView()
}
