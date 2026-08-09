//
//  BluetoothScanner.swift
//  HelloWorld
//
//  Owns the CBCentralManager and performs BLE scanning.
//  Publishes state and discovered devices for SwiftUI to display.
//


import Foundation
import CoreBluetooth
import Observation


/// Wraps Core Bluetooth scanning for Milestone 4A.
///
/// Responsibilities (intentionally limited for this milestone):
///   * Own the CBCentralManager
///   * Report the current Bluetooth state to the UI
///   * Start / stop scans
///   * Collect discovered peripherals, deduplicated by identifier
///
/// It also (as of Task 3):
///   * Initiates connections to specific peripherals
///   * Tracks each device's connection state via DiscoveredPeripheral
///
/// It also (as of Task 4):
///   * Discovers the rope's service and rep-count characteristic
///   * Advances the connection state to `.ready` once the characteristic is in hand
///
/// It also (as of Task 5):
///   * Subscribes to notifications on the rep-count characteristic
///   * Parses incoming ". Reps: N" strings and updates entry.repCount
///
/// It also (as of Task 4D):
///   * Captures the rep characteristic's advertised properties (Read, Notify, …)
///     so the UI can display them for verification.
///   * Defers the `.ready` state until iOS confirms notifications are actually
///     enabled, so "ready" in the UI truly means "we are receiving updates."
///   * Surfaces unparseable notification payloads via the status bar for
///     easier diagnosis of firmware-contract drift.
@Observable
final class BluetoothScanner: NSObject {


    // MARK: - Firmware contract
    //
    // These UUIDs must match the ArduinoBLE definitions in the rope's firmware:
    //     BLEService IMUService("19B10000-E8F2-537E-4F6C-D104768A1214");
    //     BLEStringCharacteristic switchCharacteristic("19B10001-...", BLERead | BLENotify, 20);
    //
    // If firmware changes these UUIDs, update both constants here.
    static let ropeServiceUUID = CBUUID(string: "19B10000-E8F2-537E-4F6C-D104768A1214")
    static let ropeCharacteristicUUID = CBUUID(string: "19B10001-E8F2-537E-4F6C-D104768A1214")


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
        // (We still update RSSI when the callback does fire.)
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
    ///
    /// This is safe to call at any time; it will no-op if the radio isn't
    /// ready, if we're already connected/connecting to this device, or if
    /// something else is obviously wrong. All progress is reported by
    /// mutating `entry.connectionState`, which SwiftUI observes.
    ///
    /// - Parameter entry: The discovered-device row the user tapped.
    func connect(to entry: DiscoveredPeripheral) {
        guard bluetoothState == .poweredOn else {
            statusMessage = "Cannot connect: \(Self.description(for: bluetoothState))"
            return
        }


        // Reject connection attempts that are already in flight or complete.
        // Without this guard, tapping a row twice would enqueue a duplicate
        // connect request; iOS tolerates this but it clutters logs and can
        // trigger surprising delegate callback ordering.
        switch entry.connectionState {
        case .connecting, .connected, .ready:
            return
        case .disconnected, .failed:
            break
        }


        // Stop scanning while we bring up the connection. iOS technically
        // allows scanning and connecting at the same time, but scanning
        // burns extra radio power and can slow the connection handshake
        // on some devices. We'll turn scanning back on later if needed.
        if isScanning {
            centralManager.stopScan()
            isScanning = false
        }


        entry.connectionState = .connecting
        statusMessage = "Connecting to \(entry.displayName)…"


        // options: nil → accept the default connection behavior. In future
        // milestones we may pass CBConnectPeripheralOptionNotifyOnDisconnectionKey
        // to get system notifications when the rope disconnects while our
        // app is backgrounded, but that's out of scope for Task 3.
        centralManager.connect(entry.peripheral, options: nil)
    }


