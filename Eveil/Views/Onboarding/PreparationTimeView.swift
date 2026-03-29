import SwiftUI

struct PreparationTimeView: View {
    let onBack:     (() -> Void)?
    let onContinue: (Int) -> Void

    @State private var minutes: Int = 60

    private let minMinutes = 15
    private let maxMinutes = 120
    private let step       = 5

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.05, blue: 0.08).ignoresSafeArea()

            // Warm amber glow
            RadialGradient(
                colors: [
                    Color(red: 0.80, green: 0.50, blue: 0.05).opacity(0.45),
                    Color(red: 0.55, green: 0.28, blue: 0.02).opacity(0.15),
                    Color.clear
                ],
                center: UnitPoint(x: 0.5, y: 1.2),
                startRadius: 20,
                endRadius: 500
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {

                // Top bar
                HStack {
                    if let onBack {
                        OnboardingBackButton(action: onBack)
                    } else {
                        Color.clear.frame(width: 42, height: 42)
                    }
                    Spacer()
                    OnboardingStepIndicator(current: 4, total: 4)
                }
                .padding(.horizontal, 24)
                .padding(.top, 56)

                // Question
                Text("How much time do you typically need between waking up and leaving?")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)
                    .lineSpacing(3)
                    .padding(.horizontal, 24)
                    .padding(.top, 28)

                Spacer()

                // Rotary dial
                RotaryDial(
                    minutes:    $minutes,
                    minMinutes: minMinutes,
                    maxMinutes: maxMinutes,
                    step:       step
                )
                .frame(height: 300)
                .padding(.horizontal, 24)

                Spacer()
            }

            // Continue button
            VStack {
                Spacer()
                Button { onContinue(minutes) } label: {
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

// MARK: - Rotary Dial

private struct RotaryDial: View {
    @Binding var minutes: Int
    let minMinutes: Int
    let maxMinutes: Int
    let step: Int

    // Total angular sweep of the dial (e.g. 270° like a real potentiometer)
    private let sweepDeg: Double = 270

    @State private var lastAngle: Double? = nil
    /// Continuous (unsnapped) accumulator so sub-step drag movements don't get dropped.
    @State private var rawValue: Double = 60
    @State private var isDragging = false

    private let haptic = UIImpactFeedbackGenerator(style: .light)

    private var normalized: Double {
        Double(minutes - minMinutes) / Double(maxMinutes - minMinutes)
    }

    private var faceRotation: Double {
        135 - normalized * sweepDeg
    }

    var body: some View {
        GeometryReader { geo in
            let side       = min(geo.size.width, geo.size.height)
            let faceRadius = side * 0.36
            let ringRadius = faceRadius + 22
            let cx         = geo.size.width  / 2
            let cy         = geo.size.height / 2
            let center     = CGPoint(x: cx, y: cy)

            ZStack {
                ProgressRing(normalized: normalized, radius: ringRadius, sweepDeg: sweepDeg)
                    .frame(width: geo.size.width, height: geo.size.height)

                Image(systemName: "arrowtriangle.down.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .offset(y: -(ringRadius + 12))

                DialFace(
                    radius:   faceRadius,
                    steps:    (maxMinutes - minMinutes) / step,
                    sweepDeg: sweepDeg
                )
                .rotationEffect(.degrees(faceRotation))
                // No spring during drag — direct follow. Spring only on release snap.
                .animation(isDragging ? .none : .spring(response: 0.18, dampingFraction: 0.82), value: minutes)

                VStack(spacing: 3) {
                    Text("\(minutes)")
                        .font(.system(size: 58, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: minutes)
                    Text("min")
                        .font(.system(size: 16, weight: .light))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if lastAngle == nil {
                            // Sync accumulator to current snapped value at drag start
                            rawValue = Double(minutes)
                            isDragging = true
                            haptic.prepare()
                        }
                        handleDrag(location: drag.location, center: center)
                    }
                    .onEnded { _ in
                        lastAngle = nil
                        isDragging = false
                    }
            )
        }
    }

    private func handleDrag(location: CGPoint, center: CGPoint) {
        let dx = location.x - center.x
        let dy = location.y - center.y
        let angle = Darwin.atan2(Double(dx), Double(-dy)) * 180 / Double.pi

        if let prev = lastAngle {
            var delta = angle - prev
            if delta >  180 { delta -= 360 }
            if delta < -180 { delta += 360 }

            // Accumulate into rawValue — fractional changes are preserved across frames
            let valueDelta = delta / sweepDeg * Double(maxMinutes - minMinutes)
            rawValue = max(Double(minMinutes), min(Double(maxMinutes), rawValue + valueDelta))

            let snapped = Int(round(rawValue / Double(step))) * step
            if snapped != minutes {
                haptic.impactOccurred()
                minutes = snapped
            }
        }
        lastAngle = angle
    }
}

// MARK: - Progress Ring (fixed, shows filled arc)

private struct ProgressRing: View {
    let normalized: Double
    let radius:     CGFloat
    let sweepDeg:   Double

    var body: some View {
        Canvas { ctx, sz in
            let c = CGPoint(x: sz.width / 2, y: sz.height / 2)

            // Track arc: from -135° to +135° from top
            // In SwiftUI Path angles: 0° = 3 o'clock, CW with `clockwise: false` (y-flip)
            // -135° from top (CW) = top - 135° = -90° - 135° = -225°
            // +135° from top (CW) = top + 135° = -90° + 135° = 45°
            var track = Path()
            track.addArc(center: c, radius: radius,
                         startAngle: .degrees(-225),
                         endAngle:   .degrees(45),
                         clockwise: false)
            ctx.stroke(track,
                       with: .color(.white.opacity(0.10)),
                       style: StrokeStyle(lineWidth: 5, lineCap: .round))

            // Filled arc
            guard normalized > 0 else { return }
            var fill = Path()
            fill.addArc(center: c, radius: radius,
                        startAngle: .degrees(-225),
                        endAngle:   .degrees(-225 + normalized * sweepDeg),
                        clockwise: false)
            ctx.stroke(fill,
                       with: .color(Color(red: 0.92, green: 0.68, blue: 0.22).opacity(0.8)),
                       style: StrokeStyle(lineWidth: 5, lineCap: .round))

            // Dot at current position
            let endRad = (-225 + normalized * sweepDeg) * Double.pi / 180
            let dot = CGPoint(
                x: c.x + radius * Darwin.cos(endRad),
                y: c.y + radius * Darwin.sin(endRad)
            )
            ctx.fill(
                Path(ellipseIn: CGRect(x: dot.x - 5, y: dot.y - 5, width: 10, height: 10)),
                with: .color(Color(red: 0.92, green: 0.68, blue: 0.22))
            )
        }
    }
}

// MARK: - Dial Face (rotates)

private struct DialFace: View {
    let radius:   CGFloat
    let steps:    Int
    let sweepDeg: Double

    var body: some View {
        ZStack {
            // Background with subtle 3-D gradient
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(white: 0.22),
                            Color(white: 0.11)
                        ],
                        center: .init(x: 0.38, y: 0.32),
                        startRadius: 0,
                        endRadius: radius
                    )
                )
                .shadow(color: .black.opacity(0.55), radius: 24, y: 8)

            // Thin rim
            Circle()
                .stroke(.white.opacity(0.08), lineWidth: 1)

            // Tick marks drawn via Canvas so they rotate with the face
            Canvas { ctx, sz in
                let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
                let r = sz.width / 2

                for i in 0...steps {
                    let t      = Double(i) / Double(steps)
                    // Angle on face: -sweepDeg/2 to +sweepDeg/2, from top, CW
                    let deg    = -sweepDeg / 2 + t * sweepDeg
                    let rad    = deg * Double.pi / 180

                    // CW-from-top → screen coords
                    let dx = Darwin.sin(rad)
                    let dy = -Darwin.cos(rad)

                    let isMajor  = i % 3 == 0
                    let tickLen: CGFloat = isMajor ? 18 : 9
                    let opacity: Double  = isMajor ? 0.70 : 0.22
                    let lineW:   CGFloat = isMajor ? 2.0  : 1.2

                    let outerR = r - 6
                    let innerR = outerR - tickLen

                    let outer = CGPoint(x: c.x + outerR * dx, y: c.y + outerR * dy)
                    let inner = CGPoint(x: c.x + innerR * dx, y: c.y + innerR * dy)

                    var path = Path()
                    path.move(to: inner)
                    path.addLine(to: outer)
                    ctx.stroke(path,
                               with: .color(.white.opacity(opacity)),
                               style: StrokeStyle(lineWidth: lineW, lineCap: .round))
                }
            }
        }
        .frame(width: radius * 2, height: radius * 2)
    }
}

#Preview {
    PreparationTimeView(onBack: nil) { _ in }
}
