import SwiftUI

struct AgeInputView: View {
    let onBack:     () -> Void
    let onContinue: (Int) -> Void

    @State private var age:      Int    = 25
    @State private var baseAge:  Int    = 25
    @State private var typing:   Bool   = false
    @State private var typedText: String = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.06, blue: 0.10).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                // Top bar
                HStack {
                    OnboardingBackButton(action: onBack)
                    Spacer()
                    OnboardingStepIndicator(current: 2, total: 4)
                }
                .padding(.horizontal, 24)
                .padding(.top, 56)

                // Title
                Text("How old\nare you?")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.white)
                    .lineSpacing(3)
                    .padding(.horizontal, 24)
                    .padding(.top, 36)

                Text("Helps us understand your sleep and wake patterns.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.4))
                    .lineSpacing(4)
                    .padding(.horizontal, 24)
                    .padding(.top, 14)

                Spacer()

                // Age drum / type toggle
                VStack(spacing: 12) {
                    if typing {
                        // Keyboard input mode
                        ZStack(alignment: .center) {
                            TextField("", text: $typedText)
                                .font(.system(size: 104, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .monospacedDigit()
                                .multilineTextAlignment(.center)
                                .keyboardType(.numberPad)
                                .focused($inputFocused)
                                .frame(maxWidth: .infinity)
                                .onChange(of: typedText) { _, val in
                                    // strip non-digits, cap at 2 chars
                                    let digits = val.filter(\.isNumber)
                                    typedText = String(digits.prefix(2))
                                }
                                .toolbar {
                                    ToolbarItemGroup(placement: .keyboard) {
                                        Spacer()
                                        Button("Done") { commitTyped() }
                                            .foregroundStyle(.white)
                                    }
                                }
                        }
                        .frame(height: 120)

                        Text("tap Done when finished")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.22))

                    } else {
                        // Scroll drag mode
                        HStack(alignment: .center, spacing: 0) {
                            Text("\(age)")
                                .font(.system(size: 104, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .monospacedDigit()
                                .contentTransition(.numericText())
                                .animation(.spring(response: 0.2, dampingFraction: 0.8), value: age)

                            VStack(spacing: 6) {
                                Image(systemName: "chevron.up")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.4))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                            .padding(.leading, 10)
                            .padding(.top, 8)
                        }
                        .gesture(
                            DragGesture()
                                .onChanged { drag in
                                    let yearDelta = -Int(drag.translation.height / 11)
                                    let clamped   = max(13, min(99, baseAge + yearDelta))
                                    if clamped != age {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        age = clamped
                                    }
                                }
                                .onEnded { drag in
                                    baseAge = max(13, min(99, baseAge + -Int(drag.translation.height / 11)))
                                    age     = baseAge
                                }
                        )
                        .onTapGesture { enterTypingMode() }
                        .frame(maxWidth: .infinity, alignment: .center)

                        Text("drag up or down  ·  tap to type")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.22))
                    }
                }

                Spacer()

                Button {
                    if typing { commitTyped() }
                    onContinue(age)
                } label: {
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
        .onTapGesture {
            if typing { commitTyped() }
        }
    }

    private func enterTypingMode() {
        typedText = "\(age)"
        typing = true
        inputFocused = true
    }

    private func commitTyped() {
        if let parsed = Int(typedText) {
            age = max(13, min(99, parsed))
            baseAge = age
        }
        typedText = ""
        typing = false
        inputFocused = false
    }
}

#Preview {
    AgeInputView(onBack: {}) { _ in }
}
