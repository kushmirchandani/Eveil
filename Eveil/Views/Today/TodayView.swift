import SwiftUI
import SwiftData
import EventKit

struct TodayView: View {
    @Query private var sessions: [SleepSession]
    @Query private var configs: [AlarmConfig]

    private var lastSession: SleepSession? { sessions.sorted { $0.date > $1.date }.first }
    private var config: AlarmConfig? { configs.first }

    @AppStorage("userName") private var userName = ""
    @State private var nextEvent: EKEvent?
    @State private var tomorrowEvents: [EKEvent] = []
    @State private var sleepSamples: [SleepStageSample] = []
    @State private var calendarDenied = false
    @State private var showSettings = false
    @State private var showEventPicker = false
    @State private var showBufferAdjuster = false
    @State private var eventStore = EKEventStore()
    @State private var isEstimatingBuffer = false
    @State private var aiReasoning: String = ""

    private var bufferBinding: Binding<Int> {
        Binding(
            get: { config?.preparationBufferMinutes ?? 60 },
            set: { config?.preparationBufferMinutes = $0 }
        )
    }

    private var firstName: String {
        userName.components(separatedBy: " ").first ?? userName
    }

    /// Before 6am we're still in the previous day's context (late night / early wake).
    private var effectiveDate: Date {
        let hour = Calendar.current.component(.hour, from: .now)
        if hour < 6 {
            return Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        }
        return .now
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let salutation: String
        switch hour {
        case 5..<12:  salutation = "Good morning"
        case 12..<17: salutation = "Good afternoon"
        default:      salutation = "Good evening"
        }
        return firstName.isEmpty ? "\(salutation)." : "\(salutation), \(firstName)."
    }

    private var isShowingMorningBriefing: Bool {
        let h = Calendar.current.component(.hour, from: .now)
        return h >= 5 && h < 11
    }

    // Alarm time: calendar-derived if available, else config
    private var alarmDate: Date? {
        guard let config, config.isEnabled else { return nil }
        if config.calendarSyncEnabled, let event = nextEvent {
            return event.startDate.addingTimeInterval(-Double(config.preparationBufferMinutes * 60))
        }
        return config.earliestWakeDate
    }

