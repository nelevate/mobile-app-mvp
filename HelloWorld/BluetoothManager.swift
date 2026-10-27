
//
//  BluetoothManager.swift
//  HelloWorld
//
//  Created by Rafiq Whitley on 10/25/26.
//

import CoreBluetooth
import Foundation
import Observation

@Observable
final class BluetoothManager: BluetoothCentralDelegate, BluetoothPeripheralDelegate {

    var bluetoothState: CBManagerState = .unknown
    var isScanning = false
    var discoveredDevices: [DiscoveredPeripheral] = []
    var statusMessage = "Initializing Bluetooth..."
    @ObservationIgnored
    private let lastConnectedPeripheralIDKey = "lastConnectedPeripheralID"

    @ObservationIgnored
    private let centralManager: any BluetoothCentralManaging

    @ObservationIgnored
    private let reconnectDelay: (Int) -> TimeInterval

    @ObservationIgnored
    private let maxReconnectAttempts = 5

    @ObservationIgnored
    private var reconnectAttempts: [UUID: Int] = [:]

    @ObservationIgnored
    private var reconnectGeneration: [UUID: Int] = [:]

    @ObservationIgnored
    private var pendingReconnects: Set<UUID> = []

    @ObservationIgnored
    private var autoReconnectDevices: Set<UUID> = []

    @ObservationIgnored
    private var intentionalDisconnects: Set<UUID> = []

    init(
        centralManagerFactory: () -> any BluetoothCentralManaging = {
            CoreBluetoothCentralAdapter()
        },
        reconnectDelay: @escaping (Int) -> TimeInterval = {
            min(pow(2.0, Double($0 - 1)), 16.0)
        }
    ) {
        let central = centralManagerFactory()

        self.centralManager = central
        self.reconnectDelay = reconnectDelay

        central.delegate = self
    }

    // MARK: - Scanning

    func startScan() {
        guard bluetoothState == .poweredOn else {
            statusMessage = "Cannot scan: \(Self.description(for: bluetoothState))"
            return
        }

        discoveredDevices.removeAll()
        centralManager.scanForPeripherals()
        isScanning = true
        statusMessage = "Scanning…"
    }

    func stopScan() {
        centralManager.stopScan()
        isScanning = false
        statusMessage = "Scan stopped. Found \(discoveredDevices.count) device(s)."
    }
    
