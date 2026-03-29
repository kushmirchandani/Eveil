import SwiftUI

/// Full-screen greeting shown between the name step and the age step.
/// Auto-advances after a short pause — no user interaction needed.
struct GreetingTransitionView: View {
    let userName:  String
    let onFinish:  () -> Void

    @State private var visible = false

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.06, blue: 0.10).ignoresSafeArea()

            VStack(spacing: 14) {
                Text("Great to meet you,")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(.white.opacity(0.55))
                Text(userName)
                    .font(.system(size: 52, weight: .bold, design: .default))
                    .foregroundStyle(.white)
                    .tracking(1)
            }
            .opacity(visible ? 1 : 0)
            .scaleEffect(visible ? 1 : 0.96)
        }
        .onAppear {
            // Fade in
            withAnimation(.easeOut(duration: 0.45)) { visible = true }
            // Fade out and advance
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                withAnimation(.easeIn(duration: 0.35)) { visible = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    onFinish()
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    GreetingTransitionView(userName: "Kush") {}
}
