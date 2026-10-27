
//
//  BluetoothManagerTests.swift
//  BluetoothManagerTests
//
//  Created by Rafiq Whitley on 10/25/26.
//

import CoreBluetooth
import Foundation
import Testing
@testable import HelloWorld

@Suite(.serialized)
struct BluetoothManagerTests {
    
    
    @Test
    func rediscoveringPreviouslyConnectedDeviceAutomaticallyConnects() {
        let key = "lastConnectedPeripheralID"
        let defaults = UserDefaults.standard
        let previousValue = defaults.object(forKey: key)

        let central = FakeBluetoothCentral()
        let manager = BluetoothManager(centralManagerFactory: { central })
        let peripheral = FakeBluetoothPeripheral(name: "Nelevate Pulse Rope")

        defer {
            if let previousValue {
                defaults.set(previousValue, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        defaults.set(peripheral.identifier.uuidString, forKey: key)
        central.emitState(.poweredOn)

        central.emitDiscovery(peripheral, rssi: -60)

        #expect(central.connectedPeripheralID == peripheral.identifier)
        #expect(central.connectionRequestCount == 1)
        #expect(manager.discoveredDevices[0].connectionState == .connecting)
    }

    @Test
    func discoveringUnrelatedDeviceDoesNotAutomaticallyConnect() {
        let key = "lastConnectedPeripheralID"
        let defaults = UserDefaults.standard
        let previousValue = defaults.object(forKey: key)

        let central = FakeBluetoothCentral()
        let manager = BluetoothManager(centralManagerFactory: { central })
        let peripheral = FakeBluetoothPeripheral(name: "Unrelated Device")

        defer {
            if let previousValue {
                defaults.set(previousValue, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        defaults.set(UUID().uuidString, forKey: key)
        central.emitState(.poweredOn)

        central.emitDiscovery(peripheral, rssi: -60)

        #expect(central.connectedPeripheralID == nil)
        #expect(central.connectionRequestCount == 0)
        #expect(manager.discoveredDevices[0].connectionState == .disconnected)
    }

    @Test
    func rediscoveringPreviouslyConnectedDeviceDoesNotConnectTwice() {
        let key = "lastConnectedPeripheralID"
        let defaults = UserDefaults.standard
        let previousValue = defaults.object(forKey: key)

        let central = FakeBluetoothCentral()
        let manager = BluetoothManager(centralManagerFactory: { central })
        let peripheral = FakeBluetoothPeripheral(name: "Nelevate Pulse Rope")

        defer {
            if let previousValue {
                defaults.set(previousValue, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        defaults.set(peripheral.identifier.uuidString, forKey: key)
        central.emitState(.poweredOn)

        central.emitDiscovery(peripheral, rssi: -60)
        central.emitDiscovery(peripheral, rssi: -45)

        #expect(central.connectedPeripheralID == peripheral.identifier)
        #expect(central.connectionRequestCount == 1)
        #expect(manager.discoveredDevices.count == 1)
        #expect(manager.discoveredDevices[0].connectionState == .connecting)
    }


    @Test
    func scanStartsWhenBluetoothIsPoweredOn() {
        let central = FakeBluetoothCentral()
        let manager = BluetoothManager(centralManagerFactory: { central })
        central.emitState(.poweredOn)

        manager.startScan()

        #expect(central.scanRequested)
        #expect(manager.isScanning)
        #expect(manager.statusMessage == "Scanning…")
    }

    @Test
    func scanIsRejectedWhenBluetoothIsPoweredOff() {
        let central = FakeBluetoothCentral()
        let manager = BluetoothManager(centralManagerFactory: { central })
        central.emitState(.poweredOff)

        manager.startScan()

        #expect(!central.scanRequested)
        #expect(!manager.isScanning)
        #expect(manager.statusMessage.contains("Cannot scan"))
    }

    @Test
    func stopScanStopsScanning() {
        let central = FakeBluetoothCentral()
        let manager = BluetoothManager(centralManagerFactory: { central })
        central.emitState(.poweredOn)

        manager.startScan()
        manager.stopScan()

        #expect(central.stopScanRequested)
        #expect(!manager.isScanning)
        #expect(manager.statusMessage.contains("Scan stopped"))
    }

    @Test
    func discoveredPeripheralIsAddedOnlyOnce() {
        let central = FakeBluetoothCentral()
        let manager = BluetoothManager(centralManagerFactory: { central })
        let peripheral = FakeBluetoothPeripheral(name: "Nelevate Pulse Rope")

        central.emitDiscovery(peripheral, rssi: -60)
        central.emitDiscovery(peripheral, rssi: -45)

        #expect(manager.discoveredDevices.count == 1)
        #expect(manager.discoveredDevices[0].rssi == -45)
        #expect(manager.discoveredDevices[0].name == "Nelevate Pulse Rope")
    }

    @Test
    func connectRequestsConnectionAndUpdatesState() {
        let central = FakeBluetoothCentral()
        let manager = BluetoothManager(centralManagerFactory: { central })
        let peripheral = FakeBluetoothPeripheral(name: "Nelevate Pulse Rope")
        central.emitState(.poweredOn)
        central.emitDiscovery(peripheral, rssi: -60)

        let device = manager.discoveredDevices[0]
        manager.connect(to: device)

        #expect(central.connectedPeripheralID == peripheral.identifier)
        #expect(device.connectionState == .connecting)
        #expect(manager.statusMessage.contains("Connecting"))
    }

    @Test
    func connectIsRejectedWhenBluetoothIsPoweredOff() {
        let central = FakeBluetoothCentral()
        let manager = BluetoothManager(centralManagerFactory: { central })
        let peripheral = FakeBluetoothPeripheral(name: "Nelevate Pulse Rope")
        central.emitDiscovery(peripheral, rssi: -60)

        manager.connect(to: manager.discoveredDevices[0])

        #expect(central.connectedPeripheralID == nil)
        #expect(manager.discoveredDevices[0].connectionState == .disconnected)
        #expect(manager.statusMessage.contains("Cannot connect"))
    }

    @Test
    func connectionFailureUpdatesDeviceState() {
        let central = FakeBluetoothCentral()
        let manager = BluetoothManager(centralManagerFactory: { central })
        let peripheral = FakeBluetoothPeripheral(name: "Nelevate Pulse Rope")
        central.emitState(.poweredOn)
        central.emitDiscovery(peripheral, rssi: -60)

        let device = manager.discoveredDevices[0]
        manager.connect(to: device)
        central.emitConnectionFailure(
            peripheral,
            error: FakeBluetoothError.connectionFailed
        )

        #expect(
            device.connectionState ==
                .failed(FakeBluetoothError.connectionFailed.localizedDescription)
        )
        #expect(manager.statusMessage.contains("Failed to connect"))
    }

    @Test
    func successfulConnectionDiscoversRopeService() {
        let central = FakeBluetoothCentral()
        let manager = BluetoothManager(centralManagerFactory: { central })
        let peripheral = FakeBluetoothPeripheral(name: "Nelevate Pulse Rope")
        central.emitState(.poweredOn)
        central.emitDiscovery(peripheral, rssi: -60)

        let device = manager.discoveredDevices[0]
        manager.connect(to: device)
        central.emitConnection(peripheral)

        #expect(device.connectionState == .connected)
        #expect(
            peripheral.discoveredServiceUUIDs == [
                PulseRopeProtocol.serviceUUID,
                BluetoothBatteryProtocol.serviceUUID
            ]
        )
        #expect(peripheral.delegate != nil)
    }

    @Test
    func characteristicDiscoverySubscribesToNotifications() {
        let central = FakeBluetoothCentral()
        let manager = BluetoothManager(centralManagerFactory: { central })
        let peripheral = FakeBluetoothPeripheral(name: "Nelevate Pulse Rope")
        central.emitState(.poweredOn)
        central.emitDiscovery(peripheral, rssi: -60)

        let device = manager.discoveredDevices[0]
        manager.connect(to: device)
        central.emitConnection(peripheral)

        peripheral.emitServices([
            BluetoothService(
                uuid: PulseRopeProtocol.serviceUUID,
                characteristics: nil
            )
        ])

        let characteristic = BluetoothCharacteristic(
            uuid: PulseRopeProtocol.repCharacteristicUUID,
            properties: [.notify],
            isNotifying: false,
            value: nil
        )

        peripheral.emitCharacteristics(
            BluetoothService(
                uuid: PulseRopeProtocol.serviceUUID,
                characteristics: [characteristic]
            )
        )

        #expect(device.repCharacteristic?.uuid == PulseRopeProtocol.repCharacteristicUUID)
        #expect(peripheral.notificationEnabled)
    }

    @Test
    func deviceBecomesReadyAfterNotificationsAreConfirmed() {
        let central = FakeBluetoothCentral()
        let manager = BluetoothManager(centralManagerFactory: { central })
        let peripheral = FakeBluetoothPeripheral(name: "Nelevate Pulse Rope")
        central.emitState(.poweredOn)
        central.emitDiscovery(peripheral, rssi: -60)

        let device = manager.discoveredDevices[0]
        manager.connect(to: device)
        central.emitConnection(peripheral)

        peripheral.emitServices([
            BluetoothService(
                uuid: PulseRopeProtocol.serviceUUID,
                characteristics: nil
            )
        ])

        let characteristic = BluetoothCharacteristic(
            uuid: PulseRopeProtocol.repCharacteristicUUID,
            properties: [.notify],
            isNotifying: false,
            value: nil
        )

        peripheral.emitCharacteristics(
            BluetoothService(
                uuid: PulseRopeProtocol.serviceUUID,
                characteristics: [characteristic]
            )
        )

        peripheral.emitNotificationState(
            BluetoothCharacteristic(
                uuid: PulseRopeProtocol.repCharacteristicUUID,
                properties: [.notify],
                isNotifying: true,
                value: nil
            )
        )

        #expect(device.connectionState == .ready)
        #expect(manager.statusMessage.contains("live"))
    }

    @Test
    func repNotificationUpdatesRepCount() {
        let central = FakeBluetoothCentral()
        let manager = BluetoothManager(centralManagerFactory: { central })
        let peripheral = FakeBluetoothPeripheral(name: "Nelevate Pulse Rope")
        central.emitState(.poweredOn)
        central.emitDiscovery(peripheral, rssi: -60)

        let device = manager.discoveredDevices[0]
        manager.connect(to: device)
        central.emitConnection(peripheral)

        peripheral.emitValue(
            characteristicUUID: PulseRopeProtocol.repCharacteristicUUID,
            value: Data("Reps: 12".utf8)
        )

        #expect(device.repCount == 12)
        #expect(device.hasValidatedCumulativeCount)
        #expect(device.lastMessage == "Reps: 12")
    }

    @Test
    func disconnectRequestsCancellation() {
        let central = FakeBluetoothCentral()
        let manager = BluetoothManager(centralManagerFactory: { central })
        let peripheral = FakeBluetoothPeripheral(name: "Nelevate Pulse Rope")
        central.emitState(.poweredOn)
        central.emitDiscovery(peripheral, rssi: -60)

        let device = manager.discoveredDevices[0]
        manager.disconnect(from: device)

        #expect(central.cancelledPeripheralID == peripheral.identifier)
    }
}

// MARK: - Fakes

private final class FakeBluetoothCentral: BluetoothCentralManaging {
    private(set) var state: CBManagerState = .unknown
    weak var delegate: (any BluetoothCentralDelegate)?

    private(set) var scanRequested = false
    private(set) var stopScanRequested = false
    private(set) var connectedPeripheralID: UUID?
    private(set) var connectionRequestCount = 0
    private(set) var cancelledPeripheralID: UUID?

    func scanForPeripherals() {
        scanRequested = true
    }

    func stopScan() {
        stopScanRequested = true
    }

    func connect(to peripheral: any BluetoothPeripheralManaging) {
        connectedPeripheralID = peripheral.identifier
        connectionRequestCount += 1
    }

    func cancelConnection(to peripheral: any BluetoothPeripheralManaging) {
        cancelledPeripheralID = peripheral.identifier
    }

    func emitState(_ newState: CBManagerState) {
        state = newState
        delegate?.centralDidUpdateState(newState)
    }

    func emitDiscovery(
        _ peripheral: any BluetoothPeripheralManaging,
        rssi: Int
    ) {
        delegate?.centralDidDiscover(
            peripheral,
            advertisedName: peripheral.name,
            rssi: rssi
        )
    }

    func emitConnection(_ peripheral: any BluetoothPeripheralManaging) {
        delegate?.centralDidConnect(peripheral)
    }

    func emitConnectionFailure(
        _ peripheral: any BluetoothPeripheralManaging,
        error: Error?
    ) {
        delegate?.centralDidFailToConnect(peripheral, error: error)
    }
}

private final class FakeBluetoothPeripheral: BluetoothPeripheralManaging {
    let identifier = UUID()
    let name: String?
    weak var delegate: (any BluetoothPeripheralDelegate)?

    var services: [BluetoothService]?
    private(set) var discoveredServiceUUIDs: [CBUUID]?
    private(set) var discoveredCharacteristicUUIDs: [CBUUID]?
    private(set) var notificationEnabled = false
    private(set) var readRequestedCharacteristicUUID: CBUUID?

    init(name: String?) {
        self.name = name
    }

    func readValue(for characteristic: BluetoothCharacteristic) {
        readRequestedCharacteristicUUID = characteristic.uuid
    }

    func discoverServices(_ serviceUUIDs: [CBUUID]?) {
        discoveredServiceUUIDs = serviceUUIDs
    }

    func discoverCharacteristics(
        _ characteristicUUIDs: [CBUUID]?,
        for service: BluetoothService
    ) {
        discoveredCharacteristicUUIDs = characteristicUUIDs
    }

    func setNotifyValue(
        _ enabled: Bool,
        for characteristic: BluetoothCharacteristic
    ) {
        notificationEnabled = enabled
    }

    func emitServices(_ services: [BluetoothService]) {
        self.services = services
        delegate?.peripheralDidDiscoverServices(self, error: nil)
    }

    func emitCharacteristics(_ service: BluetoothService) {
        delegate?.peripheralDidDiscoverCharacteristics(
            self,
            service: service,
            error: nil
        )
    }

    func emitNotificationState(_ characteristic: BluetoothCharacteristic) {
        delegate?.peripheralDidUpdateNotificationState(
            self,
            characteristic: characteristic,
            error: nil
        )
    }

    func emitValue(characteristicUUID: CBUUID, value: Data) {
        delegate?.peripheralDidUpdateValue(
            self,
            characteristic: BluetoothCharacteristic(
                uuid: characteristicUUID,
                properties: [.notify],
                isNotifying: true,
                value: value
            ),
            error: nil
        )
    }
}

private enum FakeBluetoothError: LocalizedError {
    case connectionFailed

    var errorDescription: String? {
        switch self {
        case .connectionFailed:
            "Fake connection failure"
        }
    }
}

