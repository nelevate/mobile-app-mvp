//
//  CoreBluetoothAdapters.swift
//  HelloWorld
//
//  Created by Rafiq Whitley on 10/25/26.
//


import CoreBluetooth
import Foundation

final class CoreBluetoothPeripheralAdapter:
    NSObject,
    BluetoothPeripheralManaging,
    CBPeripheralDelegate
{
    let peripheral: CBPeripheral

    weak var delegate: (any BluetoothPeripheralDelegate)? {
        didSet {
            peripheral.delegate = delegate == nil ? nil : self
        }
    }

    var identifier: UUID { peripheral.identifier }
    var name: String? { peripheral.name }

    var services: [BluetoothService]? {
        peripheral.services?.map { service in
            BluetoothService(
                uuid: service.uuid,
                characteristics: service.characteristics?.map(makeCharacteristic)
            )
        }
    }

    init(peripheral: CBPeripheral) {
        self.peripheral = peripheral
        super.init()
    }
    
    func readValue(for characteristic: BluetoothCharacteristic) {
        guard let actualCharacteristic = peripheral.services?
            .flatMap({ $0.characteristics ?? [] })
            .first(where: { $0.uuid == characteristic.uuid }) else {
            return
        }

        peripheral.readValue(for: actualCharacteristic)
    }

    func discoverServices(_ serviceUUIDs: [CBUUID]?) {
        peripheral.discoverServices(serviceUUIDs)
    }

    func discoverCharacteristics(
        _ characteristicUUIDs: [CBUUID]?,
        for service: BluetoothService
    ) {
        guard let actualService = peripheral.services?.first(
            where: { $0.uuid == service.uuid }
        ) else {
            return
        }

        peripheral.discoverCharacteristics(
            characteristicUUIDs,
            for: actualService
        )
    }

    func setNotifyValue(
        _ enabled: Bool,
        for characteristic: BluetoothCharacteristic
    ) {
        guard let actualCharacteristic = peripheral.services?
            .flatMap({ $0.characteristics ?? [] })
            .first(where: { $0.uuid == characteristic.uuid }) else {
            return
        }

        peripheral.setNotifyValue(enabled, for: actualCharacteristic)
    }

    private func makeCharacteristic(
        _ characteristic: CBCharacteristic
    ) -> BluetoothCharacteristic {
        BluetoothCharacteristic(
            uuid: characteristic.uuid,
            properties: characteristic.properties,
            isNotifying: characteristic.isNotifying,
            value: characteristic.value
        )
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverServices error: Error?
    ) {
        delegate?.peripheralDidDiscoverServices(self, error: error)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        let wrappedService = BluetoothService(
            uuid: service.uuid,
            characteristics: service.characteristics?.map(makeCharacteristic)
        )

        delegate?.peripheralDidDiscoverCharacteristics(
            self,
            service: wrappedService,
            error: error
        )
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        delegate?.peripheralDidUpdateNotificationState(
            self,
            characteristic: makeCharacteristic(characteristic),
            error: error
        )
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        delegate?.peripheralDidUpdateValue(
            self,
            characteristic: makeCharacteristic(characteristic),
            error: error
        )
    }
}

final class CoreBluetoothCentralAdapter:
    NSObject,
    BluetoothCentralManaging,
    CBCentralManagerDelegate
{
    private var central: CBCentralManager!
    private var peripheralAdapters: [UUID: CoreBluetoothPeripheralAdapter] = [:]

    weak var delegate: (any BluetoothCentralDelegate)?

    var state: CBManagerState { central.state }

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func scanForPeripherals() {
        central.scanForPeripherals(
            withServices: nil,
            options: [
                CBCentralManagerScanOptionAllowDuplicatesKey: false
            ]
        )
    }

    func stopScan() {
        central.stopScan()
    }

    func connect(to peripheral: any BluetoothPeripheralManaging) {
        guard let adapter = peripheral as? CoreBluetoothPeripheralAdapter else {
            return
        }

        central.connect(adapter.peripheral, options: nil)
    }

    func cancelConnection(to peripheral: any BluetoothPeripheralManaging) {
        guard let adapter = peripheral as? CoreBluetoothPeripheralAdapter else {
            return
        }

        central.cancelPeripheralConnection(adapter.peripheral)
    }

    private func adapter(for peripheral: CBPeripheral)
        -> CoreBluetoothPeripheralAdapter {
        if let existing = peripheralAdapters[peripheral.identifier] {
            return existing
        }

        let adapter = CoreBluetoothPeripheralAdapter(peripheral: peripheral)
        peripheralAdapters[peripheral.identifier] = adapter
        return adapter
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        delegate?.centralDidUpdateState(central.state)
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let advertisedName =
            advertisementData[CBAdvertisementDataLocalNameKey] as? String
            ?? peripheral.name

        delegate?.centralDidDiscover(
            adapter(for: peripheral),
            advertisedName: advertisedName,
            rssi: RSSI.intValue
        )
    }

    func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        delegate?.centralDidConnect(adapter(for: peripheral))
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        delegate?.centralDidFailToConnect(
            adapter(for: peripheral),
            error: error
        )
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        delegate?.centralDidDisconnect(
            adapter(for: peripheral),
            error: error
        )
    }
}