    private var lastConnectedPeripheralID: UUID? {
        get {
            guard let value = UserDefaults.standard.string(
                forKey: lastConnectedPeripheralIDKey
            ) else {
                return nil
            }

            return UUID(uuidString: value)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(
                    newValue.uuidString,
                    forKey: lastConnectedPeripheralIDKey
                )
            } else {
                UserDefaults.standard.removeObject(
                    forKey: lastConnectedPeripheralIDKey
                )
            }
        }
    }

    // MARK: - Connection

    func connect(to entry: DiscoveredPeripheral) {
        guard bluetoothState == .poweredOn else {
            statusMessage = "Cannot connect: \(Self.description(for: bluetoothState))"
            return
        }

        switch entry.connectionState {
        case .connecting, .connected, .ready:
            return

        case .disconnected, .failed:
            break
        }

        let id = entry.id

        intentionalDisconnects.remove(id)
        autoReconnectDevices.insert(id)
        invalidateReconnect(for: id, resetAttempts: true)

        if isScanning {
            centralManager.stopScan()
            isScanning = false
        }

        entry.connectionState = .connecting
        statusMessage = "Connecting to \(entry.displayName)…"

        centralManager.connect(to: entry.peripheral)
    }

    func disconnect(from entry: DiscoveredPeripheral) {
        let id = entry.id

        // A manual disconnect must never trigger automatic reconnection.
        intentionalDisconnects.insert(id)
        autoReconnectDevices.remove(id)
        invalidateReconnect(for: id, resetAttempts: true)

        centralManager.cancelConnection(to: entry.peripheral)
    }

    // MARK: - Central callbacks

    func centralDidUpdateState(_ state: CBManagerState) {
        bluetoothState = state

        switch state {
        case .poweredOn:
            statusMessage = "Bluetooth ready. Press Scan to search for devices."

            // Resume eligible reconnection attempts after Bluetooth returns.
            for id in autoReconnectDevices {
                guard let entry = discoveredDevices.first(where: { $0.id == id })
                else {
                    continue
                }

                switch entry.connectionState {
                case .disconnected, .failed:
                    scheduleReconnect(for: entry)
                case .connecting, .connected, .ready:
                    break
                }
            }

        case .poweredOff:
            statusMessage = "Bluetooth is powered off. Turn it on in Settings or Control Center."
            isScanning = false

        case .unauthorized:
            statusMessage = "Bluetooth permission denied. Enable it in Settings."

        case .unsupported:
            statusMessage = "This device does not support Bluetooth Low Energy."

        case .resetting:
            statusMessage = "Bluetooth is resetting. Please wait…"
            isScanning = false

        case .unknown:
            statusMessage = "Bluetooth state unknown. Waiting for the system…"

        @unknown default:
            statusMessage = "Unrecognized Bluetooth state."
        }
    }

    func centralDidDiscover(
        _ peripheral: any BluetoothPeripheralManaging,
        advertisedName: String?,
        rssi: Int
    ) {
        if let existing = discoveredDevices.first(where: {
            $0.id == peripheral.identifier
        }) {
            existing.rssi = rssi
            existing.lastSeen = Date()

            if (existing.name?.isEmpty ?? true),
               let advertisedName,
               !advertisedName.isEmpty {
                existing.name = advertisedName
            }

            autoConnectIfLastDevice(existing)
            return
        }

        let entry = DiscoveredPeripheral(
            peripheral: peripheral,
            rssi: rssi
        )

        if let advertisedName, !advertisedName.isEmpty {
            entry.name = advertisedName
        }

        discoveredDevices.append(entry)

        autoConnectIfLastDevice(entry)
    }
    
    private func autoConnectIfLastDevice(
        _ entry: DiscoveredPeripheral
    ) {
        guard entry.id == lastConnectedPeripheralID else {
            return
        }

        guard bluetoothState == .poweredOn else {
            return
        }

        switch entry.connectionState {
        case .disconnected, .failed:
            statusMessage = "Found previously connected device. Connecting to \(entry.displayName)…"
            connect(to: entry)

        case .connecting, .connected, .ready:
            return
        }
    }

    func centralDidConnect(_ peripheral: any BluetoothPeripheralManaging) {
        guard let entry = entry(for: peripheral) else {
            statusMessage = "Connected to an unknown peripheral (ignored)."
            return
        }
        entry.batteryLevel = nil

        let id = entry.id
        lastConnectedPeripheralID = id
        invalidateReconnect(for: id, resetAttempts: false)

        // The device resets its cumulative counter on connection.
        entry.repCount = 0
        entry.hasValidatedCumulativeCount = false
        entry.lastMessage = nil
        entry.repCharacteristic = nil
        entry.characteristicProperties = nil

        entry.connectionState = .connected
        statusMessage = "Connected to \(entry.displayName). Discovering services…"

        peripheral.delegate = self
        peripheral.discoverServices([
            PulseRopeProtocol.serviceUUID,
            BluetoothBatteryProtocol.serviceUUID
        ])
    }

    func centralDidFailToConnect(
        _ peripheral: any BluetoothPeripheralManaging,
        error: Error?
    ) {
        guard let entry = entry(for: peripheral) else { return }

        let id = entry.id
        let reason = error?.localizedDescription ?? "Unknown reason"

        entry.connectionState = .failed(reason)
        statusMessage = "Failed to connect to \(entry.displayName): \(reason)"

        guard autoReconnectDevices.contains(id),
              !intentionalDisconnects.contains(id) else {
            return
        }

        scheduleReconnect(for: entry)
    }

    func centralDidDisconnect(
        _ peripheral: any BluetoothPeripheralManaging,
        error: Error?
    ) {
        guard let entry = entry(for: peripheral) else { return }

        let id = entry.id
        let wasIntentional = intentionalDisconnects.remove(id) != nil

        // Preserve the last rep count after disconnecting.
        if let error {
            entry.connectionState = .failed(error.localizedDescription)
            statusMessage = "Lost connection to \(entry.displayName): \(error.localizedDescription)"
        } else {
            entry.connectionState = .disconnected
            statusMessage = "Disconnected from \(entry.displayName)."
        }

        entry.hasValidatedCumulativeCount = false
        entry.lastMessage = nil
        entry.repCharacteristic = nil
        entry.characteristicProperties = nil

        if wasIntentional {
            invalidateReconnect(for: id, resetAttempts: true)
            return
        }

        if autoReconnectDevices.contains(id) {
            scheduleReconnect(for: entry)
        }
    }

    // MARK: - Peripheral callbacks
    func peripheralDidDiscoverServices(
        _ peripheral: any BluetoothPeripheralManaging,
        error: Error?
    ) {
        guard let entry = entry(for: peripheral) else { return }

        if let error {
            entry.connectionState = .failed(
                "Service discovery failed: \(error.localizedDescription)"
            )
            statusMessage = "Service discovery failed for \(entry.displayName)."
            return
        }
        
        

        guard let services = peripheral.services,
              let ropeService = services.first(
                  where: { $0.uuid == PulseRopeProtocol.serviceUUID }
              ) else {
            entry.connectionState = .failed("Rope service not found on this device.")
            statusMessage = "\(entry.displayName) does not expose the expected service."
            return
        }

        peripheral.discoverCharacteristics(
            [PulseRopeProtocol.repCharacteristicUUID],
            for: ropeService
        )
        
        // In peripheralDidDiscoverServices
        print("Discovered services:", peripheral.services?.map {
            $0.uuid.uuidString
        } ?? [])

        if let batteryService = services.first(
            where: { $0.uuid == BluetoothBatteryProtocol.serviceUUID }
        ) {
            peripheral.discoverCharacteristics(
                [BluetoothBatteryProtocol.levelCharacteristicUUID],
                for: batteryService
            )
        }
    }

    func peripheralDidDiscoverCharacteristics(
        _ peripheral: any BluetoothPeripheralManaging,
        service: BluetoothService,
        error: Error?
    ) {
        guard let entry = entry(for: peripheral) else { return }
        
        print(
            "Service:", service.uuid.uuidString,
            "Characteristics:", service.characteristics?.map {
                $0.uuid.uuidString
            } ?? [],
            "Error:", error?.localizedDescription ?? "none"
        )
        
        for characteristic in service.characteristics ?? [] {
            print(
                "UUID:", characteristic.uuid.uuidString,
                "Properties:", characteristic.properties,
                "Value:", characteristic.value as Any
            )
        }

        if service.uuid == BluetoothBatteryProtocol.serviceUUID {
            guard error == nil,
                  let characteristic = service.characteristics?.first(where: {
                      $0.uuid == BluetoothBatteryProtocol.levelCharacteristicUUID
                  }) else {
                return
            }

            if characteristic.properties.contains(.read) {
                peripheral.readValue(for: characteristic)
            }

            if characteristic.properties.contains(.notify)
                || characteristic.properties.contains(.indicate) {
                peripheral.setNotifyValue(true, for: characteristic)
            }

            return
        }

        guard service.uuid == PulseRopeProtocol.serviceUUID else { return }

        if let error {
            entry.connectionState = .failed(
                "Characteristic discovery failed: \(error.localizedDescription)"
            )
            statusMessage = "Characteristic discovery failed for \(entry.displayName)."
            return
        }

        guard let characteristic = service.characteristics?.first(where: {
            $0.uuid == PulseRopeProtocol.repCharacteristicUUID
        }) else {
            entry.connectionState = .failed(
                "Rep characteristic not found on this device."
            )
            statusMessage = "\(entry.displayName) does not expose the expected characteristic."
            return
        }

        entry.repCharacteristic = characteristic
        entry.characteristicProperties = String(describing: characteristic.properties)

        if characteristic.properties.contains(.notify)
            || characteristic.properties.contains(.indicate) {
            peripheral.setNotifyValue(true, for: characteristic)
        } else {
            entry.connectionState = .failed(
                "Rep characteristic does not support notifications."
            )
            statusMessage = "\(entry.displayName) cannot send rep-count updates."
        }
    }

    func peripheralDidUpdateNotificationState(
        _ peripheral: any BluetoothPeripheralManaging,
        characteristic: BluetoothCharacteristic,
        error: Error?
    ) {
        guard let entry = entry(for: peripheral) else { return }
        
        if characteristic.uuid == BluetoothBatteryProtocol.levelCharacteristicUUID {
            // Battery notifications are optional; they must not affect rope readiness.
            return
        }

        if let error {
            entry.connectionState = .failed(
                "Subscribe failed: \(error.localizedDescription)"
            )
            statusMessage = "Could not subscribe to \(entry.displayName): \(error.localizedDescription)"

            if autoReconnectDevices.contains(entry.id) {
                centralManager.cancelConnection(to: peripheral)
            }

            return
        }

        if characteristic.isNotifying {
            entry.connectionState = .ready

            // Only reset retries after the BLE connection is fully ready.
            invalidateReconnect(for: entry.id, resetAttempts: true)
            statusMessage = "\(entry.displayName) live. Swing the rope to see reps."
        } else {
            statusMessage = "Notifications stopped for \(entry.displayName)."
        }
    }

    func peripheralDidUpdateValue(
        _ peripheral: any BluetoothPeripheralManaging,
        characteristic: BluetoothCharacteristic,
        error: Error?
    ) {
        guard let entry = entry(for: peripheral) else { return }

        if let error {
            statusMessage = "Read error from \(entry.displayName): \(error.localizedDescription)"
            return
        }
        
        print(
            "Characteristic update:",
            characteristic.uuid.uuidString,
            "Value:",
            characteristic.value as Any,
            "UTF-8:",
            characteristic.value.flatMap { String(data: $0, encoding: .utf8) } as Any
        )

        guard let data = characteristic.value else {
            statusMessage = "Received empty payload from \(entry.displayName)."
            return
        }

        entry.lastMessage = String(data: data, encoding: .utf8)
            ?? "<\(data.count) non-utf8 bytes>"
        
        if characteristic.uuid == BluetoothBatteryProtocol.levelCharacteristicUUID {
            guard let percentage = data.first,
                  percentage <= 100 else {
                return
            }

            entry.batteryLevel = Int(percentage)
            return
        }

        switch PulseRopeProtocol.parse(data) {
        case .starting:
            entry.repCount = 0
            entry.hasValidatedCumulativeCount = true

        case .repCount(let count):
            entry.hasValidatedCumulativeCount = true
            entry.repCount = count

        case .unknown(let raw):
            statusMessage = "Unparseable payload from \(entry.displayName): \"\(raw)\""
        }
    }

    // MARK: - Automatic reconnection


    private func scheduleReconnect(for entry: DiscoveredPeripheral) {
        let id = entry.id

        guard autoReconnectDevices.contains(id),
              !intentionalDisconnects.contains(id),
              !pendingReconnects.contains(id),
              bluetoothState == .poweredOn else {
            return
        }

        let attempts = reconnectAttempts[id, default: 0]

        guard attempts < maxReconnectAttempts else {
            statusMessage = "Could not reconnect to \(entry.displayName) after \(maxReconnectAttempts) attempts."
            autoReconnectDevices.remove(id)
            return
        }

        let nextAttempt = attempts + 1
        reconnectAttempts[id] = nextAttempt

        let generation = reconnectGeneration[id, default: 0]
        let delay = max(0, reconnectDelay(nextAttempt))

        pendingReconnects.insert(id)

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }

            // Ignore retries invalidated by a manual disconnect or new connection.
            guard self.reconnectGeneration[id, default: 0] == generation else {
                self.pendingReconnects.remove(id)
                return
            }

            self.pendingReconnects.remove(id)

            guard self.bluetoothState == .poweredOn,
                  self.autoReconnectDevices.contains(id),
                  !self.intentionalDisconnects.contains(id),
                  let currentEntry = self.discoveredDevices.first(where: { $0.id == id }) else {
                return
            }

            switch currentEntry.connectionState {
            case .connecting, .connected, .ready:
                return
            case .disconnected, .failed:
                break
            }

            currentEntry.connectionState = .connecting
            self.statusMessage = "Reconnecting to \(currentEntry.displayName) (attempt \(nextAttempt)/\(self.maxReconnectAttempts))…"
            self.centralManager.connect(to: currentEntry.peripheral)
        }
    }


    private func invalidateReconnect(
        for id: UUID,
        resetAttempts: Bool
    ) {
        reconnectGeneration[id, default: 0] += 1
        pendingReconnects.remove(id)

        if resetAttempts {
            reconnectAttempts[id] = 0
        }
    }

    // MARK: - Helpers

    private func entry(
        for peripheral: any BluetoothPeripheralManaging
    ) -> DiscoveredPeripheral? {
        discoveredDevices.first { $0.id == peripheral.identifier }
    }

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

    static func description(for properties: CBCharacteristicProperties) -> String {
        var parts: [String] = []

        if properties.contains(.broadcast) { parts.append("Broadcast") }
        if properties.contains(.read) { parts.append("Read") }
        if properties.contains(.writeWithoutResponse) { parts.append("WriteWithoutResponse") }
        if properties.contains(.write) { parts.append("Write") }
        if properties.contains(.notify) { parts.append("Notify") }
        if properties.contains(.indicate) { parts.append("Indicate") }
        if properties.contains(.authenticatedSignedWrites) { parts.append("SignedWrites") }
        if properties.contains(.extendedProperties) { parts.append("ExtendedProperties") }
        if properties.contains(.notifyEncryptionRequired) { parts.append("NotifyEncrypted") }
        if properties.contains(.indicateEncryptionRequired) { parts.append("IndicateEncrypted") }

        return parts.isEmpty ? "None" : parts.joined(separator: " | ")
    }
}

