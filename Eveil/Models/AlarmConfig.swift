import Foundation
import SwiftData

@Model
final class AlarmConfig {
    var id: UUID
    var earliestWakeHour: Int
    var earliestWakeMinute: Int
    var preparationBufferMinutes: Int
    var calendarSyncEnabled: Bool
    var escalationTimerSeconds: Int
    var retriggerIntervalSeconds: Int
    var dismissalHoldSeconds: Double
    var selectedSoundPack: String
    var isEnabled: Bool

    init() {
        self.id = UUID()
        self.earliestWakeHour = 7
        self.earliestWakeMinute = 0
        self.preparationBufferMinutes = 60
        self.calendarSyncEnabled = true
        self.escalationTimerSeconds = 45
        self.retriggerIntervalSeconds = 180
        self.dismissalHoldSeconds = 8.0
        self.selectedSoundPack = "default"
        self.isEnabled = true
    }

    var earliestWakeTime: DateComponents {
        DateComponents(hour: earliestWakeHour, minute: earliestWakeMinute)
    }

    var earliestWakeDate: Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        components.hour = earliestWakeHour
        components.minute = earliestWakeMinute
        return Calendar.current.date(from: components) ?? .now
    }
}