    var body: some View {
        ZStack {
            // Background
            Image("background-1")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            // Top scrim
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.88), location: 0.0),
                    .init(color: .black.opacity(0.4),  location: 0.45),
                    .init(color: .clear,               location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Bottom scrim behind chart
            LinearGradient(
                stops: [
                    .init(color: .clear,               location: 0.0),
                    .init(color: .black.opacity(0.65), location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Narrative content — top
            VStack(alignment: .leading, spacing: 22) {

                // Settings button
                HStack {
                    Spacer()
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(11)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                .padding(.bottom, -8)

                // Date + greeting
                VStack(alignment: .leading, spacing: 6) {
                    Text(effectiveDate, format: .dateTime.weekday(.wide).month(.wide).day())
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.45))

                    Text(greeting)
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white)
                }

                // Morning briefing sentence
                if isShowingMorningBriefing, let session = lastSession {
                    morningBriefingSentence(session)
                        .font(.system(size: 19))
                        .lineSpacing(10)
                }

                // Main narrative sentence
                mainNarrativeSentence
                    .animation(.spring(response: 0.4, dampingFraction: 0.85), value: alarmDate)
                    .animation(.spring(response: 0.4, dampingFraction: 0.85), value: nextEvent?.eventIdentifier)

                // AI streaming reasoning card
                if !aiReasoning.isEmpty {
                    Text(aiReasoning)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineSpacing(5)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            // Sleep chart + device status — bottom
            VStack(alignment: .leading, spacing: 10) {
                Spacer()

                if !sleepSamples.isEmpty {
                    SleepNightChartCard(samples: sleepSamples)
                }

                DeviceStatusLine()
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 36)
        }
        .task {
            await loadNextEvent()
            sleepSamples = await HealthKitManager.shared.fetchLastNightStageSamples()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showEventPicker) {
            EventDaySheet(events: tomorrowEvents, selected: $nextEvent)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
                .presentationCornerRadius(32)
        }
        .onChange(of: showEventPicker) { _, isShowing in
            if isShowing { Task { await loadNextEvent() } }
        }
        .onChange(of: nextEvent?.eventIdentifier) { old, new in
            // Re-estimate when user explicitly picks a different event (not on initial nil→first load,
            // which is handled inside loadNextEvent)
            guard old != nil, new != nil, let event = nextEvent else { return }
            Task { await applyAIBufferEstimate(for: event) }
        }
        .sheet(isPresented: $showBufferAdjuster) {
            if let eventStart = nextEvent?.startDate {
                WakeTimeAdjusterSheet(bufferMinutes: bufferBinding, eventStart: eventStart)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(.ultraThinMaterial)
                    .presentationCornerRadius(32)
            }
        }
    }

    // MARK: - Sentences

    @ViewBuilder
    private var mainNarrativeSentence: some View {
        let f = Color.white.opacity(0.5)
        let v = Color.white
        let a = Color.white.opacity(0.7)

        if let event = nextEvent {
            VStack(alignment: .leading, spacing: 14) {
                // Line 1 — event reference, tappable to change event
                eventLine(event: event, f: f, v: v, a: a)
                    .font(.system(size: 19))
                    .lineSpacing(10)
                    .onTapGesture { showEventPicker = true }

                // Line 2 — time + wake time (or dots while AI estimates)
                if isEstimatingBuffer, config?.isEnabled == true {
                    HStack(alignment: .lastTextBaseline, spacing: 3) {
                        timeLinePrefix(event: event, f: f, v: v, a: a)
                            .font(.system(size: 19))
                            .lineSpacing(10)
                        TypingDotsView()
                            .padding(.bottom, 3)
                    }
                    .onTapGesture { showBufferAdjuster = true }
                    .transition(.opacity)
                } else if config?.isEnabled == true, let alarmTime = alarmDate {
                    timeLine(event: event, alarmTime: alarmTime, f: f, v: v, a: a)
                        .font(.system(size: 19))
                        .lineSpacing(10)
                        .onTapGesture { showBufferAdjuster = true }
                        .transition(.opacity)
                } else {
                    (Text("at\u{00A0}").foregroundStyle(f)
                    + Text(Image(systemName: "clock.fill")).foregroundStyle(a)
                    + Text("\u{2060}").foregroundStyle(a)
                    + Text("\(formatted(event.startDate)).").foregroundStyle(v).bold())
                    .font(.system(size: 19))
                    .lineSpacing(10)
                }
            }
        } else if config?.isEnabled == true, let alarmTime = alarmDate {
            (Text("Nothing's scheduled tomorrow. Your alarm opens at\u{00A0}").foregroundStyle(f)
            + Text(Image(systemName: "alarm.fill")).foregroundStyle(a)
            + Text("\u{2060}").foregroundStyle(a)
            + Text("\(formatted(alarmTime)).").foregroundStyle(v).bold())
            .font(.system(size: 19))
            .lineSpacing(10)
        } else {
            Text("Your slate is clear tomorrow.")
                .font(.system(size: 19))
                .foregroundStyle(f)
                .lineSpacing(10)
        }
    }

    private func eventLine(event: EKEvent, f: Color, v: Color, a: Color) -> Text {
        var titleAttr = AttributedString(event.title ?? "Event")
        titleAttr.foregroundColor = v
        titleAttr.font = .boldSystemFont(ofSize: 19)
        titleAttr.underlineStyle = .single
        return Text("Your day tomorrow starts with ").foregroundStyle(f)
            + Text(Image(systemName: "calendar")).foregroundStyle(a)
            + Text("\u{2060}").foregroundStyle(a)
            + Text(titleAttr)
    }

    private func timeLine(event: EKEvent, alarmTime: Date, f: Color, v: Color, a: Color) -> Text {
        var wakeAttr = AttributedString("\(formatted(alarmTime)).")
        wakeAttr.foregroundColor = v
        wakeAttr.font = .boldSystemFont(ofSize: 19)
        wakeAttr.underlineStyle = .single
        return Text("at\u{00A0}").foregroundStyle(f)
            + Text(Image(systemName: "clock.fill")).foregroundStyle(a)
            + Text("\u{2060}").foregroundStyle(a)
            + Text("\(formatted(event.startDate)) ").foregroundStyle(v).bold()
            + Text("— wake at\u{00A0}").foregroundStyle(f)
            + Text(Image(systemName: "alarm.fill")).foregroundStyle(a)
            + Text("\u{2060}").foregroundStyle(a)
            + Text(wakeAttr)
    }

    private func morningBriefingSentence(_ session: SleepSession) -> Text {
        let f = Color.white.opacity(0.5)
        let v = Color.white
        let a = Color.white.opacity(0.7)
        if let duration = session.duration {
            return Text("You slept\u{00A0}").foregroundStyle(f)
                + Text(Image(systemName: "sparkles")).foregroundStyle(a)
                + Text("\u{2060}").foregroundStyle(a)
                + Text("\(duration.sleepFormatted) ").foregroundStyle(v).bold()
                + Text("last night.").foregroundStyle(f)
        }
        return Text("Welcome back.").foregroundStyle(f)
    }

    // MARK: - Helpers

    private func formatted(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        f.amSymbol = "AM"
        f.pmSymbol = "PM"
        return f.string(from: date)
    }

    private func applyAIBufferEstimate(for event: EKEvent) async {
        guard !isEstimatingBuffer else { return }
        withAnimation { isEstimatingBuffer = true }
        aiReasoning = ""

        let result = await WakeBufferEstimator.estimate(for: event, name: firstName)

        // Apply buffer while dots are still showing so the time is correct on reveal
        if let config { config.preparationBufferMinutes = result.minutes }

        // Dots → actual time
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            isEstimatingBuffer = false
        }

        // Skip typewriter if no reasoning came back
        guard !result.reasoning.isEmpty else { return }

        // Brief pause so the time reveal settles before reasoning card appears
        try? await Task.sleep(nanoseconds: 300_000_000)

        // Typewriter: append one character every 12 ms
        let chars = Array(result.reasoning)
        for i in chars.indices {
            try? await Task.sleep(nanoseconds: 12_000_000)
            withAnimation(.linear(duration: 0)) {
                aiReasoning = String(chars.prefix(i + 1))
            }
        }

        // Hold so user can read it
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        withAnimation(.easeOut(duration: 0.5)) { aiReasoning = "" }
    }

    // Returns the "at 🕐 time — wake at ⏰" prefix without the wake time itself.
    // Used to show the stub line while TypingDotsView replaces the actual time.
    private func timeLinePrefix(event: EKEvent, f: Color, v: Color, a: Color) -> Text {
        Text("at\u{00A0}").foregroundStyle(f)
        + Text(Image(systemName: "clock.fill")).foregroundStyle(a)
        + Text("\u{2060}").foregroundStyle(a)
        + Text("\(formatted(event.startDate)) ").foregroundStyle(v).bold()
        + Text("— wake at\u{00A0}").foregroundStyle(f)
        + Text(Image(systemName: "alarm.fill")).foregroundStyle(a)
    }

    private func loadNextEvent() async {
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .notDetermined {
            guard (try? await eventStore.requestFullAccessToEvents()) == true else {
                calendarDenied = true; return
            }
        } else if status == .denied || status == .restricted {
            calendarDenied = true; return
        }

        let cal = Calendar.current
        let tomorrowStart = cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: effectiveDate)!)
        let tomorrowEnd   = cal.date(byAdding: .day, value: 1, to: tomorrowStart)!
        let predicate = eventStore.predicateForEvents(withStart: tomorrowStart, end: tomorrowEnd, calendars: nil)
        let events = eventStore.events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
        tomorrowEvents = events
        if nextEvent == nil {
            nextEvent = events.first
            if let event = events.first {
                await applyAIBufferEstimate(for: event)
            }
        }
    }
}