    /// Tear down an active or in-progress connection.
    ///
    /// Included in Task 3 (even though the plan slates it for Task 4) because
    /// during development it's very easy to end up with a "stuck" connection
    /// — e.g. tap-connect during testing, then walk away and iOS keeps the
    /// link alive. Having an explicit disconnect gives us a clean escape.
    ///
    /// - Parameter entry: The device to disconnect.
    func disconnect(from entry: DiscoveredPeripheral) {
        // cancelPeripheralConnection is safe to call in every state — it
        // cancels an in-progress connect attempt or closes an established
        // one. Either way the delegate callback `didDisconnectPeripheral`
        // fires, and that's where we update our state.
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
    /// Used by Task 4D to display the characteristic's advertised capabilities
    /// in the device row, so a developer can eyeball whether the firmware is
    /// exposing the features we expect (specifically Read + Notify for the
    /// rope's rep characteristic).
    ///
    /// We enumerate every property CoreBluetooth defines rather than only the
    /// ones we currently care about, because a diagnostic view that hides
    /// unexpected capabilities is worse than useless — it actively misleads.
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
    ///
    /// At this point we have a live BLE link but we have not yet discovered
    /// services or characteristics — that begins here, in Task 4. We assign
    /// ourselves as the peripheral's delegate and kick off service discovery.
    func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        guard let entry = discoveredDevices.first(where: { $0.id == peripheral.identifier }) else {
            // Shouldn't happen in practice — we only ever initiate connects
            // from entries in `discoveredDevices` — but we log and bail
            // rather than crash if it does.
            statusMessage = "Connected to an unknown peripheral (ignored)."
            return
        }


        entry.connectionState = .connected
        statusMessage = "Connected to \(entry.displayName). Discovering services…"

        // Assign ourselves as the peripheral's delegate BEFORE calling any
        // discovery method. If we don't, the discovery callbacks fire on
        // nil and we silently never hear back. This is one of the most
        // common Core Bluetooth footguns.
        peripheral.delegate = self

        // Ask ONLY for the rope's service UUID. We could pass nil to
        // discover every service the peripheral offers, but filtering:
        //   * is faster (skips services we'd ignore anyway),
        //   * uses less radio time,
        //   * makes intent explicit to future readers of this code.
        peripheral.discoverServices([Self.ropeServiceUUID])
    }


    /// Called by iOS when a connection attempt fails outright (as opposed to
    /// succeeding and later dropping — that's `didDisconnectPeripheral`).
    ///
    /// The `error` parameter is optional; iOS usually populates it with a
    /// CBError describing the reason (out of range, timeout, etc.).
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
    /// `cancelPeripheralConnection` to tear one down deliberately. The two
    /// cases are distinguished by whether `error` is nil (deliberate) or
    /// populated (unexpected drop, e.g. rope went out of range).
    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        guard let entry = discoveredDevices.first(where: { $0.id == peripheral.identifier }) else {
            return
        }


