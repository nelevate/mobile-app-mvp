
import CoreBluetooth
import Foundation

struct BluetoothService {
    let uuid: CBUUID
    let characteristics: [BluetoothCharacteristic]?
}

struct BluetoothCharacteristic {
    let uuid: CBUUID
    let properties: CBCharacteristicProperties
    let isNotifying: Bool
    let value: Data?
}

enum BluetoothBatteryProtocol {
    static let serviceUUID = CBUUID(string: "180F")
    static let levelCharacteristicUUID = CBUUID(string: "2A19")
}

protocol BluetoothCentralDelegate: AnyObject {
    func centralDidUpdateState(_ state: CBManagerState)

    func centralDidDiscover(
        _ peripheral: any BluetoothPeripheralManaging,
        advertisedName: String?,
        rssi: Int
    )

    func centralDidConnect(_ peripheral: any BluetoothPeripheralManaging)
    func centralDidFailToConnect(
        _ peripheral: any BluetoothPeripheralManaging,
        error: Error?
    )
    func centralDidDisconnect(
        _ peripheral: any BluetoothPeripheralManaging,
        error: Error?
    )
}

protocol BluetoothPeripheralDelegate: AnyObject {
    func peripheralDidDiscoverServices(
        _ peripheral: any BluetoothPeripheralManaging,
        error: Error?
    )

    func peripheralDidDiscoverCharacteristics(
        _ peripheral: any BluetoothPeripheralManaging,
        service: BluetoothService,
        error: Error?
    )

    func peripheralDidUpdateNotificationState(
        _ peripheral: any BluetoothPeripheralManaging,
        characteristic: BluetoothCharacteristic,
        error: Error?
    )

    func peripheralDidUpdateValue(
        _ peripheral: any BluetoothPeripheralManaging,
        characteristic: BluetoothCharacteristic,
        error: Error?
    )
}

protocol BluetoothCentralManaging: AnyObject {
    var state: CBManagerState { get }
    var delegate: (any BluetoothCentralDelegate)? { get set }

    func scanForPeripherals()
    func stopScan()
    func connect(to peripheral: any BluetoothPeripheralManaging)
    func cancelConnection(to peripheral: any BluetoothPeripheralManaging)
}

protocol BluetoothPeripheralManaging: AnyObject {
    var identifier: UUID { get }
    var name: String? { get }
    var delegate: (any BluetoothPeripheralDelegate)? { get set }
    var services: [BluetoothService]? { get }

    func discoverServices(_ serviceUUIDs: [CBUUID]?)
    func discoverCharacteristics(
        _ characteristicUUIDs: [CBUUID]?,
        for service: BluetoothService
    )
    func setNotifyValue(
        _ enabled: Bool,
        for characteristic: BluetoothCharacteristic
    )
    func readValue(for characteristic: BluetoothCharacteristic)
}
