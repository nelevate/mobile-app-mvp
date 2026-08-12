//
//  BluetoothScanner.swift
//  HelloWorld
//
//  Owns the CBCentralManager and performs BLE scanning.
//  Publishes state and discovered devices for SwiftUI to display.
//
//  As of Task 5A.1, all BLE protocol facts (service UUID, characteristic
//  UUID, payload parsing) live in PulseRopeProtocol.swift. This file
//  should no longer contain any hard-coded UUID strings or inline parsing
//  logic — if it does, that's a bug and it belongs in PulseRopeProtocol.
//


import Foundation
import CoreBluetooth
import Observation


/// Wraps Core Bluetooth scanning and connection lifecycle.
///
/// Responsibilities:
///   * Own the CBCentralManager
///   * Report the current Bluetooth state to the UI
///   * Start / stop scans
///   * Collect discovered peripherals, deduplicated by identifier
///   * Initiate and tear down connections
///   * Discover the rope's service and rep-count characteristic
///   * Subscribe to notifications and forward parsed rep counts onto
///     the corresponding DiscoveredPeripheral entry
///
/// Protocol details (UUIDs, payload format) are NOT defined here — see
/// PulseRopeProtocol for those. This class is concerned only with the
/// mechanics of Core Bluetooth, not with what the rope actually says.
@Observable
final class BluetoothScanner: NSObject {


    // MARK: - Published state (SwiftUI reads these)


    /// Current Core Bluetooth radio state. Starts as `.unknown` until
    /// iOS delivers the first `centralManagerDidUpdateState` callback.
    var bluetoothState: CBManagerState = .unknown


    /// True while a scan is in progress.
    var isScanning: Bool = false


    /// Deduplicated list of devices heard during the current (or most recent) scan.
    /// Order is stable: first-seen at the top.
    var discoveredDevices: [DiscoveredPeripheral] = []


    /// Human-readable status line for the UI (e.g. "Scanning…", "Bluetooth is off").
    var statusMessage: String = "Initializing Bluetooth…"


    // MARK: - Private


    private var centralManager: CBCentralManager!


    // MARK: - Init


    override init() {
        super.init()
        // Creating the manager on the main queue keeps delegate callbacks
        // on the main thread, which is what SwiftUI wants for observation.
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }


    // MARK: - Public control


    /// Begin scanning if Bluetooth is powered on. Otherwise update the status
    /// message so the UI can show why nothing is happening.
    func startScan() {
        guard bluetoothState == .poweredOn else {
            statusMessage = "Cannot scan: \(Self.description(for: bluetoothState))"
            return
        }


        // Reset the list for a fresh scan so old (possibly stale) devices
        // don't stick around forever.
        discoveredDevices.removeAll()


        // withServices: nil  → find every advertising BLE device nearby.
        // We use an unfiltered scan because we haven't confirmed the rope
        // advertises its custom service UUID in its ad packet.
        //
        // AllowDuplicates: false  → iOS collapses repeat advertisements from
        // the same device into a single callback until something changes.
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [
                CBCentralManagerScanOptionAllowDuplicatesKey: false
            ]
        )