        // Reset rope-specific state so a subsequent reconnect starts clean.
        // (The firmware also resets its own counter on connect, so this
        // keeps our view consistent with the device's own view.) We also
        // drop the characteristic reference and its cached properties —
        // they belong to the now-dead connection and would be invalid to
        // use, or misleading to display, after reconnect.
        entry.repCount = 0
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
    ///
    /// - Parameters:
    ///   - peripheral: the device we heard from
    ///   - advertisementData: the raw ad packet contents (name, service UUIDs, etc.)
    ///   - RSSI: signal strength in dBm, wrapped as NSNumber
    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        // Prefer the name from the advertisement packet if present, because it
        // sometimes arrives before peripheral.name is populated. Fall back to
        // peripheral.name, which may itself be nil for devices that don't
        // advertise a local name at all — DiscoveredPeripheral.displayName
        // will substitute a friendly placeholder in that case.
        let advertisedName =
        (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
        ?? peripheral.name

        let rssiValue = RSSI.intValue

        // Deduplicate by peripheral identifier: if we've heard this device
        // before, update the existing entry in place instead of appending.
        if let existingIndex = discoveredDevices.firstIndex(where: { $0.id == peripheral.identifier }) {
            let existing = discoveredDevices[existingIndex]
            existing.rssi = rssiValue
            existing.lastSeen = Date()

            // The name can improve over time (e.g. nil → "Nelevate Fast Rope").
            // Only overwrite when the incoming advertisement carries a name
            // and the existing entry is still missing one. We deliberately
            // do NOT overwrite an already-known name, because some devices
            // occasionally re-advertise with a shortened or blank name and
            // we don't want the UI to flicker.
            if (existing.name?.isEmpty ?? true), let newName = advertisedName, !newName.isEmpty {
                existing.name = newName
            }
        } else {
            // New device: create an entry. The initializer reads the name
            // directly from peripheral.name, but we may have a better name
            // from the advertisement packet, so we overwrite immediately
            // after construction if the advertised name is more informative.
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
    ///
    /// On success we drill down one more level and ask for the specific
    /// characteristic we care about. On failure we mark the device as failed
    /// so the UI reflects it and the user can retry.
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

        // Find the rope's service among what iOS reports back. Even though we
        // filtered by UUID in the discover call, the services array can still
        // be empty if the peripheral doesn't expose the service we asked for —
        // for example, if we're accidentally talking to a different device with
        // a coincidentally similar name.
        guard let ropeService = peripheral.services?.first(where: { $0.uuid == Self.ropeServiceUUID }) else {
            entry.connectionState = .failed("Rope service not found on this device.")
            statusMessage = "\(entry.displayName) does not expose the expected service."
            return
        }

        statusMessage = "Found rope service on \(entry.displayName). Discovering characteristics…"

        // Same filter-by-UUID reasoning as before: only ask for what we need.
        peripheral.discoverCharacteristics([Self.ropeCharacteristicUUID], for: ropeService)
    }

    /// Called after `discoverCharacteristics(_:for:)` completes.
    ///
    /// As of Task 4D, this method:
    ///   * Locates the expected characteristic
    ///   * Captures its properties string for display in the UI
    ///   * Verifies Notify is supported (fail fast if firmware changes)
    ///   * Kicks off the subscribe request
    ///
    /// Note the state transition: we do NOT flip `entry.connectionState` to
    /// `.ready` here. That happens only after `didUpdateNotificationStateFor`
    /// confirms iOS actually enabled notifications, so the UI's "ready" light
    /// truly means "notifications are live", not "we asked for them."
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

        guard let repCharacteristic = service.characteristics?.first(where: { $0.uuid == Self.ropeCharacteristicUUID }) else {
            entry.connectionState = .failed("Rep characteristic not found on this device.")
            statusMessage = "\(entry.displayName) does not expose the expected characteristic."
            return
        }

        // Record what iOS says this characteristic supports. We do this
        // BEFORE the Notify sanity check so that even if the check fails,
        // the UI can still show what the firmware IS advertising — which
        // is exactly the information a developer needs to diagnose the
        // mismatch.
        entry.characteristicProperties = Self.description(for: repCharacteristic.properties)

        // Sanity check: the firmware declares this characteristic as
        // BLERead | BLENotify. If a future firmware revision drops Notify
        // support, subscribing below would silently do nothing — so we
        // check now and surface the problem while it's easy to diagnose.
        guard repCharacteristic.properties.contains(.notify) else {
            entry.connectionState = .failed("Characteristic does not support notifications.")
            statusMessage = "\(entry.displayName): characteristic missing Notify property."
            return
        }

        entry.repCharacteristic = repCharacteristic
        // Deliberately NOT setting .ready here — see method doc-comment.
        statusMessage = "Found characteristic on \(entry.displayName). Subscribing to rep notifications…"

        // Ask iOS to enable notifications on this characteristic. The
        // firmware pushes a new value every completed rep (". Reps: N").
        // The actual "subscribed / not subscribed" confirmation arrives
        // asynchronously via peripheral(_:didUpdateNotificationStateFor:),
        // which is where we finally advance the state to .ready.
        peripheral.setNotifyValue(true, for: repCharacteristic)
    }

