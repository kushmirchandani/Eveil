import SwiftUI
import SwiftData
import UIKit
import FoundationModels

// MARK: - Colour palette

private extension Color {
    static let eveilBg    = Color(red: 0.06, green: 0.06, blue: 0.10)
    static let eveilCard  = Color(red: 0.11, green: 0.11, blue: 0.17)
    static let eveilCard2 = Color(red: 0.15, green: 0.15, blue: 0.22)
    static let sleepDeep  = Color(red: 0.18, green: 0.28, blue: 0.90)
    static let sleepCore  = Color(red: 0.35, green: 0.56, blue: 0.98)
    static let sleepREM   = Color(red: 0.52, green: 0.68, blue: 1.00)
    static let sleepAwake = Color(red: 0.90, green: 0.22, blue: 0.42)
}

// MARK: - Sleep Stage model

enum SleepStage: String, CaseIterable {
    case deep  = "Deep Sleep"
    case core  = "Core Sleep"
    case rem   = "REM"
    case awake = "Awake"

    var color: Color {
        switch self {
        case .deep:  return .sleepDeep
        case .core:  return .sleepCore
        case .rem:   return .sleepREM
        case .awake: return .sleepAwake
        }
    }

    var icon: String {
        switch self {
        case .deep:  return "moon.fill"
        case .core:  return "bed.double.fill"
        case .rem:   return "sparkles"
        case .awake: return "eye.fill"
        }
    }

    var detail: String {
        switch self {
        case .deep:
            return "The most restorative stage. Supports memory consolidation, immune function, and physical recovery."
        case .core:
            return "Light sleep that makes up the bulk of the night. Important for mental recovery and processing."
        case .rem:
            return "Rapid Eye Movement sleep. Critical for emotional regulation, creativity, and memory formation."
        case .awake:
            return "Brief awakenings during the night. Some is normal — frequent waking may signal sleep disruption."
        }
    }

    func minutes(from b: SleepBreakdown) -> Int {
        switch self {
        case .deep:  return Int(b.deepMinutes)
        case .core:  return Int(b.coreMinutes)
        case .rem:   return Int(b.remMinutes)
        case .awake: return Int(b.awakeMinutes)
        }
    }
}

struct SleepStageSelection: Equatable {
    let stage:  SleepStage
    let night:  DailySleepData

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.stage == rhs.stage && lhs.night.id == rhs.night.id
    }
}

// MARK: - Period

enum SleepPeriod: String, CaseIterable {
    case week = "Week", month = "Month"
}

// MARK: - Main View

struct SleepView: View {
    @State private var weeklyData: [DailySleepData] = []
    @State private var monthlyData: [DailySleepData] = []
    @State private var isLoading = true
    @State private var period: SleepPeriod = .week
    @State private var selectedNight: DailySleepData?
    @State private var selectedSegment: SleepStageSelection?

    var body: some View {
        NavigationStack {
            ZStack {
                Image("background-1")
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()

                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.45), location: 0),
                        .init(color: .black.opacity(0.82), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                if isLoading {
                    loadingView
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 24) {
                            PeriodPicker(selected: $period)
                                .onChange(of: period) {
                                    selectedSegment = nil
                                    selectedNight = nil
                                    UISelectionFeedbackGenerator().selectionChanged()
                                    if period == .month && monthlyData.isEmpty {
                                        Task { monthlyData = await HealthKitManager.shared.fetchWeeklySleepData(days: 30) }
                                    }
                                }

                            if period == .week {
                                WeekView(
                                    data: weeklyData,
                                    selectedNight: $selectedNight,
                                    selectedSegment: $selectedSegment
                                )
                            } else {
                                MonthView(data: monthlyData)
                            }

                            Spacer(minLength: 40)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                    }
                }
            }
            .navigationTitle("Sleep")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.eveilBg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .task {
                await HealthKitManager.shared.requestAuthorization()
                weeklyData = await HealthKitManager.shared.fetchWeeklySleepData()
                selectedNight = weeklyData.filter(\.hasData).last
                isLoading = false
            }
            .refreshable {
                weeklyData = await HealthKitManager.shared.fetchWeeklySleepData()
                selectedNight = weeklyData.filter(\.hasData).last
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView().tint(.white)
            Text("Loading sleep data…")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.4))
        }
    }
}

// MARK: - Period Picker

private struct PeriodPicker: View {
    @Binding var selected: SleepPeriod

