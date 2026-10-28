import Foundation

// MARK: - BluetoothScanning conformance
//
// Add this file to the project (or paste the extension into BluetoothManager.swift)
// to satisfy the protocol required by the refactored ContentView.

extension BluetoothManager: BluetoothScanning {

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