// MARK: - Device Status Line

private struct DeviceStatusLine: View {
    @Environment(BLEManager.self) private var ble
    @Environment(TabRouter.self) private var router

    private var connected: Bool { ble.connectionState == .connected }

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(connected ? Color.green : Color.white.opacity(0.25))
                .frame(width: 6, height: 6)
            Text(connected ? "Device connected" : "Device not connected")
                .font(.footnote)
                .foregroundStyle(.white.opacity(connected ? 0.55 : 0.35))
            if !connected {
                Text("·")
                    .foregroundStyle(.white.opacity(0.25))
                Button {
                    router.selectedTab = "device"
                } label: {
                    Text("Set up")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white)
                }
            }
        }
    }
}

// MARK: - Sleep Night Chart

private struct SleepNightChartCard: View {
    let samples: [SleepStageSample]

    private let laneH: CGFloat   = 26
    private let labelW: CGFloat  = 58
    private let blockH: CGFloat  = 18
    private let cornerR: CGFloat = 5

    @State private var scrubX: CGFloat?
    @State private var scrubTime: Date?
    @State private var lastScrubIdx: Int?

    private let selectionFeedback = UISelectionFeedbackGenerator()
    private let impactFeedback    = UIImpactFeedbackGenerator(style: .light)

    private var timeRange: (start: Date, end: Date)? {
        guard let s = samples.first?.start, let e = samples.last?.end else { return nil }
        return (s, e)
    }

