import HealthKit
import Observation

@Observable
final class HealthKitManager {
    static let shared = HealthKitManager()
    private init() {}

    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }
    var authorizationStatus: AuthStatus = .notDetermined

    enum AuthStatus { case notDetermined, authorized, denied }

    private var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        for id: HKCategoryTypeIdentifier in [.sleepAnalysis] {
            if let t = HKObjectType.categoryType(forIdentifier: id) { types.insert(t) }
        }
        for id: HKQuantityTypeIdentifier in [.heartRate, .respiratoryRate, .heartRateVariabilitySDNN, .oxygenSaturation] {
            if let t = HKObjectType.quantityType(forIdentifier: id) { types.insert(t) }
        }
        return types
    }

    private var writeTypes: Set<HKSampleType> {
        guard let t = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
        return [t]
    }

    func requestAuthorization() async {
        guard isAvailable else { authorizationStatus = .denied; return }
        do {
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
            authorizationStatus = .authorized
        } catch {
            authorizationStatus = .denied
        }
    }

    // MARK: - Weekly data

    /// Returns one `DailySleepData` per day for the past `days` nights, oldest first.
    func fetchWeeklySleepData(days: Int = 7) async -> [DailySleepData] {
        guard isAvailable else { return [] }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        var results: [DailySleepData] = []

        await withTaskGroup(of: DailySleepData?.self) { group in
            for offset in 1...days {
                guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
                group.addTask { await self.fetchDailySleep(wakeDay: day) }
            }
            for await result in group {
                if let r = result { results.append(r) }
            }
        }

        return results.sorted { $0.date < $1.date }
    }

    // MARK: - Per-night fetch

    /// Fetches sleep samples for a single night ending on `wakeDay`.
    /// The sleep window spans from 6 pm the previous day to noon of `wakeDay`.
    func fetchDailySleep(wakeDay: Date) async -> DailySleepData {
        let calendar = Calendar.current
        let noon     = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: wakeDay)!
        let evening  = calendar.date(byAdding: .hour, value: -18, to: noon)!

        let type      = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        let predicate = HKQuery.predicateForSamples(withStart: evening, end: noon, options: .strictStartDate)
        let sort      = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let samples: [HKCategorySample] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, s, _ in
                cont.resume(returning: (s as? [HKCategorySample]) ?? [])
            }
            store.execute(q)
        }

        var deep = 0.0, core = 0.0, rem = 0.0, awake = 0.0

        // Filter out .inBed — only count actual stage samples
        let stageSamples = samples.filter {
            HKCategoryValueSleepAnalysis(rawValue: $0.value) != .inBed
        }

        for s in stageSamples {
            let mins = s.endDate.timeIntervalSince(s.startDate) / 60
            switch HKCategoryValueSleepAnalysis(rawValue: s.value) {
            case .asleepDeep: deep  += mins
            case .asleepREM:  rem   += mins
            case .awake:      awake += mins
            default:          core  += mins   // .asleepCore + .asleepUnspecified
            }
        }

        let bedTime  = stageSamples.first?.startDate
        let wakeTime = stageSamples.last?.endDate

        return DailySleepData(
            date:      wakeDay,
            breakdown: SleepBreakdown(deepMinutes: deep, coreMinutes: core, remMinutes: rem, awakeMinutes: awake),
            bedTime:   bedTime,
            wakeTime:  wakeTime
        )
    }

    // MARK: - Heart Rate

    func averageHeartRate(for date: Date) async -> Double? {
        guard isAvailable else { return nil }
        return await averageQuantity(.heartRate, unit: HKUnit(from: "count/min"), on: date)
    }

    // MARK: - HRV

    func averageHRV(for date: Date) async -> Double? {
        guard isAvailable else { return nil }
        return await averageQuantity(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), on: date)
    }

    // MARK: - Respiratory Rate

    func averageRespiratoryRate(for date: Date) async -> Double? {
        guard isAvailable else { return nil }
        return await averageQuantity(.respiratoryRate, unit: HKUnit(from: "count/min"), on: date)
    }

    // MARK: - Private helpers

    private func averageQuantity(_ id: HKQuantityTypeIdentifier, unit: HKUnit, on date: Date) async -> Double? {
        let type  = HKQuantityType(id)
        let start = Calendar.current.startOfDay(for: date)
        let end   = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        let pred  = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: pred, options: .discreteAverage) { _, stats, _ in
                cont.resume(returning: stats?.averageQuantity()?.doubleValue(for: unit))
            }
            store.execute(q)
        }
    }

    // MARK: - Last night stage samples

    /// Returns individual sleep stage samples for the most recent night, sorted by start time.
    func fetchLastNightStageSamples() async -> [SleepStageSample] {
        guard isAvailable else { return [] }
        let calendar = Calendar.current
        let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        // Search up to 7 nights back, return the most recent night with actual stage data.
        for daysBack in 0..<7 {
            let anchor = calendar.date(byAdding: .day, value: -daysBack, to: .now)!
            let noon    = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: anchor)!
            let evening = calendar.date(byAdding: .hour, value: -18, to: noon)!

            let predicate = HKQuery.predicateForSamples(withStart: evening, end: noon, options: .strictStartDate)
            let raw: [HKCategorySample] = await withCheckedContinuation { cont in
                let q = HKSampleQuery(sampleType: type, predicate: predicate,
                                      limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, s, _ in
                    cont.resume(returning: (s as? [HKCategorySample]) ?? [])
                }
                store.execute(q)
            }

            let samples = raw.compactMap { s -> SleepStageSample? in
                guard let v = HKCategoryValueSleepAnalysis(rawValue: s.value), v != .inBed else { return nil }
                let stage: SleepStageSample.Stage
                switch v {
                case .awake:      stage = .awake
                case .asleepREM:  stage = .rem
                case .asleepDeep: stage = .deep
                default:          stage = .core
                }
                return SleepStageSample(stage: stage, start: s.startDate, end: s.endDate)
            }

            if !samples.isEmpty { return samples }
        }
        return []
    }
}

