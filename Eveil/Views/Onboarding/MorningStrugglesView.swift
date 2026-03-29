import SwiftUI

struct MorningStrugglesView: View {
    let userName:   String
    let onBack:     () -> Void
    let onContinue: (Set<Int>) -> Void

    @State private var selected: Set<Int> = []

    private let struggles = [
        "I hit snooze repeatedly without realizing it",
        "I wake up but can't make myself get out of bed",
        "I sleep through alarms entirely",
        "I feel disoriented or groggy for a long time after waking",
        "I'm fine once I'm up — but the getting up part is the battle"
    ]

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.06, blue: 0.10).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {

                // Top bar
                HStack {
                    OnboardingBackButton(action: onBack)
                    Spacer()
                    OnboardingStepIndicator(current: 3, total: 4)
                }
                .padding(.horizontal, 24)
                .padding(.top, 56)

                // Title
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(userName),")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(.white.opacity(0.4))
                    Text("let's customize\nyour experience")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(.white)
                        .lineSpacing(3)
                }
                .padding(.horizontal, 24)
                .padding(.top, 32)

                Text("What makes mornings hard for you? Select all that apply.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.4))
                    .lineSpacing(4)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)

                // Option list
                VStack(spacing: 0) {
                    ForEach(struggles.indices, id: \.self) { i in
                        StruggleRow(
                            text: struggles[i],
                            isSelected: selected.contains(i)
                        ) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                if selected.contains(i) {
                                    selected.remove(i)
                                } else {
                                    selected.insert(i)
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }
                            }
                        }

                        if i < struggles.count - 1 {
                            Rectangle()
                                .fill(.white.opacity(0.07))
                                .frame(height: 1)
                                .padding(.horizontal, 24)
                        }
                    }
                }
                .padding(.top, 20)

                Spacer()

                // Continue — always enabled (skip is valid)
                Button { onContinue(selected) } label: {
                    Text("Continue")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(.white)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 52)
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct StruggleRow: View {
    let text:       String
    let isSelected: Bool
    let onTap:      () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                Text(text)
                    .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.5))
                    .multilineTextAlignment(.leading)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ZStack {
                    Circle()
                        .stroke(.white.opacity(isSelected ? 0 : 0.2), lineWidth: 1.5)
                        .frame(width: 26, height: 26)
                    Circle()
                        .fill(isSelected ? Color.white : .clear)
                        .frame(width: 26, height: 26)
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.black)
                        .opacity(isSelected ? 1 : 0)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    MorningStrugglesView(userName: "Kush", onBack: {}) { _ in }
}
