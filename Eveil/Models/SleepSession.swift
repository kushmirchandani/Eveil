import Foundation
import SwiftData

@Model
final class SleepSession {
    var id: UUID
    var date: Date
    var bedTime: Date
    var wakeTime: Date?
    var targetWakeTime: Date?
    var alarmCycles: Int
    var movementData: Data // Encoded [MovementEvent]

    init(date: Date = .now, bedTime: Date = .now) {
        self.id = UUID()
        self.date = date
        self.bedTime = bedTime
        self.alarmCycles = 0
        self.movementData = Data()
    }

    var movements: [MovementEvent] {
        get { (try? JSONDecoder().decode([MovementEvent].self, from: movementData)) ?? [] }
        set { movementData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var duration: TimeInterval? {
        guard let wake = wakeTime else { return nil }
        return wake.timeIntervalSince(bedTime)
    }

    var wakeAccuracy: Double? {
        guard let target = targetWakeTime, let actual = wakeTime else { return nil }
        let delta = abs(actual.timeIntervalSince(target))
        return max(0, 1 - (delta / (15 * 60))) // 1.0 = exact, 0.0 = 15+ min off
    }
}

struct MovementEvent: Codable {
    var timestamp: Date
    var intensity: Float // 0.0–1.0
    var zones: [Float]   // 4 FSR zone readings
}
