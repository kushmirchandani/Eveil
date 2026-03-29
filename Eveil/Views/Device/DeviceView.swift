import SwiftUI
import SwiftData
import CoreBluetooth

struct DeviceView: View {
    @Environment(BLEManager.self) private var ble
    @Query private var profiles: [CalibrationProfile]

    @State private var showCalibrationFlow = false
    @State private var showDevicePicker = false
    @State private var showDevTools = false

    private var activeProfile: CalibrationProfile? {
        profiles.first(where: \.isActive)
    }

    var body: some View {
        NavigationStack {
            List {

                // MARK: Connection Card
                Section {
                    ConnectionStatusCard(ble: ble, activeProfile: activeProfile)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                // MARK: Live Sensor (connected only)
                if ble.connectionState == .connected {
                    Section("Live Sensor") {
                        LiveSensorView(readings: ble.liveReadings)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }

                // MARK: Calibration
                Section("Calibration") {
                    if let profile = activeProfile, profile.isCalibrated {
                        LabeledContent("Status") {
                            Label("Calibrated", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                        }
                        LabeledContent("Last calibrated") {
                            Text(profile.calibratedAt, style: .relative)
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }

                        // Bare mattress thresholds — always shown when calibrated
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Bare mattress thresholds")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 12) {
                                ForEach(0..<4, id: \.self) { i in
                                    VStack(spacing: 3) {
                                        Text("Z\(i + 1)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text(i < profile.emptyBaselines.count
                                             ? String(format: "%.0f", profile.emptyBaselines[i])
                                             : "—")
                                            .font(.caption.weight(.semibold))
                                            .monospacedDigit()
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    } else {
                        Label("Not calibrated", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }

                    Button {
                        showCalibrationFlow = true
                    } label: {
                        Label("Run Calibration", systemImage: "slider.horizontal.3")
                            .foregroundStyle(.white)
                    }
                    .disabled(ble.connectionState != .connected)
                }

                // MARK: Hardware Info
                Section("Hardware") {
                    LabeledContent("Firmware") {
                        Text(ble.firmwareVersion ?? "—")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Signal") {
                        if let rssi = ble.rssi {
                            SignalStrengthLabel(rssi: rssi)
                        } else {
                            Text("—").foregroundStyle(.secondary)
                        }
                    }
                    Button {
                        showDevTools = true
                    } label: {
                        Label("Developer Tools", systemImage: "hammer.fill")
                            .foregroundStyle(.white)
                    }
                    .disabled(ble.connectionState != .connected)
                }

                // MARK: Connect / Disconnect
                Section {
                    switch ble.connectionState {
                    case .disconnected:
                        Button {
                            ble.startScanning()
                            showDevicePicker = true
                        } label: {
                            Label("Scan for Device", systemImage: "antenna.radiowaves.left.and.right")
                                .frame(maxWidth: .infinity, alignment: .center)
                                .foregroundStyle(.white)
                        }
                    case .scanning, .connecting:
                        HStack {
                            Spacer()
                            ProgressView()
                                .tint(.orange)
                            Text(ble.connectionState.rawValue)
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                            Spacer()
                        }
                        .onTapGesture { showDevicePicker = true }
                        Button(role: .destructive) {
                            ble.disconnect()
                        } label: {
                            Text("Cancel")
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    case .connected:
                        Button(role: .destructive) {
                            ble.disconnect()
                        } label: {
                            Label("Disconnect", systemImage: "minus.circle")
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(isPresented: $showCalibrationFlow) {
                CalibrationFlowView(ble: ble)
            }
            .sheet(isPresented: $showDevicePicker) {
                DevicePickerSheet(ble: ble, isPresented: $showDevicePicker)
            }
            .sheet(isPresented: $showDevTools) {
                DevToolsSheet(ble: ble)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
        .background {
            ZStack {
                if let url = Bundle.main.url(forResource: "onboarding", withExtension: "mp4") {
                    LoopingVideoPlayer(url: url)
                        .ignoresSafeArea()
                } else {
                    Color.black.ignoresSafeArea()
                }
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.1), location: 0),
                        .init(color: .black.opacity(0.3), location: 0.4),
                        .init(color: .black.opacity(0.85), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }
        }
    }
}

// MARK: - Connection Status Card

private struct ConnectionStatusCard: View {
    let ble: BLEManager
    let activeProfile: CalibrationProfile?

    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.45

    private var isOccupied: Bool {
        guard ble.connectionState == .connected, let profile = activeProfile else { return false }
        let rawReadings = ble.liveReadings.map { $0 * 4095 }
        return profile.isOccupied(readings: rawReadings)
    }

    private var glowColor: Color {
        guard ble.connectionState == .connected else { return .clear }
        return isOccupied ? .orange : .green
    }

    private var icon: String {
        switch ble.connectionState {
        case .disconnected: "sensor.tag.radiowaves.forward"
        case .scanning, .connecting: "antenna.radiowaves.left.and.right"
        case .connected: "sensor.tag.radiowaves.forward.fill"
        }
    }

    private var statusColor: Color {
        switch ble.connectionState {
        case .disconnected: .secondary
        case .scanning, .connecting: .orange
        case .connected: isOccupied ? .orange : .green
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                // Glow layer — pulses when occupied
                Image("Eveil")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 260, height: 160)
                    .blur(radius: 28)
                    .opacity(ble.connectionState == .disconnected ? 0 : pulseOpacity)
                    .scaleEffect(isOccupied ? pulseScale : 1.0)
                    .colorMultiply(glowColor)

                // Sharp device image
                Image("Eveil")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 260, height: 160)
                    .shadow(color: glowColor.opacity(ble.connectionState == .disconnected ? 0 : 0.65), radius: 22)
                    .scaleEffect(isOccupied ? pulseScale : 1.0)
            }
            .animation(.easeInOut(duration: 0.6), value: ble.connectionState)
            .animation(.easeInOut(duration: 0.5), value: isOccupied)
            .onAppear { startPulse() }
            .onChange(of: isOccupied) { _, occupied in
                if !occupied {
                    pulseScale = 1.0
                    pulseOpacity = 0.45
                }
            }

            // Status row
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
                    .symbolEffect(.pulse, isActive: ble.connectionState == .scanning || ble.connectionState == .connecting)

                Text("Éveil Sensor")
                    .font(.subheadline.weight(.semibold))

                Text("·")
                    .foregroundStyle(.tertiary)

                Text(isOccupied ? "In Bed" : ble.connectionState.rawValue)
                    .font(.subheadline)
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
                    .contentTransition(.identity)
            }

            if ble.connectionState == .connected {
                SyncBadge(isSynced: ble.isSynced)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal)
    }

    private func startPulse() {
        withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
            pulseScale = 1.08
            pulseOpacity = 0.65
        }
    }
}

// MARK: - Sync Badge

private struct SyncBadge: View {
    let isSynced: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isSynced ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(isSynced ? "Synced" : "Waiting")
                .font(.caption2.weight(.medium))
                .foregroundStyle(isSynced ? .green : .orange)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

// MARK: - Signal Strength Label

private struct SignalStrengthLabel: View {
    let rssi: Int

    private var label: String {
        switch rssi {
        case ..<(-80): "Weak"
        case -80 ..< -60: "Fair"
        case -60 ..< -40: "Good"
        default: "Excellent"
        }
    }

    private var color: Color {
        switch rssi {
        case ..<(-80): .red
        case -80 ..< -60: .orange
        default: .green
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundStyle(color)
            Text("(\(rssi) dBm)")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }
}

// MARK: - Live Sensor View

private struct LiveSensorView: View {
    let readings: [Float]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pressure Zones")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            HStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { i in
                    ZoneIndicator(zone: i + 1, value: i < readings.count ? readings[i] : 0)
                }
            }
        }
        .padding(20)
        .glassEffect(in: .rect(cornerRadius: 20))
        .padding(.horizontal)
        .padding(.vertical, 4)
    }
}

private struct ZoneIndicator: View {
    let zone: Int
    let value: Float

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(height: 60)

                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.7))
                    .frame(height: CGFloat(value) * 60)
                    .animation(.spring(response: 0.3), value: value)
            }
            .frame(maxWidth: .infinity)

            Text("Z\(zone)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - UART Console

private struct UARTConsoleView: View {
    let ble: BLEManager
    @State private var commandInput = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Log scroll area
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(ble.uartLog) { msg in
                            UARTMessageRow(message: msg)
                                .id(msg.id)
                        }
                    }
                    .padding(12)
                }
                .frame(height: 200)
                .onChange(of: ble.uartLog.count) { _, _ in
                    if let last = ble.uartLog.last {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()
                .opacity(0.2)

            // Send bar
            HStack(spacing: 10) {
                TextField("Command…", text: $commandInput)
                    .font(.system(.caption, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($inputFocused)
                    .onSubmit { sendCommand() }

                Button(action: sendCommand) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title3)
                        .foregroundStyle(commandInput.isEmpty ? Color.secondary : Color.white)
                }
                .disabled(commandInput.isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .glassEffect(in: .rect(cornerRadius: 20))
        .padding(.horizontal)
        .padding(.vertical, 4)
    }

    private func sendCommand() {
        let trimmed = commandInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        ble.send(trimmed)
        commandInput = ""
    }
}

private struct UARTMessageRow: View {
    let message: UARTMessage

    private var isSent: Bool { message.direction == .sent }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if isSent { Spacer() }

            VStack(alignment: isSent ? .trailing : .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if isSent {
                        Text(message.timestamp, style: .time)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    Text(isSent ? "→" : "←")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(isSent ? .white : .secondary)
                    if !isSent {
                        Text(message.timestamp, style: .time)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
                Text(message.text)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(isSent ? .white : .primary)
                    .textSelection(.enabled)
            }

            if !isSent { Spacer() }
        }
    }
}

// MARK: - Calibration Flow

struct CalibrationFlowView: View {
    let ble: BLEManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var countdownActive = false
    @State private var countdown = 5
    @State private var emptySnapshot: [Float] = []

    private let steps: [CalibrationStep] = [
        .init(title: "Empty Bed",
              instruction: "Make sure the bed is completely empty, then tap Continue.",
              icon: "bed.double",
              command: "CAL_EMPTY"),
        .init(title: "Lie Down",
              instruction: "Lie in your normal sleeping position and stay still for 5 seconds.",
              icon: "figure.sleep",
              command: "CAL_OCCUPIED"),
        .init(title: "Complete",
              instruction: "Calibration saved. Your sleep detection thresholds are set.",
              icon: "checkmark.seal.fill",
              command: nil),
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                Image(systemName: steps[step].icon)
                    .font(.system(size: 64))
                    .foregroundStyle(.white)
                    .symbolEffect(.bounce, value: step)

                VStack(spacing: 12) {
                    Text(steps[step].title)
                        .font(.title2.weight(.semibold))
                    Text(steps[step].instruction)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    // Countdown shown during lie-down step
                    if countdownActive {
                        Text("\(countdown)")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText(countsDown: true))
                            .animation(.default, value: countdown)
                    }
                }

                // Progress dots
                HStack(spacing: 8) {
                    ForEach(0..<steps.count, id: \.self) { i in
                        Circle()
                            .fill(i == step ? Color.white : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }

                Spacer()

                Button {
                    advance()
                } label: {
                    Text(step < steps.count - 1 ? "Continue" : "Done")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.white)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .disabled(countdownActive)
                .padding(.horizontal)
            }
            .padding(.bottom, 32)
            .navigationTitle("Calibration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func advance() {
        let current = steps[step]
        if let cmd = current.command {
            ble.send(cmd)
        }

        // Snapshot empty-bed readings before moving off step 0
        if step == 0 && ble.liveReadings.count == 4 {
            emptySnapshot = ble.liveReadings.map { $0 * 4095 }
        }

        if step == 1 {
            // Lie-down step: count down 5 seconds before auto-advancing
            countdownActive = true
            countdown = 5
            runCountdown()
        } else if step < steps.count - 1 {
            withAnimation { step += 1 }
        } else {
            saveCalibrationProfile()
            dismiss()
        }
    }

    private func runCountdown() {
        guard countdown > 0 else {
            countdownActive = false
            withAnimation { step += 1 }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            countdown -= 1
            runCountdown()
        }
    }

    private func saveCalibrationProfile() {
        let profile = CalibrationProfile()
        profile.isActive = true
        profile.calibratedAt = Date()
        if !emptySnapshot.isEmpty {
            profile.emptyBaselines = emptySnapshot
        }
        if ble.liveReadings.count == 4 {
            profile.occupiedBaselines = ble.liveReadings.map { $0 * 4095 }
        }
        modelContext.insert(profile)
    }
}

// MARK: - Device Picker Sheet

private struct DevicePickerSheet: View {
    let ble: BLEManager
    @Binding var isPresented: Bool

    private var filteredDevices: [DiscoveredDevice] {
        ble.discoveredDevices.filter { $0.name.localizedCaseInsensitiveContains("eveil") }
    }

    var body: some View {
        NavigationStack {
            List {
                if ble.connectionState == .scanning {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView().tint(.white)
                            Text("Scanning for devices…")
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                        }
                        .listRowBackground(Color.clear)
                    }
                }

                if filteredDevices.isEmpty && ble.connectionState == .scanning {
                    Section {
                        Text("Make sure your Éveil sensor is powered on and nearby.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .listRowBackground(Color.clear)
                    }
                } else {
                    Section("Nearby Devices") {
                        ForEach(filteredDevices) { device in
                            Button {
                                ble.connect(to: device)
                                isPresented = false
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(device.name)
                                            .foregroundStyle(.primary)
                                            .font(.subheadline.weight(.medium))
                                        Text(device.peripheral.identifier.uuidString.prefix(8) + "…")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    SignalStrengthLabel(rssi: device.rssi)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        ble.disconnect()
                        isPresented = false
                    }
                }
            }
            .onChange(of: ble.connectionState) { _, state in
                if state == .connected { isPresented = false }
            }
        }
    }
}

// MARK: - Developer Tools Sheet

private struct DevToolsSheet: View {
    let ble: BLEManager

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Action buttons
                HStack(spacing: 12) {
                    Button {
                        ble.send("FORCE ALARM")
                    } label: {
                        Label("Fire Alarm", systemImage: "alarm.waves.left.and.right.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.red.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.red)
                    }

                    Button {
                        ble.send("ARM")
                    } label: {
                        Label("ARM", systemImage: "sensor.tag.radiowaves.forward.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.green.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.green)
                    }

                    Button {
                        ble.send("ALARM KILL")
                        ble.send("ARM")
                    } label: {
                        Label("Kill Alarm", systemImage: "xmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()

                Divider()

                // UART console
                UARTConsoleView(ble: ble)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
            }
            .navigationTitle("Developer Tools")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct CalibrationStep {
    let title: String
    let instruction: String
    let icon: String
    let command: String?
}

#Preview {
    let schema = Schema([SleepSession.self, AlarmConfig.self, CalibrationProfile.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])
    DeviceView()
        .modelContainer(container)
        .environment(BLEManager())
}
