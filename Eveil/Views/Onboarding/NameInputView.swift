import SwiftUI

// MARK: - Shared step indicator (used across all onboarding screens)

struct OnboardingStepIndicator: View {
    let current: Int
    let total:   Int

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.15), lineWidth: 1.5)
            Circle()
                .trim(from: 0, to: CGFloat(current) / CGFloat(total))
                .stroke(.white.opacity(0.65), lineWidth: 1.5)
                .rotationEffect(.degrees(-90))
            Text("\(current) of \(total)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(width: 58, height: 58)
    }
}

// MARK: - Shared back button builder

struct OnboardingBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(.white.opacity(0.08))
                .clipShape(Circle())
        }
    }
}

// MARK: - Name Input

struct NameInputView: View {
    let onBack:     (() -> Void)?
    let onContinue: (String) -> Void

    @State private var name = ""
    @FocusState private var focused: Bool

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.06, blue: 0.10).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {

                // Top bar
                HStack {
                    if let onBack {
                        OnboardingBackButton(action: onBack)
                    } else {
                        Color.clear.frame(width: 42, height: 42)
                    }
                    Spacer()
                    OnboardingStepIndicator(current: 1, total: 4)
                }
                .padding(.horizontal, 24)
                .padding(.top, 56)

                // Title
                Text("What's your\nname?")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.white)
                    .lineSpacing(3)
                    .padding(.horizontal, 24)
                    .padding(.top, 36)

                Text("We'll use it to personalize your experience.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.horizontal, 24)
                    .padding(.top, 14)

                Spacer()

                // Input
                VStack(alignment: .leading, spacing: 10) {
                    TextField("", text: $name,
                              prompt: Text("Your first name")
                                  .foregroundStyle(.white.opacity(0.22)))
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.white)
                        .focused($focused)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit { if !trimmed.isEmpty { onContinue(trimmed) } }

                    Rectangle()
                        .fill(.white.opacity(trimmed.isEmpty ? 0.15 : 0.45))
                        .frame(height: 1)
                        .animation(.easeInOut(duration: 0.2), value: trimmed.isEmpty)
                }
                .padding(.horizontal, 24)

                Spacer()

                // Continue
                Button { if !trimmed.isEmpty { onContinue(trimmed) } } label: {
                    Text("Continue")
                        .font(.headline)
                        .foregroundStyle(trimmed.isEmpty ? Color.black.opacity(0.35) : .black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(trimmed.isEmpty ? Color.white.opacity(0.35) : .white)
                        .animation(.easeInOut(duration: 0.2), value: trimmed.isEmpty)
                }
                .disabled(trimmed.isEmpty)
                .padding(.horizontal, 24)
                .padding(.bottom, 52)
            }
        }
        .onAppear { focused = true }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    NameInputView(onBack: nil) { _ in }
}
