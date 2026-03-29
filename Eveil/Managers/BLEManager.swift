import CoreBluetooth
import SwiftUI

// MARK: - Discovered Device

struct DiscoveredDevice: Identifiable {
    let id = UUID()
    let peripheral: CBPeripheral
    let name: String
    let rssi: Int
}

// MARK: - UART Message

struct UARTMessage: Identifiable {
    enum Direction { case sent, received }
    let id = UUID()
    let timestamp = Date()
    let direction: Direction
    let text: String
}

// MARK: - BLE Manager

@Observable
final class BLEManager: NSObject {

    // Nordic UART Service — used by Adafruit BlueFruit and compatible ESP32 firmwares
    private static let uartServiceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    private static let rxCharUUID      = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E") // iOS → device
    private static let txCharUUID      = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E") // device → iOS

    private static let savedPeripheralKey = "eveil.savedPeripheralUUID"

    enum ConnectionState: String {
        case disconnected = "Not Connected"
        case scanning     = "Scanning…"
        case connecting   = "Connecting…"
        case connected    = "Connected"
    }

    // Published observable state
    var connectionState: ConnectionState = .disconnected
    var rssi: Int?
    var firmwareVersion: String?
    var liveReadings: [Float] = [0, 0, 0, 0]
    var uartLog: [UARTMessage] = []
    var isSynced = false
    var discoveredDevices: [DiscoveredDevice] = []

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var rxChar: CBCharacteristic?
    private var incomingBuffer = ""
    private var rssiTimer: Timer?

    override init() {
        super.init()
        // restoreIdentifier lets CoreBluetooth hand back the session after app relaunch
        central = CBCentralManager(delegate: self, queue: .main,
                                   options: [CBCentralManagerOptionRestoreIdentifierKey: "eveil.central"])
    }

    // MARK: - Public API

    func startScanning() {
        guard central.state == .poweredOn else { return }
        discoveredDevices = []
        connectionState = .scanning
        central.scanForPeripherals(withServices: nil)
    }

    func connect(to device: DiscoveredDevice) {
        central.stopScan()
        peripheral = device.peripheral
        device.peripheral.delegate = self
        connectionState = .connecting
        central.connect(device.peripheral, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
    }

    func disconnect() {
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        UserDefaults.standard.removeObject(forKey: Self.savedPeripheralKey)
        cleanup()
    }

    /// Send a command string to the device over UART (newline appended automatically).
    func send(_ text: String) {
        guard let p = peripheral, let rx = rxChar else { return }
        let data = Data((text + "\n").utf8)
        p.writeValue(data, for: rx, type: .withResponse)
        uartLog.append(UARTMessage(direction: .sent, text: text))
        trimLog()
    }

    // MARK: - Auto-reconnect

    /// Called when CoreBluetooth is ready. Tries to reconnect to the last known device.
    private func attemptAutoReconnect() {
        guard let uuidString = UserDefaults.standard.string(forKey: Self.savedPeripheralKey),
              let uuid = UUID(uuidString: uuidString) else { return }

        // First check if the peripheral is already connected (backgrounded app case)
        let connected = central.retrieveConnectedPeripherals(withServices: [Self.uartServiceUUID])
        if let known = connected.first(where: { $0.identifier == uuid }) {
            reconnect(to: known)
            return
        }

        // Otherwise retrieve by UUID and ask CoreBluetooth to connect when it comes in range
        let known = central.retrievePeripherals(withIdentifiers: [uuid])
        if let p = known.first {
            reconnect(to: p)
        }
    }

    private func reconnect(to p: CBPeripheral) {
        peripheral = p
        p.delegate = self
        connectionState = .connecting
        central.connect(p, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
    }

    // MARK: - Internal

    private func cleanup() {
        rssiTimer?.invalidate()
        rssiTimer = nil
        peripheral = nil
        rxChar = nil
        rssi = nil
        isSynced = false
        incomingBuffer = ""
        connectionState = .disconnected
    }

    private func startRSSIPolling() {
        rssiTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.peripheral?.readRSSI()
        }
    }

    /// Buffer incoming bytes and process complete newline-delimited lines.
    private func handleIncoming(_ raw: String) {
        incomingBuffer += raw
        while let nlIndex = incomingBuffer.firstIndex(of: "\n") {
            let line = String(incomingBuffer[incomingBuffer.startIndex..<nlIndex])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            incomingBuffer = String(incomingBuffer[incomingBuffer.index(after: nlIndex)...])
            guard !line.isEmpty else { continue }
            processLine(line)
        }
    }

    private func processLine(_ line: String) {
        uartLog.append(UARTMessage(direction: .received, text: line))
        trimLog()

        // FSR0:1024 FSR1:2048 FSR2:512 FSR3:3072  — space-separated key:value pairs
        if line.contains("FSR0:") {
            var values: [Float?] = [nil, nil, nil, nil]
            for token in line.split(separator: " ") {
                let parts = token.split(separator: ":")
                guard parts.count == 2,
                      let idx = Int(parts[0].dropFirst(3)),
                      idx >= 0 && idx < 4,
                      let raw = Float(parts[1]) else { continue }
                values[idx] = min(raw / 4095.0, 1.0)
            }
            if values.allSatisfy({ $0 != nil }) {
                liveReadings = values.map { $0! }
                isSynced = true
            }
        }
        // FSR:1024,2048,512,3072  — legacy comma-separated format
        else if line.hasPrefix("FSR:") {
            let parts = line.dropFirst(4).split(separator: ",").compactMap { Float($0) }
            if parts.count >= 4 {
                liveReadings = Array(parts.prefix(4)).map { min($0 / 4095.0, 1.0) }
                isSynced = true
            }
        }
        // FW:1.0.2
        else if line.hasPrefix("FW:") {
            firmwareVersion = String(line.dropFirst(3))
        }
    }

    private func trimLog() {
        if uartLog.count > 300 {
            uartLog.removeFirst(uartLog.count - 300)
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            attemptAutoReconnect()
        } else {
            cleanup()
        }
    }

    // Called when the app is relaunched and CoreBluetooth restores state
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral],
           let p = peripherals.first {
            peripheral = p
            p.delegate = self
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard !discoveredDevices.contains(where: { $0.peripheral.identifier == peripheral.identifier }) else { return }
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Unknown Device"
        discoveredDevices.append(DiscoveredDevice(peripheral: peripheral, name: name, rssi: RSSI.intValue))
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectionState = .connected
        // Save so we can reconnect after relaunch
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: Self.savedPeripheralKey)
        peripheral.discoverServices([Self.uartServiceUUID])
        startRSSIPolling()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        // Unexpected disconnect — try to reconnect automatically
        if UserDefaults.standard.string(forKey: Self.savedPeripheralKey) != nil {
            connectionState = .connecting
            central.connect(peripheral, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
        } else {
            cleanup()
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        cleanup()
    }
}

// MARK: - CBPeripheralDelegate

extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == Self.uartServiceUUID {
            peripheral.discoverCharacteristics([Self.rxCharUUID, Self.txCharUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for char in service.characteristics ?? [] {
            if char.uuid == Self.rxCharUUID {
                rxChar = char
            } else if char.uuid == Self.txCharUUID {
                peripheral.setNotifyValue(true, for: char)
            }
        }
        send("INFO")
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value,
              let str = String(data: data, encoding: .utf8) else { return }
        handleIncoming(str)
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        rssi = RSSI.intValue
    }
}