    /// Called after iOS finishes turning notifications on (or off) for a
    /// characteristic, in response to `setNotifyValue(_:for:)`.
    ///
    /// As of Task 4D this is the authoritative "we are live" transition:
    /// only when iOS confirms `isNotifying == true` do we flip the entry
    /// into `.ready`. Any prior state ("Connected — subscribing…") stays
    /// visible until this callback lands, which is typically 50–200 ms
    /// after characteristic discovery.
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
            // Notifications are now genuinely live. Advance the state.
            entry.connectionState = .ready
            statusMessage = "\(entry.displayName) live. Swing the rope to see reps."
        } else {
            // Notifications were turned OFF. We don't do this ourselves in
            // Task 5, so if this fires it means iOS unsubscribed us — usually
            // because the connection dropped. Nothing to do here; the
            // disconnect handler will run separately.
            statusMessage = "Notifications stopped for \(entry.displayName)."
        }
    }

    /// Called every time the peripheral pushes a new value on a subscribed
    /// characteristic. For the Nelevate rope, the firmware writes:
    ///
    ///   * `"Starting..."` once on boot (we ignore it, but do not warn)
    ///   * `". Reps: N"` after every completed rep (we parse N)
    ///
    /// We update both `entry.repCount` (the parsed number, drives the big
    /// counter in the UI) and `entry.lastMessage` (the raw string, useful
    /// for debugging while we're still stabilizing the firmware contract).
    ///
    /// As of Task 4D, payloads that are neither the boot message nor a
    /// parseable "Reps: N" string also produce a visible status-bar
    /// diagnostic. Silent parse failures were making firmware-contract
    /// drift too hard to spot.
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

        // Pull the raw bytes and decode as UTF-8. ArduinoBLE writes plain
        // ASCII, which is a valid UTF-8 subset, so this decode should never
        // fail in practice — but we handle failure defensively rather than
        // force-unwrapping.
        guard let data = characteristic.value,
              let raw = String(data: data, encoding: .utf8) else {
            statusMessage = "Received unreadable payload from \(entry.displayName)."
            return
        }

        // Store the raw string on the entry regardless of whether we can
        // parse it. That way the debug row in the UI always reflects the
        // most recent notification, which is invaluable when tracking down
        // "why isn't the counter moving?" issues.
        entry.lastMessage = raw

        // Parse ". Reps: N".
        //
        // We deliberately look for the substring "Reps: " and read the
        // integer immediately after it, rather than pattern-matching the
        // whole ". Reps: N" shape. That way, if the firmware author ever
        // tweaks the prefix (drops the leading period, adds a device ID,
        // switches to "Rep: " singular, etc.), our parser still works so
        // long as the "Reps: N" fragment is present.
        if let repsRange = raw.range(of: "Reps: ") {
            let numberSubstring = raw[repsRange.upperBound...]
            // trimmingCharacters handles trailing whitespace/newlines that
            // firmware sometimes appends without us noticing.
            let trimmed = numberSubstring.trimmingCharacters(in: .whitespacesAndNewlines)
            if let parsed = Int(trimmed) {
                entry.repCount = parsed
                return
            }
        }

        // The known-benign boot message. Ignored intentionally; if we
        // surfaced this the status bar would spam on every connect.
        let trimmedRaw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedRaw == "Starting..." {
            return
        }

        // Anything else is a genuine surprise: a payload we don't recognize
        // and can't extract a rep count from. Surface it in the status bar
        // so firmware-contract drift is visible instead of silent. The raw
        // string is already visible via lastMessage in the row itself, but
        // most users won't scroll to find it — the status bar is where
        // they're already looking when the counter doesn't move.
        statusMessage = "Unparseable payload from \(entry.displayName): \"\(trimmedRaw)\""
    }
}