    private func minutesFor(_ stage: SleepStageSample.Stage) -> Double {
        samples.filter { $0.stage == stage }.reduce(0) { $0 + $1.duration / 60 }
    }

    private func durationLabel(_ mins: Double) -> String {
        let h = Int(mins) / 60; let m = Int(mins) % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "h:mma"
        f.amSymbol = "AM"; f.pmSymbol = "PM"
        return f.string(from: date)
    }

    private var chartH: CGFloat { laneH * 4 }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left labels column
            VStack(spacing: 0) {
                ForEach(SleepStageSample.Stage.allCases, id: \.rawValue) { stage in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(stage.label)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                        Text(durationLabel(minutesFor(stage)))
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.38))
                    }
                    .frame(width: labelW, height: laneH, alignment: .leading)
                }
            }

            // Chart area
            GeometryReader { geo in
                let w = geo.size.width

                ZStack(alignment: .topLeading) {
                    // Canvas — blocks, dividers, cursor
                    Canvas { ctx, size in
                        guard let range = timeRange else { return }
                        let totalSecs = range.end.timeIntervalSince(range.start)
                        guard totalSecs > 0 else { return }

                        func xFor(_ d: Date) -> CGFloat {
                            CGFloat(d.timeIntervalSince(range.start) / totalSecs) * size.width
                        }

                        // Dashed lane dividers
                        for i in 1..<4 {
                            let y = CGFloat(i) * laneH
                            var p = Path()
                            p.move(to: CGPoint(x: 0, y: y))
                            p.addLine(to: CGPoint(x: size.width, y: y))
                            ctx.stroke(p, with: .color(.white.opacity(0.09)),
                                       style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                        }

                        // Stage-transition connector lines
                        for i in 0..<(samples.count - 1) {
                            let a = samples[i], b = samples[i + 1]
                            guard a.stage != b.stage else { continue }
                            let x  = xFor(a.end)
                            let y1 = CGFloat(a.stage.rawValue) * laneH + laneH / 2
                            let y2 = CGFloat(b.stage.rawValue) * laneH + laneH / 2
                            var p = Path()
                            p.move(to: CGPoint(x: x, y: y1))
                            p.addLine(to: CGPoint(x: x, y: y2))
                            ctx.stroke(p, with: .color(.white.opacity(0.18)),
                                       style: StrokeStyle(lineWidth: 1.2))
                        }

                        // Stage blocks
                        for sample in samples {
                            let x   = xFor(sample.start)
                            let bw  = max(xFor(sample.end) - x, 3)
                            let by  = CGFloat(sample.stage.rawValue) * laneH + (laneH - blockH) / 2
                            let rect = CGRect(x: x, y: by, width: bw, height: blockH)
                            let path = Path(roundedRect: rect, cornerRadius: cornerR)
                            let c    = sample.stage.color

                            ctx.fill(path, with: .linearGradient(
                                Gradient(stops: [
                                    .init(color: c.opacity(0.5), location: 0),
                                    .init(color: c,              location: 1),
                                ]),
                                startPoint: CGPoint(x: rect.midX, y: rect.minY),
                                endPoint:   CGPoint(x: rect.midX, y: rect.maxY)
                            ))

                            // Top highlight
                            let gh = blockH * 0.3
                            let gRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: gh)
                            ctx.fill(Path(roundedRect: gRect,
                                         cornerRadii: RectangleCornerRadii(
                                            topLeading: cornerR, bottomLeading: 0,
                                            bottomTrailing: 0, topTrailing: cornerR)),
                                     with: .color(.white.opacity(0.11)))
                        }

                        // Scrub cursor
                        if let sx = scrubX {
                            var line = Path()
                            line.move(to: CGPoint(x: sx, y: 0))
                            line.addLine(to: CGPoint(x: sx, y: size.height))
                            ctx.stroke(line, with: .color(.white.opacity(0.75)),
                                       style: StrokeStyle(lineWidth: 1))

                            ctx.fill(Path(ellipseIn: CGRect(x: sx - 2.5, y: -2.5, width: 5, height: 5)),
                                     with: .color(.white))
                        }

                        // Time axis labels embedded in canvas
                        let labelY = size.height - 1
                        let startTxt = ctx.resolve(
                            Text(timeString(range.start))
                                .font(.system(size: 9))
                                .foregroundStyle(Color.white.opacity(0.35))
                        )
                        ctx.draw(startTxt, at: CGPoint(x: 0, y: labelY), anchor: .bottomLeading)

                        let endTxt = ctx.resolve(
                            Text(timeString(range.end))
                                .font(.system(size: 9))
                                .foregroundStyle(Color.white.opacity(0.35))
                        )
                        ctx.draw(endTxt, at: CGPoint(x: size.width, y: labelY), anchor: .bottomTrailing)
                    }
                    .frame(height: chartH + 14)

                    // Floating time label above cursor
                    if let sx = scrubX, let t = scrubTime {
                        Text(timeString(t))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.ultraThinMaterial, in: Capsule())
                            .offset(x: min(max(sx - 22, 0), w - 48), y: 0)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            let x = min(max(drag.location.x, 0), w)
                            if scrubX == nil {
                                impactFeedback.impactOccurred(intensity: 0.5)
                                selectionFeedback.prepare()
                            }
                            scrubX = x
                            if let range = timeRange {
                                scrubTime = range.start.addingTimeInterval(
                                    Double(x / w) * range.end.timeIntervalSince(range.start)
                                )
                                // Haptic tick on each new sample crossed
                                if let t = scrubTime,
                                   let idx = samples.firstIndex(where: { $0.start <= t && $0.end > t }),
                                   idx != lastScrubIdx {
                                    selectionFeedback.selectionChanged()
                                    lastScrubIdx = idx
                                }
                            }
                        }
                        .onEnded { _ in
                            withAnimation(.easeOut(duration: 0.25)) { scrubX = nil; scrubTime = nil }
                            lastScrubIdx = nil
                        }
                )
            }
            .frame(height: chartH + 14)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(in: .rect(cornerRadius: 18))
    }
}

