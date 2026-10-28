import CoreBluetooth
import Foundation

/// Minimal fake central adapter for SwiftUI previews and lightweight tests.
/// Does not touch real Bluetooth hardware.
@MainActor
final class MockBluetoothCentralAdapter: BluetoothCentralManaging {
    var state: CBManagerState
    weak var delegate: (any BluetoothCentralDelegate)?

    init(state: CBManagerState = .poweredOn) {
        self.state = state
    }

    func scanForPeripherals() {
        // No-op in previews
    }

    func stopScan() {
        // No-op in previews
    }

    func connect(to peripheral: any BluetoothPeripheralManaging) {
        // No-op in previews
    }

    func cancelConnection(to peripheral: any BluetoothPeripheralManaging) {
        // No-op in previews
    }
}
