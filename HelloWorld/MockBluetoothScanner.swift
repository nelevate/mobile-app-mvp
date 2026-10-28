import CoreBluetooth
import Foundation

/// Drop-in mock for SwiftUI previews and snapshot tests.
/// Simulates a deterministic BLE environment without hardware.
@MainActor
final class MockBluetoothScanner: BluetoothScanning {
    var bluetoothState: CBManagerState = .poweredOn
    var isScanning = false
    var discoveredDevices: [DiscoveredPeripheral] = []
    var statusMessage = "Mock Bluetooth ready."

    init(populateWith mockDevices: [DiscoveredPeripheral] = []) {
        self.discoveredDevices = mockDevices
    }

    func startScan() {
        isScanning = true
        statusMessage = "Mock scanning…"
    }

    func stopScan() {
        isScanning = false
        statusMessage = "Mock scan stopped."
    }

    func connect(to device: DiscoveredPeripheral) {
        device.connectionState = .connecting
        // Simulate fast async connection for previews
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak device] in
            device?.connectionState = .ready
        }
    }

    func disconnect(from device: DiscoveredPeripheral) {
        device.connectionState = .disconnected
    }

    func handleDeviceTap(_ device: DiscoveredPeripheral) -> DeviceTapResult {
        switch device.connectionState {
        case .disconnected, .failed:
            connect(to: device)
            return .none
        case .ready:
            return .navigateToWorkout(device)
        case .connecting, .connected:
            return .none
        }
    }
}