        isScanning = true
        statusMessage = "Scanning…"
    }


    /// Stop any in-progress scan.
    func stopScan() {
        centralManager.stopScan()
        isScanning = false
        statusMessage = "Scan stopped. Found \(discoveredDevices.count) device(s)."
    }

    /// Initiate a connection to a specific discovered device.
    func connect(to entry: DiscoveredPeripheral) {
        guard bluetoothState == .poweredOn else {
            statusMessage = "Cannot connect: \(Self.description(for: bluetoothState))"
            return
        }


        // Reject connection attempts that are already in flight or complete.
        switch entry.connectionState {
        case .connecting, .connected, .ready:
            return
        case .disconnected, .failed:
            break
        }


        // Stop scanning while we bring up the connection.
        if isScanning {
            centralManager.stopScan()
            isScanning = false
        }


        entry.connectionState = .connecting
        statusMessage = "Connecting to \(entry.displayName)…"

        centralManager.connect(entry.peripheral, options: nil)
    }


    /// Tear down an active or in-progress connection.
    func disconnect(from entry: DiscoveredPeripheral) {
        centralManager.cancelPeripheralConnection(entry.peripheral)
    }

    // MARK: - Helpers


    /// Human-readable description for a CBManagerState value.
    static func description(for state: CBManagerState) -> String {
        switch state {
        case .unknown:      return "Unknown"
        case .resetting:    return "Resetting"
        case .unsupported:  return "Unsupported"
        case .unauthorized: return "Unauthorized"
        case .poweredOff:   return "Powered Off"
        case .poweredOn:    return "Powered On"
        @unknown default:   return "Unrecognized state"
        }
    }


    /// Human-readable description for a CBCharacteristicProperties value.
    ///
    /// Used to display the characteristic's advertised capabilities in the
    /// device row, so a developer can eyeball whether the firmware is
    /// exposing the features we expect (Read + Notify for the rope).
    static func description(for properties: CBCharacteristicProperties) -> String {
        var parts: [String] = []
        if properties.contains(.broadcast)                  { parts.append("Broadcast") }
        if properties.contains(.read)                       { parts.append("Read") }
        if properties.contains(.writeWithoutResponse)       { parts.append("WriteWithoutResponse") }
        if properties.contains(.write)                      { parts.append("Write") }
        if properties.contains(.notify)                     { parts.append("Notify") }
        if properties.contains(.indicate)                   { parts.append("Indicate") }
        if properties.contains(.authenticatedSignedWrites)  { parts.append("SignedWrites") }
        if properties.contains(.extendedProperties)         { parts.append("ExtendedProperties") }
        if properties.contains(.notifyEncryptionRequired)   { parts.append("NotifyEncrypted") }
        if properties.contains(.indicateEncryptionRequired) { parts.append("IndicateEncrypted") }
        return parts.isEmpty ? "None" : parts.joined(separator: " | ")
    }
}


// MARK: - CBCentralManagerDelegate


extension BluetoothScanner: CBCentralManagerDelegate {

    /// Called by iOS whenever the Bluetooth radio state changes, including
    /// the very first time after we create the CBCentralManager.
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothState = central.state

        switch central.state {
        case .poweredOn:
            statusMessage = "Bluetooth ready. Press Scan to search for devices."
        case .poweredOff:
            statusMessage = "Bluetooth is powered off. Turn it on in Settings or Control Center."
            isScanning = false
        case .unauthorized:
            statusMessage = "Bluetooth permission denied. Enable it in Settings → Nelevate."
        case .unsupported:
            statusMessage = "This device does not support Bluetooth Low Energy."
        case .resetting:
            statusMessage = "Bluetooth is resetting. Please wait…"
        case .unknown:
            statusMessage = "Bluetooth state unknown. Waiting for the system…"
        @unknown default:
            statusMessage = "Unrecognized Bluetooth state."
        }
    }

    /// Called by iOS when a connection attempt succeeds.
    func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        guard let entry = discoveredDevices.first(where: { $0.id == peripheral.identifier }) else {
            statusMessage = "Connected to an unknown peripheral (ignored)."
            return
        }


        entry.connectionState = .connected
        statusMessage = "Connected to \(entry.displayName). Discovering services…"

        // Assign ourselves as the peripheral's delegate BEFORE calling any
        // discovery method. Forgetting this is one of the most common
        // Core Bluetooth footguns — callbacks silently fire on nil.
        peripheral.delegate = self

        // Ask ONLY for the rope's service UUID. Filtering here is faster
        // and makes intent explicit to future readers.
        peripheral.discoverServices([PulseRopeProtocol.serviceUUID])
    }


    /// Called by iOS when a connection attempt fails outright.
    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        guard let entry = discoveredDevices.first(where: { $0.id == peripheral.identifier }) else {
            return
        }


        let reason = error?.localizedDescription ?? "Unknown reason"
        entry.connectionState = .failed(reason)
        statusMessage = "Failed to connect to \(entry.displayName): \(reason)"
    }


    /// Called by iOS when an established connection drops, OR when we call
    /// `cancelPeripheralConnection` to tear one down deliberately.
    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        guard let entry = discoveredDevices.first(where: { $0.id == peripheral.identifier }) else {
            return
        }


        // Reset rope-specific state so a subsequent reconnect starts clean.
        // (The firmware also resets its own counter on connect.)
        entry.repCount = 0
        entry.hasValidatedCumulativeCount = false
        entry.lastMessage = nil
        entry.repCharacteristic = nil
        entry.characteristicProperties = nil


        if let error {
            entry.connectionState = .failed(error.localizedDescription)
            statusMessage = "Lost connection to \(entry.displayName): \(error.localizedDescription)"
        } else {
            entry.connectionState = .disconnected
            statusMessage = "Disconnected from \(entry.displayName)."
        }
    }

    /// Called every time the scan hears a BLE advertisement.
    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        // Prefer the name from the advertisement packet if present.
        let advertisedName =
        (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
        ?? peripheral.name

        let rssiValue = RSSI.intValue

        if let existingIndex = discoveredDevices.firstIndex(where: { $0.id == peripheral.identifier }) {
            let existing = discoveredDevices[existingIndex]
            existing.rssi = rssiValue
            existing.lastSeen = Date()

            // Only overwrite when the incoming ad has a name and the
            // existing entry is still missing one — see original notes
            // about flicker prevention.
            if (existing.name?.isEmpty ?? true), let newName = advertisedName, !newName.isEmpty {
                existing.name = newName
            }
        } else {
            let newEntry = DiscoveredPeripheral(peripheral: peripheral, rssi: rssiValue)
            if let advertisedName, !advertisedName.isEmpty {
                newEntry.name = advertisedName
            }
            discoveredDevices.append(newEntry)
        }
    }
}


