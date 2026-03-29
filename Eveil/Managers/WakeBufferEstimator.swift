import Foundation
import FoundationModels
import EventKit

// MARK: - Generable output type

@Generable
struct WakeBufferEstimate {
    /// Reasoning appears first in the struct so the model generates it before minutes,
    /// giving us something meaningful to animate as a typewriter once the response lands.
    @Guide(description: "One short sentence (max 15 words) explaining the key reason for the wake time — e.g. travel, prep, or routine. No filler, no punctuation beyond a period.")
    var reasoning: String

    @Guide(description: "Minutes the user should wake up before the event. Must be a multiple of 15 and between 15 and 120 inclusive.")
    var minutes: Int
}

// MARK: - Estimator

enum WakeBufferEstimator {

    struct Result {
        let minutes: Int
        let reasoning: String
    }

    static func estimate(for event: EKEvent, name: String = "") async -> Result {
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "EEEE 'at' h:mm a"
        let title = event.title ?? "Untitled event"
        let timeStr = timeFormatter.string(from: event.startDate)
        let nameClause = name.isEmpty ? "the user" : name

        let prompt = """
        \(nameClause) has "\(title)" on \(timeStr).
        Give a realistic wake-up lead time accounting for morning routine, travel, and any event prep.
        """

        do {
            let session = LanguageModelSession(
                instructions: "You estimate realistic morning wake-up lead times before calendar events. Be concise and direct."
            )
            let response = try await session.respond(to: prompt, generating: WakeBufferEstimate.self)
            let snapped = Int((Double(response.content.minutes) / 15).rounded()) * 15
            let clamped = min(120, max(15, snapped))
            return Result(minutes: clamped, reasoning: response.content.reasoning)
        } catch {
            return Result(minutes: 60, reasoning: "")
        }
    }
}
