import SwiftUI
import EventKit
import UserNotifications

// MARK: - Flow coordinator
//
// Post-sign-in onboarding: Name → Age → Struggles → PrepTime → Calendar → Notifications
//

struct PermissionsView: View {
    @AppStorage("hasCompletedOnboarding")   private var hasCompletedOnboarding   = false
    @AppStorage("userName")                 private var userName                  = ""
    @AppStorage("userAge")                  private var userAge                   = 0
    @AppStorage("morningStruggles")         private var morningStrugglesStr       = ""
    @AppStorage("preparationBufferMinutes") private var preparationBufferMinutes  = 60

    @State private var step = 0

    var body: some View {
        ZStack {
            if step == 0 {
                NameInputView(onBack: nil) { name in
                    userName = name
                    advance()
                }
                .transition(forwardTransition)
            } else if step == 1 {
                GreetingTransitionView(userName: userName) { advance() }
                    .transition(.opacity)
            } else if step == 2 {
                AgeInputView(onBack: { retreat() }) { age in
                    userAge = age
                    advance()
                }
                .transition(forwardTransition)
            } else if step == 3 {
                MorningStrugglesView(userName: userName, onBack: { retreat() }) { selected in
                    morningStrugglesStr = selected.sorted().map(String.init).joined(separator: ",")
                    advance()
                }
                .transition(forwardTransition)
            } else if step == 4 {
                PreparationTimeView(onBack: { retreat() }) { minutes in
                    preparationBufferMinutes = minutes
                    advance()
                }
                .transition(forwardTransition)
            } else if step == 5 {
                CalendarPermissionScreen(onBack: { retreat() }, onContinue: { advance() })
                    .transition(forwardTransition)
            } else {
                NotificationsPermissionScreen(onBack: { retreat() }) {
                    hasCompletedOnboarding = true
                }
                .transition(forwardTransition)
            }
        }
        .animation(.easeInOut(duration: 0.38), value: step)
        .preferredColorScheme(.dark)
    }

    private var forwardTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing),
            removal:   .move(edge: .leading)
        )
    }

    private func advance() { withAnimation(.easeInOut(duration: 0.38)) { step += 1 } }
    private func retreat() { withAnimation(.easeInOut(duration: 0.38)) { step -= 1 } }
}

// MARK: - Calendar Screen

private struct CalendarPermissionScreen: View {
    let onBack:     () -> Void
    let onContinue: () -> Void
    @State private var granted = false
    @State private var loading = false

    var body: some View {
        PermissionScreenLayout(
            iconName:    "calendar",
            iconColor:   Color(red: 0.95, green: 0.4, blue: 0.3),
            title:       "Know when\nyou need to wake",
            description: "Éveil reads your first event each morning to calculate the latest you can sleep in — automatically, without you setting a single alarm.",
            isGranted:   granted,
            isLoading:   loading,
            allowLabel:  "Allow Calendar Access",
            skipLabel:   "Set alarms manually",
            onAllow: {
                loading = true
                let store = EKEventStore()
                if #available(iOS 17, *) {
                    granted = (try? await store.requestFullAccessToEvents()) ?? false
                } else {
                    granted = await withCheckedContinuation { cont in
                        store.requestAccess(to: .event) { ok, _ in cont.resume(returning: ok) }
                    }
                }
                loading = false
                if granted {
                    try? await Task.sleep(for: .milliseconds(600))
                    onContinue()
                }
            },
            onSkip: onContinue,
            onBack: onBack
        )
    }
}

// MARK: - Notifications Screen

private struct NotificationsPermissionScreen: View {
    let onBack:     () -> Void
    let onContinue: () -> Void
    @State private var granted = false
    @State private var loading = false

    var body: some View {
        PermissionScreenLayout(
            iconName:    "bell.fill",
            iconColor:   Color(red: 0.45, green: 0.45, blue: 1.0),
            title:       "Get your morning\nbriefing",
            description: "The moment you leave bed, Éveil sends your first event, the weather, and last night's sleep summary — one notification, no noise.",
            isGranted:   granted,
            isLoading:   loading,
            allowLabel:  "Allow Notifications",
            skipLabel:   "Skip for now",
            onAllow: {
                loading = true
                granted = (try? await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
                loading = false
                try? await Task.sleep(for: .milliseconds(600))
                onContinue()
            },
            onSkip: onContinue,
            onBack: onBack
        )
    }
}

// MARK: - Shared permission layout (calendar & notifications only)

private struct PermissionScreenLayout: View {
    let iconName:    String
    let iconColor:   Color
    let title:       String
    let description: String
    let isGranted:   Bool
    let isLoading:   Bool
    let allowLabel:  String
    let skipLabel:   String
    let onAllow:     () async -> Void
    let onSkip:      () -> Void
    let onBack:      () -> Void

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.06, blue: 0.10).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {

                // Top bar — back only, no step counter (permissions are the finish line)
                HStack {
                    OnboardingBackButton(action: onBack)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 56)

                // Title
                Text(title)
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.white)
                    .lineSpacing(3)
                    .padding(.horizontal, 24)
                    .padding(.top, 36)

                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.4))
                    .lineSpacing(5)
                    .padding(.horizontal, 24)
                    .padding(.top, 14)

                Spacer()

                // Icon
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.07))
                        .frame(width: 180, height: 180)
                    Circle()
                        .fill(iconColor.opacity(0.04))
                        .frame(width: 230, height: 230)
                    Image(systemName: iconName)
                        .font(.system(size: 56, weight: .medium))
                        .foregroundStyle(iconColor.opacity(0.9))
                }
                .frame(maxWidth: .infinity)

                Spacer()

                // Buttons
                VStack(spacing: 16) {
                    Button {
                        Task { await onAllow() }
                    } label: {
                        ZStack {
                            if isLoading {
                                ProgressView().tint(.black)
                            } else if isGranted {
                                Label("Access Granted", systemImage: "checkmark")
                                    .font(.headline)
                                    .foregroundStyle(.black)
                            } else {
                                Text(allowLabel)
                                    .font(.headline)
                                    .foregroundStyle(.black)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(isGranted ? Color.green : .white)
                        .animation(.easeInOut(duration: 0.2), value: isGranted)
                    }
                    .disabled(isLoading || isGranted)
                    .padding(.horizontal, 24)

                    Button(action: onSkip) {
                        Text(skipLabel)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.28))
                    }
                    .padding(.bottom, 4)
                }
                .padding(.bottom, 52)
            }
        }
    }
}

#Preview {
    PermissionsView()
}