// MARK: - CBPeripheralDelegate


extension BluetoothScanner: CBPeripheralDelegate {

    /// Called after `discoverServices` completes — success or failure.
    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverServices error: Error?
    ) {
        guard let entry = discoveredDevices.first(where: { $0.id == peripheral.identifier }) else {
            return
        }

        if let error {
            entry.connectionState = .failed("Service discovery failed: \(error.localizedDescription)")
            statusMessage = "Service discovery failed for \(entry.displayName)."
            return
        }

        guard let ropeService = peripheral.services?.first(where: { $0.uuid == PulseRopeProtocol.serviceUUID }) else {
            entry.connectionState = .failed("Rope service not found on this device.")
            statusMessage = "\(entry.displayName) does not expose the expected service."
            return
        }

        statusMessage = "Found rope service on \(entry.displayName). Discovering characteristics…"

        peripheral.discoverCharacteristics([PulseRopeProtocol.repCharacteristicUUID], for: ropeService)
    }

    /// Called after `discoverCharacteristics(_:for:)` completes.
    ///
    /// Captures the characteristic's properties for display, verifies Notify
    /// is supported, and requests a subscription. The transition to `.ready`
    /// happens later, in `didUpdateNotificationStateFor`, only after iOS
    /// confirms notifications are actually live.
    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard let entry = discoveredDevices.first(where: { $0.id == peripheral.identifier }) else {
            return
        }

        if let error {
            entry.connectionState = .failed("Characteristic discovery failed: \(error.localizedDescription)")
            statusMessage = "Characteristic discovery failed for \(entry.displayName)."
            return
        }

        guard let repCharacteristic = service.characteristics?.first(where: { $0.uuid == PulseRopeProtocol.repCharacteristicUUID }) else {
            entry.connectionState = .failed("Rep characteristic not found on this device.")
            statusMessage = "\(entry.displayName) does not expose the expected characteristic."
            return
        }

        // Record what iOS says this characteristic supports BEFORE the
        // Notify sanity check, so a failure still leaves diagnostic
        // info visible in the UI.
        entry.characteristicProperties = Self.description(for: repCharacteristic.properties)

        guard repCharacteristic.properties.contains(.notify) else {
            entry.connectionState = .failed("Characteristic does not support notifications.")
            statusMessage = "\(entry.displayName): characteristic missing Notify property."
            return
        }

        entry.repCharacteristic = repCharacteristic
        statusMessage = "Found characteristic on \(entry.displayName). Subscribing to rep notifications…"

        peripheral.setNotifyValue(true, for: repCharacteristic)
    }

    /// Called after iOS finishes turning notifications on (or off) for a
    /// characteristic. This is the authoritative "we are live" transition.
    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard let entry = discoveredDevices.first(where: { $0.id == peripheral.identifier }) else {
            return
        }

        if let error {
            entry.connectionState = .failed("Subscribe failed: \(error.localizedDescription)")
            statusMessage = "Could not subscribe to \(entry.displayName): \(error.localizedDescription)"
            return
        }

        if characteristic.isNotifying {
            entry.connectionState = .ready
            statusMessage = "\(entry.displayName) live. Swing the rope to see reps."
        } else {
            // Notifications turned OFF. We don't do this ourselves, so if
            // this fires it means iOS unsubscribed us — usually because
            // the connection dropped. The disconnect handler will run
            // separately.
            statusMessage = "Notifications stopped for \(entry.displayName)."
        }
    }

    /// Called every time the peripheral pushes a new value on a subscribed
    /// characteristic.
    ///
    /// As of Task 5A.1, the actual byte-to-meaning translation lives in
    /// `PulseRopeProtocol.parse(_:)`. This method's only job is to route
    /// the parsed result to the right side effects: update the entry's
    /// rep count, update the debug string, or surface a status message
    /// for unrecognized payloads.
    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard let entry = discoveredDevices.first(where: { $0.id == peripheral.identifier }) else {
            return
        }

        if let error {
            statusMessage = "Read error from \(entry.displayName): \(error.localizedDescription)"
            return
        }

        guard let data = characteristic.value else {
            statusMessage = "Received empty payload from \(entry.displayName)."
            return
        }

        // Preserve the raw string on the entry regardless of parse outcome.
        // That way the debug row in the UI always shows the most recent
        // notification exactly as received, which is invaluable when
        // tracking down "why isn't the counter moving?" bugs.
        entry.lastMessage = String(data: data, encoding: .utf8) ?? "<\(data.count) non-utf8 bytes>"
        // TEMP DIAGNOSTIC (Task 5A.2): log the raw bytes and decoded
                // string of every notification so we can see exactly what the
                // firmware is sending. Remove once handshake detection works.
                let rawString = String(data: data, encoding: .utf8) ?? "<non-utf8>"
                let hexBytes = data.map { String(format: "%02x", $0) }.joined(separator: " ")
                print("📡 BLE notify — utf8: \(rawString.debugDescription)  hex: \(hexBytes)")

        switch PulseRopeProtocol.parse(data) {
        case .starting:
                    // Kept for forward compatibility: if a future firmware build
                    // does send a "Starting..." handshake, we defensively re-
                    // baseline the counter. Current firmware (as of Aug 2026)
                    // does NOT send this — see the .repCount case for the actual
                    // validation trigger.
                    entry.repCount = 0
                    entry.hasValidatedCumulativeCount = true

        case .repCount(let count):
                    // Validate the counter on the first successfully parsed rep
                    // event of this connection. Rationale: the firmware resets
                    // its counter to 0 on connect, so any count we see here is
                    // a trustworthy cumulative count for the current session —
                    // regardless of whether we caught the first swing or the
                    // user swung a few times before we finished subscribing.
                    //
                    // This replaces the original handshake-based validation
                    // because empirical testing (Task 5A.2) showed the current
                    // firmware doesn't send a "Starting..." message; the first
                    // notification is always a rep count.
                    if !entry.hasValidatedCumulativeCount {
                        entry.hasValidatedCumulativeCount = true
                    }
                    entry.repCount = count

        case .unknown(let raw):
            // Genuine surprise: a payload the parser didn't recognize.
            // Surface it in the status bar so firmware-contract drift is
            // visible instead of silent.
            statusMessage = "Unparseable payload from \(entry.displayName): \"\(raw)\""
        }
    }
}
