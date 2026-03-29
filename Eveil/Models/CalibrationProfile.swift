import Foundation
import SwiftData

@Model
final class CalibrationProfile {
    var id: UUID
    var emptyBaselines: [Float]    // 4 FSR zones — empty bed
    var occupiedBaselines: [Float] // 4 FSR zones — user in bed
    var calibratedAt: Date
    var isActive: Bool

    init() {
        self.id = UUID()
        self.emptyBaselines = [0, 0, 0, 0]
        self.occupiedBaselines = [0, 0, 0, 0]
        self.calibratedAt = .now
        self.isActive = false
    }

    var isCalibrated: Bool {
        occupiedBaselines.contains(where: { $0 > 0 })
    }

    func isOccupied(readings: [Float]) -> Bool {
        guard readings.count == 4 else { return false }
        return readings.enumerated().contains { i, reading in
            reading > emptyBaselines[i] + (occupiedBaselines[i] - emptyBaselines[i]) * 0.4
        }
    }
}
