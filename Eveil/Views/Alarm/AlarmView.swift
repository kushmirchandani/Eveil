import SwiftUI
import SwiftData

// Embeddable content used inside Settings → NavigationLink
struct AlarmSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var configs: [AlarmConfig]

    @State private var showTimePicker = false
    @State private var showSoundPicker = false

    private var config: AlarmConfig {
        if let existing = configs.first { return existing }
        let new = AlarmConfig()
        modelContext.insert(new)
        return new
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                WakeTimeCard(config: config, showPicker: $showTimePicker)
                PrepCard(config: config)
                BehaviorCard(config: config)
                DismissalCard(config: config)
                SoundCard(config: config, showPicker: $showSoundPicker)
                NoSnoozeCard()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .navigationTitle("Alarm")
        .sheet(isPresented: $showTimePicker) {
            TimePickerSheet(config: config)
                .presentationDetents([.height(320)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSoundPicker) {
            SoundPackPicker(selectedPack: Bindable(config).selectedSoundPack)
        }
    }
}

struct AlarmView: View {
    var body: some View {
        NavigationStack {
            AlarmSettingsView()
        }
    }
}

// MARK: - Wake Time Card

private struct WakeTimeCard: View {
    @Bindable var config: AlarmConfig
    @Binding var showPicker: Bool

    private var timeString: String {
        let h = config.earliestWakeHour
        let m = config.earliestWakeMinute
        let hour12 = h == 0 ? 12 : (h > 12 ? h - 12 : h)
        let ampm = h < 12 ? "AM" : "PM"
        return String(format: "%d:%02d %@", hour12, m, ampm)
    }

    var body: some View {
        Button { showPicker = true } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Toggle("", isOn: $config.isEnabled)
                        .labelsHidden()
                        .tint(.green)
                    Text(config.isEnabled ? "Alarm on" : "Alarm off")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(config.isEnabled ? .white : .secondary)
                }

                Text("Your wake-up window opens at")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(alignment: .lastTextBaseline, spacing: 0) {
                    Text(timeString)
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.bottom, 8)
                }
            }
            .padding(22)
            .glassEffect(in: .rect(cornerRadius: 22))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Time Picker Sheet

private struct TimePickerSheet: View {
    @Bindable var config: AlarmConfig
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Wake-up time")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 8)

            DatePicker(
                "",
                selection: Binding(
                    get: { config.earliestWakeDate },
                    set: { date in
                        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                        config.earliestWakeHour   = c.hour   ?? 7
                        config.earliestWakeMinute = c.minute ?? 0
                    }
                ),
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
            .datePickerStyle(.wheel)
            .padding(.horizontal, 12)
        }
    }
}

// MARK: - Prep Card

private struct PrepCard: View {
    @Bindable var config: AlarmConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("You'll need")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                InlineStepper(
                    value: $config.preparationBufferMinutes,
                    range: 15...180,
                    step: 15,
                    label: { "\($0) min" }
                )
                Spacer()
            }

            Text("to prepare before leaving.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(22)
        .glassEffect(in: .rect(cornerRadius: 22))
    }
}

// MARK: - Behavior Card

private struct BehaviorCard: View {
    @Bindable var config: AlarmConfig

    private var retriggerMinutes: Binding<Int> {
        Binding(
            get: { config.retriggerIntervalSeconds / 60 },
            set: { config.retriggerIntervalSeconds = $0 * 60 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("The alarm rings for")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                InlineStepper(
                    value: $config.escalationTimerSeconds,
                    range: 20...120,
                    step: 5,
                    label: { "\($0) sec" }
                )
                Spacer()
            }

            Text("then waits")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                InlineStepper(
                    value: retriggerMinutes,
                    range: 1...10,
                    step: 1,
                    label: { "\($0) min" }
                )
                Spacer()
            }

            Text("before trying again if you're still in bed.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(22)
        .glassEffect(in: .rect(cornerRadius: 22))
    }
}

// MARK: - Dismissal Card

private struct DismissalCard: View {
    @Bindable var config: AlarmConfig

    private var holdSecondsInt: Binding<Int> {
        Binding(
            get: { Int(config.dismissalHoldSeconds) },
            set: { config.dismissalHoldSeconds = Double($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Stay out of bed for")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                InlineStepper(
                    value: holdSecondsInt,
                    range: 3...15,
                    step: 1,
                    label: { "\($0) sec" }
                )
                Spacer()
            }

            Text("to dismiss the alarm.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(22)
        .glassEffect(in: .rect(cornerRadius: 22))
    }
}

// MARK: - Sound Card

private struct SoundCard: View {
    @Bindable var config: AlarmConfig
    @Binding var showPicker: Bool

    var body: some View {
        Button { showPicker = true } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sound")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(config.selectedSoundPack.capitalized)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(22)
            .glassEffect(in: .rect(cornerRadius: 22))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - No Snooze Card

private struct NoSnoozeCard: View {
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "hand.raised.slash.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text("No snooze.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Text("This is a product decision, not an oversight.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(22)
        .glassEffect(in: .rect(cornerRadius: 22))
    }
}

// MARK: - Inline Stepper

private struct InlineStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let label: (Int) -> String

    var body: some View {
        HStack(spacing: 0) {
            Button {
                if value - step >= range.lowerBound {
                    value -= step
                }
            } label: {
                Image(systemName: "minus")
                    .font(.callout.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(value <= range.lowerBound)

            Text(label(value))
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .frame(minWidth: 80)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.2, dampingFraction: 0.8), value: value)

            Button {
                if value + step <= range.upperBound {
                    value += step
                }
            } label: {
                Image(systemName: "plus")
                    .font(.callout.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(value >= range.upperBound)
        }
        .foregroundStyle(.primary)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

// MARK: - Sound Pack Picker

private struct SoundPackPicker: View {
    @Binding var selectedPack: String
    @Environment(\.dismiss) private var dismiss

    private let packs = ["default", "nature", "tones", "harsh", "gradual"]

    var body: some View {
        NavigationStack {
            List(packs, id: \.self) { pack in
                HStack {
                    Text(pack.capitalized)
                    Spacer()
                    if pack == selectedPack {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.white)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedPack = pack
                    dismiss()
                }
            }
            .navigationTitle("Sound Pack")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    let schema = Schema([SleepSession.self, AlarmConfig.self, CalibrationProfile.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])
    AlarmView()
        .modelContainer(container)
}