// MARK: - Models

struct SleepStageSample {
    enum Stage: Int, CaseIterable {
        case awake = 0, rem = 1, core = 2, deep = 3

        var label: String {
            switch self { case .awake: "Awake"; case .rem: "REM"; case .core: "Core"; case .deep: "Deep" }
        }

        var color: Color {
            switch self {
            case .awake: Color(red: 0.95, green: 0.40, blue: 0.28)
            case .rem:   Color(red: 0.34, green: 0.75, blue: 0.94)
            case .core:  Color(red: 0.24, green: 0.46, blue: 0.85)
            case .deep:  Color(red: 0.18, green: 0.17, blue: 0.55)
            }
        }
    }
    let stage: Stage
    let start: Date
    let end:   Date
    var duration: TimeInterval { end.timeIntervalSince(start) }
}

import SwiftUI

struct DailySleepData: Identifiable {
    let id    = UUID()
    let date:      Date
    let breakdown: SleepBreakdown
    let bedTime:   Date?
    let wakeTime:  Date?

    var dayLabel: String {
        date.formatted(.dateTime.weekday(.narrow))
    }
    var hasData: Bool { breakdown.totalMinutes > 0 }
}

struct SleepBreakdown {
    let deepMinutes:  Double
    let coreMinutes:  Double
    let remMinutes:   Double
    let awakeMinutes: Double

    var totalMinutes: Double { deepMinutes + coreMinutes + remMinutes + awakeMinutes }
    var totalHours: Int  { Int(totalMinutes) / 60 }
    var totalMins:  Int  { Int(totalMinutes) % 60 }

    var qualityLabel: String {
        guard totalMinutes > 0 else { return "No data" }
        let ratio = (deepMinutes + remMinutes) / totalMinutes
        if ratio > 0.30 { return "Good" }
        if ratio > 0.18 { return "Fair" }
        return "Light"
    }

    static let empty = SleepBreakdown(deepMinutes: 0, coreMinutes: 0, remMinutes: 0, awakeMinutes: 0)
}