// MARK: - Helpers

private extension TimeInterval {
    var sleepFormatted: String {
        let h = Int(self) / 3600
        let m = (Int(self) % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}

// MARK: - Event Day Sheet (timeline calendar)

private struct EventDaySheet: View {
    let events: [EKEvent]
    @Binding var selected: EKEvent?
    @Environment(\.dismiss) private var dismiss

    private let hourHeight: CGFloat = 64
    private let labelWidth: CGFloat = 48

    private var hourRange: ClosedRange<Int> {
        let cal = Calendar.current
        let starts = events.map { cal.component(.hour, from: $0.startDate) }
        let ends   = events.map { cal.component(.hour, from: $0.endDate) + 1 }
        let lo = (starts.min() ?? 7) - 1
        let hi = (ends.max()   ?? 20)
        return max(0, lo)...min(23, hi)
    }

    private func yOffset(for date: Date) -> CGFloat {
        let cal = Calendar.current
        let h = cal.component(.hour, from: date)
        let m = cal.component(.minute, from: date)
        return CGFloat(h - hourRange.lowerBound) * hourHeight + CGFloat(m) / 60 * hourHeight
    }

    private func eventHeight(for event: EKEvent) -> CGFloat {
        let dur = event.endDate.timeIntervalSince(event.startDate) / 3600
        return max(32, CGFloat(dur) * hourHeight)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                // Conversational header
                VStack(alignment: .leading, spacing: 6) {
                    Text("What's the earliest event")
                        .font(.title2.weight(.semibold))
                    Text("you need to be up for?")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 20)

                Divider()

                // Calendar content
                if events.isEmpty {
                    ContentUnavailableView(
                        "No Events Tomorrow",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("Add events to your calendar and they'll appear here.")
                    )
                } else {
                    ScrollView {
                        let totalH = CGFloat(hourRange.count) * hourHeight
                        ZStack(alignment: .topLeading) {
                            // Hour grid
                            VStack(spacing: 0) {
                                ForEach(hourRange, id: \.self) { hour in
                                    HStack(alignment: .top, spacing: 0) {
                                        Text(hourLabel(hour))
                                            .font(.system(size: 11, weight: .medium, design: .rounded))
                                            .foregroundStyle(.secondary)
                                            .frame(width: labelWidth, alignment: .trailing)
                                            .padding(.trailing, 8)
                                            .offset(y: -7)
                                        Rectangle()
                                            .fill(Color.secondary.opacity(0.15))
                                            .frame(height: 0.5)
                                    }
                                    .frame(height: hourHeight)
                                }
                            }

                            // Event blocks
                            ForEach(events, id: \.eventIdentifier) { event in
                                let isSelected = event.eventIdentifier == selected?.eventIdentifier
                                Button {
                                    selected = event
                                    dismiss()
                                } label: {
                                    HStack(spacing: 6) {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(.white)
                                            .frame(width: 3)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(event.title ?? "Untitled")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.white)
                                                .lineLimit(2)
                                            Text(timeRangeLabel(event))
                                                .font(.system(size: 10))
                                                .foregroundStyle(.white.opacity(0.7))
                                        }
                                        Spacer(minLength: 0)
                                        if isSelected {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.caption)
                                                .foregroundStyle(.white)
                                        }
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .frame(height: eventHeight(for: event), alignment: .top)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(isSelected ? Color.white.opacity(0.25) : Color.white.opacity(0.12))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .strokeBorder(isSelected ? Color.white.opacity(0.6) : Color.clear, lineWidth: 1)
                                            )
                                    )
                                }
                                .offset(x: labelWidth + 8, y: yOffset(for: event.startDate))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.trailing, 16)
                            }
                        }
                        .frame(height: totalH)
                        .padding(.top, 12)
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        let d = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now)!
        return d.formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated)))
    }

    private func timeRangeLabel(_ event: EKEvent) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        f.amSymbol = "AM"; f.pmSymbol = "PM"
        return "\(f.string(from: event.startDate)) – \(f.string(from: event.endDate))"
    }
}

