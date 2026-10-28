import CoreBluetooth
import Foundation

/// Protocol abstracting the BLE scanning / connection surface.
/// Enables mocking for previews and unit tests without a real Bluetooth radio.
@MainActor
protocol BluetoothScanning {
    var bluetoothState: CBManagerState { get }
    var isScanning: Bool { get }
    var discoveredDevices: [DiscoveredPeripheral] { get }
    var statusMessage: String { get }

    func startScan()
    func stopScan()
    func connect(to device: DiscoveredPeripheral)
    func disconnect(from device: DiscoveredPeripheral)

    /// Semantic action when the user taps a device row.
    /// Returns the navigation target if the tap should trigger navigation.
    func handleDeviceTap(_ device: DiscoveredPeripheral) -> DeviceTapResult
}

enum DeviceTapResult {
    case none
    case navigateToWorkout(DiscoveredPeripheral)
}
