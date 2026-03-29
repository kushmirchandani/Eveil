import SwiftUI

struct LaunchScreenView: View {
    var onComplete: () -> Void

    @State private var opacity: Double = 1
    private let totalDuration: Double = 2.4
    private let haptic = UIImpactFeedbackGenerator(style: .heavy)

    var body: some View {
        ZStack {
            Image("background-1")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            Color.black.opacity(0.18).ignoresSafeArea()

            // Wave dot field
            TimelineView(.animation) { tl in
                Canvas { ctx, size in
                    let t  = tl.date.timeIntervalSinceReferenceDate
                    let cx = size.width  / 2
                    let cy = size.height / 2
                    let maxDist = hypot(cx, cy)

                    let cols = 12
                    let rows = 22
                    let dx   = size.width  / CGFloat(cols)
                    let dy   = size.height / CGFloat(rows)

                    for r in 0..<rows {
                        for c in 0..<cols {
                            let x    = (CGFloat(c) + 0.5) * dx
                            let y    = (CGFloat(r) + 0.5) * dy
                            let dist = hypot(x - cx, y - cy) / maxDist

                            // Sharp pulse wave radiating from center
                            // pow() makes it a tight ring rather than a broad swell
                            let phase = t * 2.2 - dist * 3.8
                            let raw   = sin(phase * .pi)
                            let v     = pow(max(0, raw), 2.5)

                            // Secondary echo wave, slightly behind
                            let phase2 = t * 2.2 - dist * 3.8 - 1.0
                            let v2     = pow(max(0, sin(phase2 * .pi)), 2.5) * 0.35

                            let total  = min(v + v2, 1)
                            let alpha  = 0.05 + total * 0.72
                            let radius = 1.3  + total * 3.0

                            ctx.fill(
                                Path(ellipseIn: CGRect(
                                    x: x - radius, y: y - radius,
                                    width: radius * 2, height: radius * 2
                                )),
                                with: .color(.white.opacity(alpha))
                            )
                        }
                    }
                }
            }
        }
        .opacity(opacity)
        .onAppear {
            haptic.prepare()
            scheduleHaptics()
            scheduleExit()
        }
    }

    // MARK: - Haptic rhythm

    private func scheduleHaptics() {
        // Fire with the approximate wave period (~0.45s) for a pulse feel
        let period = 0.45
        let count  = Int(totalDuration / period)
        for i in 0..<count {
            let delay     = Double(i) * period
            let intensity = i % 2 == 0 ? 1.0 : 0.75
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                haptic.impactOccurred(intensity: intensity)
            }
        }
    }

    // MARK: - Exit

    private func scheduleExit() {
        DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration - 0.35) {
            withAnimation(.easeIn(duration: 0.35)) { opacity = 0 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration) {
            onComplete()
        }
    }
}