    var body: some View {
        HStack(spacing: 0) {
            ForEach(SleepPeriod.allCases, id: \.self) { p in
                Button {
                    withAnimation(.spring(response: 0.3)) { selected = p }
                } label: {
                    Text(p.rawValue)
                        .font(.subheadline.weight(selected == p ? .semibold : .regular))
                        .foregroundStyle(selected == p ? .white : .white.opacity(0.45))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            selected == p ? Color.eveilCard2 : Color.clear,
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                }
            }
        }
        .padding(4)
        .background(Color.eveilCard, in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Day View

private struct DayView: View {
    let data: DailySleepData?
    @State private var heartRate: Double?
    @State private var hrv: Double?
    @State private var respRate: Double?
    @State private var selectedSegment: SleepStageSelection?

    var body: some View {
        if let data {
            VStack(spacing: 20) {
                // Date label
                Text(data.date, format: .dateTime.weekday(.wide).month(.wide).day())
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .center)

                // Ring
                InteractiveRing(data: data, selectedSegment: $selectedSegment)

                // Bed/wake times
                if data.bedTime != nil || data.wakeTime != nil {
                    BedWakeRow(bedTime: data.bedTime, wakeTime: data.wakeTime)
                }

                // Segment detail card
                if let seg = selectedSegment {
                    SegmentDetailCard(selection: seg)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Stage grid
                StageGrid(data: data, selectedSegment: $selectedSegment)

                // Health metrics
                HealthMetricsSection(date: data.date)
            }
        } else {
            NoDataView()
        }
    }
}

// MARK: - Week View

private struct WeekView: View {
    let data: [DailySleepData]
    @Binding var selectedNight: DailySleepData?
    @Binding var selectedSegment: SleepStageSelection?

    private var avgMinutes: Double {
        let nights = data.filter(\.hasData)
        guard !nights.isEmpty else { return 0 }
        return nights.map(\.breakdown.totalMinutes).reduce(0, +) / Double(nights.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Average header
            AverageSleepHeader(avgMinutes: avgMinutes)

            // Interactive chart
            InteractiveBarChart(data: data, selectedNight: $selectedNight, selectedSegment: $selectedSegment)

            // Selected segment detail
            if let seg = selectedSegment {
                SegmentDetailCard(selection: seg)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Selected night breakdown
            if let night = selectedNight, night.hasData, selectedSegment == nil {
                SelectedNightCard(night: night)
                    .transition(.opacity)
            }

            FiltersRow()
            Divider().background(Color.white.opacity(0.08))
            InsightsSection(data: data)

            let nights: [DailySleepData] = data.filter { $0.hasData }.reversed()
            if !nights.isEmpty {
                SessionListSection(data: nights)
            } else {
                NoDataView()
            }
        }
    }
}

// MARK: - Interactive Ring (Day view)

private struct InteractiveRing: View {
    let data: DailySleepData
    @Binding var selectedSegment: SleepStageSelection?

    private let size: CGFloat      = 260
    private let lineWidth: CGFloat = 26
    private let gap: Double        = 0.007   // fraction of circle between segments

    private var b: SleepBreakdown { data.breakdown }
    private var total: Double { max(b.totalMinutes, 1) }

    private func rawFrac(_ stage: SleepStage) -> Double {
        Double(stage.minutes(from: b)) / total
    }

    // Cumulative start position of each stage
    private func rawStart(_ stage: SleepStage) -> Double {
        switch stage {
        case .deep:  return 0
        case .core:  return rawFrac(.deep)
        case .rem:   return rawFrac(.deep) + rawFrac(.core)
        case .awake: return rawFrac(.deep) + rawFrac(.core) + rawFrac(.rem)
        }
    }

    // Inset each segment by half a gap on each side
    private func trimFrom(_ stage: SleepStage) -> Double { rawStart(stage) + gap / 2 }
    private func trimTo(_ stage: SleepStage) -> Double   { rawStart(stage) + rawFrac(stage) - gap / 2 }

    // Convert a 0–1 fraction to an (x, y) offset on the ring track
    private func trackOffset(at fraction: Double) -> CGSize {
        let r = Double((size / 2) - (lineWidth / 2))
        let angle = fraction * 2 * Double.pi - (Double.pi / 2)
        return CGSize(width: r * Darwin.cos(angle), height: r * Darwin.sin(angle))
    }

    // End fraction (where sun sits)
    private var endFraction: Double { 1.0 - gap / 2 }

    var body: some View {
        ZStack {
            // Background track
            Circle()
                .stroke(Color.white.opacity(0.07), lineWidth: lineWidth)

            // Sleep stage arcs — flat .butt caps, gapped, no overlap
            ForEach(SleepStage.allCases, id: \.self) { stage in
                let from   = trimFrom(stage)
                let to     = trimTo(stage)
                let isSelected = selectedSegment?.stage == stage

                if to > from + 0.002 {
                    Circle()
                        .trim(from: from, to: to)
                        .stroke(
                            isSelected ? stage.color : stage.color.opacity(0.82),
                            style: StrokeStyle(
                                lineWidth: isSelected ? lineWidth + 5 : lineWidth,
                                lineCap: .butt
                            )
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 0.3), value: isSelected)
                        .onTapGesture {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            withAnimation(.spring(response: 0.35)) {
                                selectedSegment = selectedSegment?.stage == stage
                                    ? nil
                                    : SleepStageSelection(stage: stage, night: data)
                            }
                        }
                }
            }

            // Moon marker — sits on the ring at the start (12 o'clock)
            let moonOff = trackOffset(at: 0)
            ZStack {
                Circle()
                    .fill(Color.sleepDeep)
                    .frame(width: lineWidth, height: lineWidth)
                Image(systemName: "moon.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .offset(moonOff)

            // Sun marker — sits on the ring at the end of the arc
            let sunOff = trackOffset(at: endFraction)
            ZStack {
                Circle()
                    .fill(Color(red: 0.95, green: 0.75, blue: 0.2))
                    .frame(width: lineWidth, height: lineWidth)
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .offset(sunOff)

            // Centre text
            VStack(spacing: 4) {
                if let seg = selectedSegment {
                    Text(seg.stage.rawValue)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(seg.stage.color)
                    Text(seg.stage.minutes(from: b).sleepFormatted)
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                } else {
                    Text(b.qualityLabel)
                        .font(.title2.weight(.semibold)).foregroundStyle(.white)
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text("\(b.totalHours)")
                            .font(.system(size: 28, weight: .light, design: .rounded)).foregroundStyle(.white)
                        Text("h").font(.subheadline).foregroundStyle(.white.opacity(0.5))
                        Text("\(b.totalMins)")
                            .font(.system(size: 28, weight: .medium, design: .rounded)).foregroundStyle(.white)
                        Text("m").font(.subheadline).foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: selectedSegment)
        }
        .frame(width: size, height: size)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Interactive Bar Chart (Week view)

private struct InteractiveBarChart: View {
    let data: [DailySleepData]
    @Binding var selectedNight: DailySleepData?
    @Binding var selectedSegment: SleepStageSelection?

    private let maxMinutes: Double = 9 * 60

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 8) {
                // Y-axis
                VStack(alignment: .trailing, spacing: 0) {
                    Text("12am").frame(maxHeight: .infinity, alignment: .top)
                    Text("4am").frame(maxHeight: .infinity, alignment: .center)
                    Text("8am").frame(maxHeight: .infinity, alignment: .bottom)
                }
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.3))
                .frame(width: 30, height: 160)

                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(data) { night in
                        TappableBarColumn(
                            night: night,
                            maxMinutes: maxMinutes,
                            isSelected: selectedNight?.id == night.id,
                            selectedSegment: $selectedSegment
                        )
                        .onTapGesture {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.spring(response: 0.35)) {
                                selectedNight = night
                                selectedSegment = nil
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }

            // X-axis labels
            HStack(spacing: 0) {
                Spacer().frame(width: 38)
                HStack(spacing: 0) {
                    ForEach(data) { night in
                        Text(night.dayLabel)
                            .font(.caption2)
                            .foregroundStyle(
                                selectedNight?.id == night.id
                                    ? .white
                                    : .white.opacity(0.35)
                            )
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.top, 8)
        }
    }
}

private struct TappableBarColumn: View {
    let night: DailySleepData
    let maxMinutes: Double
    let isSelected: Bool
    @Binding var selectedSegment: SleepStageSelection?

    private func height(_ mins: Double) -> CGFloat {
        CGFloat(mins / maxMinutes) * 160
    }

    var body: some View {
        VStack(spacing: 1) {
            if night.hasData {
                ForEach([SleepStage.awake, .rem, .deep, .core], id: \.self) { stage in
                    let mins = Double(stage.minutes(from: night.breakdown))
                    if mins > 0 {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(
                                selectedSegment?.stage == stage && selectedSegment?.night.id == night.id
                                    ? stage.color
                                    : stage.color.opacity(isSelected ? 1.0 : 0.55)
                            )
                            .frame(height: height(mins))
                            .onTapGesture {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                withAnimation(.spring(response: 0.35)) {
                                    let sel = SleepStageSelection(stage: stage, night: night)
                                    selectedSegment = selectedSegment == sel ? nil : sel
                                }
                            }
                    }
                }
            } else {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 20)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color.white.opacity(isSelected ? 0.25 : 0), lineWidth: 1.5)
        )
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.3), value: isSelected)
    }
}

// MARK: - Segment Detail Card

private struct SegmentDetailCard: View {
    let selection: SleepStageSelection

    private var minutes: Int { selection.stage.minutes(from: selection.night.breakdown) }
    private var pct: Int {
        let total = max(selection.night.breakdown.totalMinutes, 1)
        return Int(Double(minutes) / total * 100)
    }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(selection.stage.color.opacity(0.15))
                    .frame(width: 46, height: 46)
                Image(systemName: selection.stage.icon)
                    .font(.system(size: 20))
                    .foregroundStyle(selection.stage.color)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(selection.stage.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("\(minutes.sleepFormatted) · \(pct)% of night")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.45))
                }
                Text(selection.stage.detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(Color.eveilCard, in: RoundedRectangle(cornerRadius: 18))
    }
}

// MARK: - Selected Night Card (week view)

private struct SelectedNightCard: View {
    let night: DailySleepData

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(night.date, format: .dateTime.weekday(.wide).month().day())
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text(night.breakdown.qualityLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(qualityColor(night.breakdown.qualityLabel))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(qualityColor(night.breakdown.qualityLabel).opacity(0.15), in: Capsule())
            }
            HStack(spacing: 0) {
                ForEach(SleepStage.allCases, id: \.self) { stage in
                    let mins = stage.minutes(from: night.breakdown)
                    if mins > 0 {
                        MiniStageStat(stage: stage, minutes: mins)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.eveilCard, in: RoundedRectangle(cornerRadius: 18))
    }

    private func qualityColor(_ q: String) -> Color {
        switch q {
        case "Good": return .sleepCore
        case "Fair": return .orange
        default: return .white.opacity(0.4)
        }
    }
}

private struct MiniStageStat: View {
    let stage: SleepStage
    let minutes: Int

    var body: some View {
        VStack(spacing: 4) {
            Circle().fill(stage.color).frame(width: 6, height: 6)
            Text(minutes.sleepFormatted)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.6))
            Text(stage.rawValue.components(separatedBy: " ").first ?? "")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Stage Grid (Day view)

private struct StageGrid: View {
    let data: DailySleepData
    @Binding var selectedSegment: SleepStageSelection?

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(SleepStage.allCases, id: \.self) { stage in
                let mins = stage.minutes(from: data.breakdown)
                let isSelected = selectedSegment?.stage == stage
                SleepMetricCard(
                    stage: stage,
                    minutes: mins,
                    isSelected: isSelected
                )
                .onTapGesture {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation(.spring(response: 0.35)) {
                        selectedSegment = isSelected ? nil : SleepStageSelection(stage: stage, night: data)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Shared metric card

private struct SleepMetricCard: View {
    let stage: SleepStage
    let minutes: Int
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle().fill(stage.color).frame(width: 8, height: 8)
                Text(stage.rawValue).font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.6))
            }
            Group {
                if minutes >= 60 {
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text("\(minutes / 60)")
                            .font(.system(size: 28, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                        Text("h").font(.subheadline).foregroundStyle(.white.opacity(0.5))
                        Text("\(minutes % 60)")
                            .font(.system(size: 22, weight: .medium, design: .rounded)).foregroundStyle(.white)
                        Text("m").font(.caption).foregroundStyle(.white.opacity(0.5))
                    }
                } else {
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text("\(minutes)")
                            .font(.system(size: 28, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                        Text("min").font(.subheadline).foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isSelected
                ? stage.color.opacity(0.15)
                : Color.eveilCard,
            in: RoundedRectangle(cornerRadius: 18)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(isSelected ? stage.color.opacity(0.5) : Color.clear, lineWidth: 1.5)
        )
        .animation(.spring(response: 0.3), value: isSelected)
    }
}

// MARK: - Bed/Wake row

private struct BedWakeRow: View {
    let bedTime: Date?
    let wakeTime: Date?

    var body: some View {
        HStack(spacing: 32) {
            if let bed = bedTime {
                HStack(spacing: 6) {
                    Image(systemName: "moon.fill").foregroundStyle(Color.sleepDeep)
                    Text(bed, format: .dateTime.hour().minute())
                        .font(.subheadline.weight(.medium)).foregroundStyle(.white)
                }
            }
            if let wake = wakeTime {
                HStack(spacing: 6) {
                    Image(systemName: "sun.max.fill").foregroundStyle(.yellow.opacity(0.8))
                    Text(wake, format: .dateTime.hour().minute())
                        .font(.subheadline.weight(.medium)).foregroundStyle(.white)
                }
            }
        }
    }
}

// MARK: - Health Metrics Section

private struct HealthMetricsSection: View {
    let date: Date
    @State private var heartRate: Double?
    @State private var hrv: Double?
    @State private var respRate: Double?
    @State private var loading = true

    var body: some View {
        Group {
            if loading {
                ProgressView().tint(.white).padding()
            } else if heartRate != nil || hrv != nil || respRate != nil {
                HealthMetricsCard(heartRate: heartRate, hrv: hrv, respRate: respRate)
                    .padding(.horizontal, 20)
            }
        }
        .task {
            async let hr  = HealthKitManager.shared.averageHeartRate(for: date)
            async let h   = HealthKitManager.shared.averageHRV(for: date)
            async let rr  = HealthKitManager.shared.averageRespiratoryRate(for: date)
            (heartRate, hrv, respRate) = await (hr, h, rr)
            loading = false
        }
    }
}

private struct HealthMetricsCard: View {
    let heartRate: Double?
    let hrv: Double?
    let respRate: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Health Metrics", systemImage: "heart.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.4))
                .tracking(0.5)
                .textCase(.uppercase)
            HStack(spacing: 0) {
                if let hr = heartRate {
                    HealthMetric(icon: "heart.fill", iconColor: .red,
                                 value: "\(Int(hr))", unit: "bpm", label: "Avg HR")
                }
                if let h = hrv {
                    HealthMetric(icon: "waveform.path.ecg",
                                 iconColor: Color(red: 0.4, green: 0.8, blue: 0.6),
                                 value: "\(Int(h))", unit: "ms", label: "HRV")
                }
                if let rr = respRate {
                    HealthMetric(icon: "lungs.fill", iconColor: Color.sleepCore,
                                 value: "\(Int(rr))", unit: "/min", label: "Resp")
                }
            }
        }
        .padding(20)
        .background(Color.eveilCard, in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct HealthMetric: View {
    let icon: String; let iconColor: Color
    let value: String; let unit: String; let label: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(iconColor).font(.system(size: 18))
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value).font(.title3.weight(.semibold)).foregroundStyle(.white)
                Text(unit).font(.caption2).foregroundStyle(.white.opacity(0.45))
            }
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Average Header

private struct AverageSleepHeader: View {
    let avgMinutes: Double
    private var hours: Int   { Int(avgMinutes) / 60 }
    private var minutes: Int { Int(avgMinutes) % 60 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Average time asleep", systemImage: "bed.double.fill")
                .font(.subheadline).foregroundStyle(.white.opacity(0.5))
            if avgMinutes == 0 {
                Text("No data yet").font(.title2).foregroundStyle(.white.opacity(0.4))
            } else {
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text("\(hours)")
                        .font(.system(size: 52, weight: .thin, design: .rounded)).foregroundStyle(.white)
                    Text("h").font(.title3).foregroundStyle(.white.opacity(0.6)).padding(.trailing, 4)
                    Text("\(minutes)")
                        .font(.system(size: 52, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    Text("min").font(.title3).foregroundStyle(.white.opacity(0.6))
                }
            }
        }
    }
}

// MARK: - Filters

private struct FiltersRow: View {
    var body: some View {
        Button { } label: {
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                Text("Filters").font(.subheadline.weight(.medium))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Color.eveilCard, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - Insights

private struct InsightsSection: View {
    let data: [DailySleepData]

    private var bestDay: String? {
        data.filter(\.hasData)
            .max { $0.breakdown.totalMinutes < $1.breakdown.totalMinutes }
            .map { $0.date.formatted(.dateTime.weekday(.wide)) }
    }
    private var avgDeepPct: Int {
        let nights = data.filter(\.hasData)
        guard !nights.isEmpty else { return 0 }
        let avg = nights.map { $0.breakdown.deepMinutes / max($0.breakdown.totalMinutes, 1) }.reduce(0, +) / Double(nights.count)
        return Int(avg * 100)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("PERSONAL INSIGHTS", systemImage: "bolt.fill")
                .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.4)).tracking(0.5)

            InsightCard(icon: "moon.stars.fill", title: "Deep sleep this week",
                detail: avgDeepPct > 0
                    ? "You averaged \(avgDeepPct)% deep sleep — the restorative stage that matters most."
                    : "Connect an Apple Watch or Oura Ring to get deep sleep insights.")

            if let day = bestDay {
                InsightCard(icon: "sun.and.horizon.fill", title: "Best night this week",
                    detail: "You slept longest on \(day). Keeping that bedtime consistent improves your average.")
            }
        }
    }
}

private struct InsightCard: View {
    let icon: String; let title: String; let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle().fill(Color.eveilCard2).frame(width: 40, height: 40)
                Image(systemName: icon).font(.system(size: 16)).foregroundStyle(Color.sleepCore)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Text(detail).font(.caption).foregroundStyle(.white.opacity(0.5)).lineSpacing(3)
            }
        }
        .padding(16)
        .background(Color.eveilCard, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Session list

private struct SessionListSection: View {
    let data: [DailySleepData]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Nights")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.4))
                .tracking(0.5).textCase(.uppercase)

            ForEach(data.prefix(7)) { night in
                NavigationLink(destination: NightDetailView(data: night)) {
                    SleepNightRow(night: night)
                }
            }
        }
    }
}

private struct SleepNightRow: View {
    let night: DailySleepData

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(night.date, format: .dateTime.weekday(.wide).month().day())
                    .font(.subheadline.weight(.medium)).foregroundStyle(.white)
                Text("\(night.breakdown.totalHours)h \(night.breakdown.totalMins)m")
                    .font(.caption).foregroundStyle(.white.opacity(0.45))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(night.breakdown.qualityLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(night.breakdown.qualityLabel == "Good" ? Color.sleepCore : .orange)
                if let wake = night.wakeTime {
                    Text("Woke \(wake.formatted(.dateTime.hour().minute()))")
                        .font(.caption2).foregroundStyle(.white.opacity(0.3))
                }
            }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.white.opacity(0.2)).padding(.leading, 4)
        }
        .padding(16)
        .background(Color.eveilCard, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Full night detail (navigation push)

struct NightDetailView: View {
    let data: DailySleepData
    @State private var selectedSegment: SleepStageSelection?

    var body: some View {
        ZStack {
            Color.eveilBg.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    Text(data.date, format: .dateTime.weekday(.wide).month(.wide).day())
                        .font(.subheadline).foregroundStyle(.white.opacity(0.4))
                        .padding(.top, 8)

                    InteractiveRing(data: data, selectedSegment: $selectedSegment)

                    if data.bedTime != nil || data.wakeTime != nil {
                        BedWakeRow(bedTime: data.bedTime, wakeTime: data.wakeTime)
                    }

                    if let seg = selectedSegment {
                        SegmentDetailCard(selection: seg)
                            .padding(.horizontal, 20)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    StageGrid(data: data, selectedSegment: $selectedSegment)
                    HealthMetricsSection(date: data.date)
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.eveilBg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}

// MARK: - No data

private struct NoDataView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "moon.zzz").font(.system(size: 36)).foregroundStyle(.white.opacity(0.2))
            Text("No sleep data found")
                .font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.4))
            Text("Make sure Apple Health is connected\nand you've worn your Apple Watch to bed.")
                .font(.caption).foregroundStyle(.white.opacity(0.25))
                .multilineTextAlignment(.center).lineSpacing(3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

// MARK: - Helpers

private extension Int {
    var sleepFormatted: String {
        guard self > 0 else { return "0 min" }
        if self >= 60 {
            let h = self / 60
            let m = self % 60
            return m > 0 ? "\(h)h \(m)m" : "\(h)h"
        }
        return "\(self) min"
    }
}

// MARK: - Month View

@Generable
private struct SleepProfileOutput {
    @Guide(description: "A catchy 3–5 word label for this person's sleep archetype, e.g. 'Late-Night Deep Sleeper' or 'REM-Dominant Dreamer'.")
    var archetype: String

    @Guide(description: "Two or three sentences summarising this person's overall sleep patterns based on the data. Be specific — mention actual averages or trends.")
    var overview: String

    @Guide(description: "One sentence about the user's deep sleep trends. Include typical percentage and whether it's above, average, or below the healthy 13–23% range.")
    var deepSleepInsight: String

    @Guide(description: "One sentence about the user's REM sleep trends. Include typical percentage and whether it's above, average, or below the healthy 20–25% range.")
    var remInsight: String

    @Guide(description: "One actionable, personalised tip (max 20 words) based on this person's specific patterns.")
    var tip: String
}

@Observable
private final class MonthProfileViewModel {
    enum State { case idle, loading, ready(SleepProfileOutput), unavailable, error(String) }
    var state: State = .idle

    func generate(from data: [DailySleepData]) async {
        guard !data.isEmpty else { state = .idle; return }
        state = .loading

        // Build a compact text summary of the 30 days
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"

        var lines: [String] = []
        for night in data where night.hasData {
            let b = night.breakdown
            let total = b.totalMinutes
            guard total > 0 else { continue }
            let deepPct  = Int((b.deepMinutes  / total) * 100)
            let corePct  = Int((b.coreMinutes  / total) * 100)
            let remPct   = Int((b.remMinutes   / total) * 100)
            let awakePct = Int((b.awakeMinutes / total) * 100)
            let label    = formatter.string(from: night.date)
            lines.append("\(label): \(b.totalHours)h\(b.totalMins)m total — deep \(deepPct)%, core \(corePct)%, REM \(remPct)%, awake \(awakePct)%")
        }

        guard !lines.isEmpty else { state = .idle; return }

        let prompt = """
        Here is 30 days of my sleep data (one night per line):
        \(lines.joined(separator: "\n"))

        Based on these patterns, create a personalised sleep profile for me.
        """

        do {
            let session = LanguageModelSession(
                instructions: "You are a sleep scientist analysing personal HealthKit sleep stage data. Give specific, data-driven insights. Speak directly to the user."
            )
            let response = try await session.respond(to: prompt, generating: SleepProfileOutput.self)
            state = .ready(response.content)
        } catch {
            let desc = error.localizedDescription.lowercased()
            if desc.contains("unavailable") || desc.contains("not available") || desc.contains("model") {
                state = .unavailable
            } else {
                state = .error(error.localizedDescription)
            }
        }
    }
}

private struct MonthView: View {
    let data: [DailySleepData]
    @State private var vm = MonthProfileViewModel()

    private var nightsWithData: [DailySleepData] { data.filter(\.hasData) }

    // 30-day averages
    private var avgTotal: Double {
        guard !nightsWithData.isEmpty else { return 0 }
        return nightsWithData.map(\.breakdown.totalMinutes).reduce(0, +) / Double(nightsWithData.count)
    }
    private var avgDeepPct: Double {
        guard !nightsWithData.isEmpty else { return 0 }
        let pcts = nightsWithData.map { n -> Double in
            let t = n.breakdown.totalMinutes; return t > 0 ? n.breakdown.deepMinutes / t : 0
        }
        return pcts.reduce(0, +) / Double(nightsWithData.count) * 100
    }
    private var avgREMPct: Double {
        guard !nightsWithData.isEmpty else { return 0 }
        let pcts = nightsWithData.map { n -> Double in
            let t = n.breakdown.totalMinutes; return t > 0 ? n.breakdown.remMinutes / t : 0
        }
        return pcts.reduce(0, +) / Double(nightsWithData.count) * 100
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            // 30-day stats strip
            if !nightsWithData.isEmpty {
                MonthStatsStrip(avgMinutes: avgTotal, deepPct: avgDeepPct, remPct: avgREMPct, nights: nightsWithData.count)
            }

            // Mini bar sparkline — all 30 nights
            if !data.isEmpty {
                MonthSparkline(data: data)
            }

            // AI Profile card
            MonthProfileCard(vm: vm)

            Spacer(minLength: 16)
        }
        .task(id: data.count) {
            guard case .idle = vm.state else { return }
            await vm.generate(from: data)
        }
    }
}

// MARK: Month Stats Strip

private struct MonthStatsStrip: View {
    let avgMinutes: Double
    let deepPct:   Double
    let remPct:    Double
    let nights:    Int

    private var avgH: Int { Int(avgMinutes) / 60 }
    private var avgM: Int { Int(avgMinutes) % 60 }

    var body: some View {
        HStack(spacing: 0) {
            statCell(label: "Avg Sleep", value: "\(avgH)h \(avgM)m")
            Divider().frame(height: 32).background(.white.opacity(0.12))
            statCell(label: "Deep", value: String(format: "%.0f%%", deepPct))
            Divider().frame(height: 32).background(.white.opacity(0.12))
            statCell(label: "REM", value: String(format: "%.0f%%", remPct))
            Divider().frame(height: 32).background(.white.opacity(0.12))
            statCell(label: "Nights", value: "\(nights)")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.eveilCard, in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private func statCell(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: Month Sparkline

private struct MonthSparkline: View {
    let data: [DailySleepData]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Last 30 nights")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.4))

            Canvas { ctx, sz in
                let nights = data
                guard !nights.isEmpty else { return }
                let barW    = (sz.width - CGFloat(nights.count - 1) * 2) / CGFloat(nights.count)
                let maxMins = nights.map(\.breakdown.totalMinutes).max() ?? 1
                let maxH    = sz.height

                for (i, night) in nights.enumerated() {
                    let x    = CGFloat(i) * (barW + 2)
                    let frac = night.hasData ? CGFloat(night.breakdown.totalMinutes / maxMins) : 0

                    // Background bar
                    let bg = Path(roundedRect: CGRect(x: x, y: 0, width: barW, height: maxH), cornerRadius: 3)
                    ctx.fill(bg, with: .color(.white.opacity(0.06)))

                    guard frac > 0 else { continue }

                    let b     = night.breakdown
                    let total = b.totalMinutes
                    var y     = maxH

                    for (mins, color): (Double, Color) in [
                        (b.deepMinutes, .sleepDeep),
                        (b.coreMinutes, .sleepCore),
                        (b.remMinutes,  .sleepREM),
                        (b.awakeMinutes, .sleepAwake)
                    ] {
                        let segH = CGFloat(mins / total) * frac * maxH
                        y -= segH
                        let seg = Path(roundedRect: CGRect(x: x, y: y, width: barW, height: segH), cornerRadius: 2)
                        ctx.fill(seg, with: .color(color.opacity(0.85)))
                    }
                }
            }
            .frame(height: 60)
        }
        .padding(14)
        .background(Color.eveilCard, in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: Month Profile Card

private struct MonthProfileCard: View {
    var vm: MonthProfileViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(red: 0.92, green: 0.68, blue: 0.22))
                Text("Your Sleep Profile")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                Text("On-device AI")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.25))
            }
            .padding(.bottom, 14)

            switch vm.state {
            case .idle:
                EmptyView()

            case .loading:
                VStack(spacing: 14) {
                    ProgressView().tint(.white.opacity(0.4))
                    Text("Analysing your sleep patterns…")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.4))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)

            case .ready(let profile):
                VStack(alignment: .leading, spacing: 16) {
                    Text(profile.archetype)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text(profile.overview)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                        .lineSpacing(3)

                    Divider().background(.white.opacity(0.08))

                    insightRow(icon: "moon.fill",    color: .sleepDeep, text: profile.deepSleepInsight)
                    insightRow(icon: "sparkles",      color: .sleepREM,  text: profile.remInsight)

                    Divider().background(.white.opacity(0.08))

                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "lightbulb.fill")
                            .font(.caption)
                            .foregroundStyle(Color(red: 0.92, green: 0.68, blue: 0.22))
                            .padding(.top, 2)
                        Text(profile.tip)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineSpacing(3)
                    }
                }

            case .unavailable:
                VStack(spacing: 10) {
                    Image(systemName: "brain")
                        .font(.system(size: 28))
                        .foregroundStyle(.white.opacity(0.25))
                    Text("On-device AI not available")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.5))
                    Text("Requires iOS 18.1 or later with Apple Intelligence enabled.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.3))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)

            case .error(let msg):
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 24))
                        .foregroundStyle(.white.opacity(0.3))
                    Text("Couldn't generate profile")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.45))
                    Text(msg)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.2))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
        }
        .padding(16)
        .background(Color.eveilCard, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func insightRow(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 16)
                .padding(.top, 2)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .lineSpacing(3)
        }
    }
}

// MARK: - Preview

#Preview {
    let schema = Schema([SleepSession.self, AlarmConfig.self, CalibrationProfile.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])
    SleepView()
        .modelContainer(container)
        .preferredColorScheme(.dark)
}