// MARK: - Wake Time Adjuster Sheet

private struct WakeTimeAdjusterSheet: View {
    @Binding var bufferMinutes: Int
    let eventStart: Date
    @Environment(\.dismiss) private var dismiss

    @State private var localBuffer: Int = 60
    @State private var dragBase: Int = 60
    @State private var dragAccum: CGFloat = 0
    @State private var originalBuffer: Int = 60  // captured on appear — never changes
    private let pxPerMin: CGFloat = 3.0

    private var isModified: Bool { localBuffer != originalBuffer }

    private var wakeTime: Date {
        eventStart.addingTimeInterval(-Double(localBuffer * 60))
    }
    private var subPixelOffset: CGFloat {
        dragAccum.truncatingRemainder(dividingBy: pxPerMin)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header row with undo
            HStack {
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        localBuffer = originalBuffer
                        dragBase = originalBuffer
                        dragAccum = 0
                    }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                } label: {
                    Label("Suggested", systemImage: "arrow.uturn.backward")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(isModified ? .white.opacity(0.7) : .white.opacity(0.25))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(isModified ? 0.12 : 0.05), in: Capsule())
                }
                .disabled(!isModified)
                .animation(.easeInOut(duration: 0.2), value: isModified)

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)

            Text("How early do you want to wake?")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.45))
                .padding(.top, 28)

                // Large wake time
                Text(wakeTime.formatted(.dateTime.hour().minute()))
                    .font(.system(size: 64, weight: .thin, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.15), value: localBuffer)
                    .padding(.top, 12)

                Spacer()

                // Ruler + cursor
                ZStack {
                    TimeRulerView(centerTime: wakeTime, pxPerMin: pxPerMin, subPixelOffset: subPixelOffset)
                        .frame(height: 80)

                    // Fixed center cursor (circle + stem)
                    VStack(spacing: 0) {
                        Circle()
                            .stroke(.white, lineWidth: 1.5)
                            .background(Circle().fill(Color.clear))
                            .frame(width: 10, height: 10)
                        Rectangle()
                            .fill(.white)
                            .frame(width: 1.5, height: 30)
                    }
                    .allowsHitTesting(false)
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { val in
                            dragAccum = val.translation.width
                            let delta = Int(dragAccum / pxPerMin)
                            let next = max(0, min(240, dragBase + delta))
                            if next != localBuffer {
                                localBuffer = next
                                UISelectionFeedbackGenerator().selectionChanged()
                            }
                        }
                        .onEnded { _ in
                            dragBase = localBuffer
                            dragAccum = 0
                            bufferMinutes = localBuffer
                        }
                )

                Spacer()

                // Buffer pill
                Text("\(localBuffer) min before event")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(Color.white.opacity(0.12), in: Capsule())
                    .animation(.spring(response: 0.15), value: localBuffer)

                Text("Drag the ruler to adjust prep time")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.top, 10)

                Spacer()

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    bufferMinutes = localBuffer
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 36)
        }
        .onAppear {
            localBuffer = bufferMinutes
            dragBase = bufferMinutes
            originalBuffer = bufferMinutes
        }
    }
}

