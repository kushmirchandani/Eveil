import SwiftUI
import SwiftData

@main
struct EveilApp: App {
    @State private var bleManager = BLEManager()
    @State private var alarmOrchestrator = AlarmOrchestrator()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            SleepSession.self,
            AlarmConfig.self,
            CalibrationProfile.self,
        ])
        // Try persistent store first; fall back to in-memory if the store is incompatible
        // (common during development when models change). Delete the app to reset.
        if let container = try? ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        ]) {
            return container
        }
        return try! ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        ])
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(bleManager)
                .environment(alarmOrchestrator)
                .task { alarmOrchestrator.beginWatching(ble: bleManager) }
        }
        .modelContainer(sharedModelContainer)
    }
}
