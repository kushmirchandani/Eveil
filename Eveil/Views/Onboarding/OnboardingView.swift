import SwiftUI
import AuthenticationServices

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showPermissions = false

    private var videoURL: URL? {
        Bundle.main.url(forResource: "onboarding", withExtension: "mp4")
    }

    var body: some View {
        ZStack {
            // Video background
            if let url = videoURL {
                LoopingVideoPlayer(url: url)
                    .ignoresSafeArea()
            } else {
                // Fallback during development before video is added
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.05, green: 0.05, blue: 0.15), Color(red: 0.1, green: 0.05, blue: 0.25)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .ignoresSafeArea()
            }

            // Gradient scrim — heavier at bottom for legibility
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.1), location: 0),
                    .init(color: .black.opacity(0.3), location: 0.4),
                    .init(color: .black.opacity(0.85), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Hero text — anchored near the top
                VStack(spacing: 12) {
                    Text("Éveil")
                        .font(.system(size: 48, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .tracking(8)

                    Text("The alarm that only stops\nwhen you leave the bed.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
                .padding(.top, 80)

                Spacer()

                // Bottom CTA
                VStack(spacing: 16) {
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        switch result {
                        case .success:
                            showPermissions = true
                        case .failure:
                            break
                        }
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 54)
                    .clipShape(Rectangle())
                    .padding(.horizontal, 24)

                    Text("By continuing you agree to our Privacy Policy.")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.4))
                }
                .padding(.bottom, 52)
            }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showPermissions) {
            PermissionsView()
        }
    }
}

#Preview {
    OnboardingView()
}