// MARK: - Time Ruler

private struct TimeRulerView: View {
    let centerTime: Date
    let pxPerMin: CGFloat
    let subPixelOffset: CGFloat

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                let cx = size.width / 2
                let minuteSpan = Int(size.width / pxPerMin / 2) + 10

                for offset in -minuteSpan...minuteSpan {
                    let x = cx + CGFloat(offset) * pxPerMin + subPixelOffset
                    guard x >= -4 && x <= size.width + 4 else { continue }

                    let t = centerTime.addingTimeInterval(Double(offset) * 60)
                    let mins = Calendar.current.component(.minute, from: t)

                    let (tickH, alpha): (CGFloat, Double) = {
                        if mins == 0      { return (28, 0.75) }
                        if mins % 15 == 0 { return (16, 0.40) }
                        if mins % 5  == 0 { return (9,  0.22) }
                        return (0, 0)
                    }()
                    guard tickH > 0 else { continue }

                    let y = (size.height - tickH) / 2
                    ctx.fill(
                        Path(CGRect(x: x - 0.75, y: y, width: 1.5, height: tickH)),
                        with: .color(.white.opacity(alpha))
                    )

                    if mins == 0 {
                        ctx.draw(
                            Text(t.formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated))))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.55)),
                            at: CGPoint(x: x, y: y - 13),
                            anchor: .center
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Typing Dots

private struct TypingDotsView: View {
    @State private var lit: Int = 0

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.white.opacity(lit == i ? 0.85 : 0.25))
                    .frame(width: 6, height: 6)
                    .offset(y: lit == i ? -5 : 0)
                    .animation(
                        .spring(response: 0.22, dampingFraction: 0.45),
                        value: lit
                    )
            }
        }
        .task {
            while !Task.isCancelled {
                for i in 0..<3 {
                    lit = i
                    try? await Task.sleep(nanoseconds: 260_000_000)
                }
            }
        }
    }
}

#Preview {
    let schema = Schema([SleepSession.self, AlarmConfig.self, CalibrationProfile.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])
    TodayView()
        .modelContainer(container)
        .environment(BLEManager())
        .environment(TabRouter())
}
