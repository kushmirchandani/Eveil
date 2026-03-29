import SwiftUI
import SwiftData

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(AlarmOrchestrator.self) private var orchestrator
    @Environment(BLEManager.self) private var ble
    @State private var isLaunching = true

    var body: some View {
        ZStack {
            Group {
                if hasCompletedOnboarding {
                    MainTabView()
                } else {
                    OnboardingView()
                }
            }
            .preferredColorScheme(.dark)

            if isLaunching {
                LaunchScreenView { isLaunching = false }
                    .ignoresSafeArea()
                    .zIndex(1)
            }

            // Escalation overlay — shown when AlarmKit alarm is dismissed
            if let countdown = orchestrator.escalationCountdown {
                EscalationCountdownOverlay(countdown: countdown)
                    .ignoresSafeArea()
                    .zIndex(2)
                    .transition(.opacity)
            }

            // Success overlay — shown when user gets up (during countdown or after device alarm)
            if orchestrator.successState {
                SuccessOverlay()
                    .ignoresSafeArea()
                    .zIndex(3)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: orchestrator.escalationCountdown != nil)
        .animation(.easeInOut(duration: 0.4), value: orchestrator.successState)
    }
}

// MARK: - Escalation Countdown Overlay

private struct EscalationCountdownOverlay: View {
    let countdown: Int

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                Text("Get out of bed.")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)

                Text("\(countdown)")
                    .font(.system(size: 140, weight: .black, design: .rounded))
                    .foregroundStyle(countdown <= 3 ? .red : .white)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: countdown)

                Text("Device alarm arms in \(countdown) second\(countdown == 1 ? "" : "s").")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))

                Spacer()
                Spacer()
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
        }
    }
}

// MARK: - Success Overlay

private struct SuccessOverlay: View {
    @State private var scale: CGFloat = 0.6
    @State private var opacity: Double = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()

            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.2))
                        .frame(width: 120, height: 120)
                    Image(systemName: "checkmark")
                        .font(.system(size: 52, weight: .bold))
                        .foregroundStyle(.green)
                }
                .scaleEffect(scale)

                Text("You're up!")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Great job getting out of bed.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .opacity(opacity)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.65)) {
                scale = 1.0
                opacity = 1.0
            }
        }
    }
}

@Observable
final class TabRouter {
    var selectedTab: String = "today"
}

struct MainTabView: View {
    @State private var router = TabRouter()

    var body: some View {
        TabView(selection: $router.selectedTab) {
            Tab("Today", systemImage: "sun.horizon.fill", value: "today") {
                TodayView()
            }
            Tab("Insights", systemImage: "chart.bar.fill", value: "insights") {
                SleepView()
            }
            Tab("MyEveil", systemImage: "sensor.tag.radiowaves.forward.fill", value: "device") {
                DeviceView()
            }
        }
        .environment(router)
    }
}

#Preview("Onboarding") {
    OnboardingView()
}

#Preview("Main App") {
    let schema = Schema([SleepSession.self, AlarmConfig.self, CalibrationProfile.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])
    MainTabView()
        .modelContainer(container)
}
