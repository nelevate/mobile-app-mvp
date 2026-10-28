import SwiftUI
import CoreBluetooth

/// Lightweight shell view. Owns layout and navigation only.
/// All BLE state lives in the injected `BluetoothManager`.
struct ContentView: View {

    @Environment(BluetoothManager.self) private var scanner

    /// Stable selection independent of the scan list.
    /// If a device drops out of `discoveredDevices`, the workout
    /// screen remains valid until the user dismisses it.
    @State private var selectedDevice: DiscoveredPeripheral?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                BluetoothStatusHeader(state: scanner.bluetoothState)

                ScanControlBar(
                    isScanning: scanner.isScanning,
                    canScan: scanner.bluetoothState == .poweredOn,
                    onStart: { scanner.startScan() },
                    onStop: { scanner.stopScan() }
                )
                .padding(.horizontal)

                HStack {
                    Text("Nearby Devices")
                        .font(.headline)
                    Spacer()
                    Text("\(scanner.discoveredDevices.count)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)

                DeviceList(
                    devices: scanner.discoveredDevices,
                    isScanning: scanner.isScanning,
                    onDeviceTap: { device in
                        switch scanner.handleDeviceTap(device) {
                        case .none:
                            break
                        case .navigateToWorkout(let peripheral):
                            selectedDevice = peripheral
                        }
                    }
                )

                StatusFooter(message: scanner.statusMessage)
            }
            .padding(.vertical)
            .navigationTitle("Nelevate BLE Prototype")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $selectedDevice) { device in
                WorkoutContainerView(peripheral: device)
            }
        }
    }
}

// MARK: - Previews

#Preview("Empty") {
    let mock = BluetoothManager(
        centralManagerFactory: { MockBluetoothCentralAdapter(state: .poweredOn) }
    )
    return ContentView()
        .environment(mock)
}

#Preview("Scanning") {
    let mock = BluetoothManager(
        centralManagerFactory: { MockBluetoothCentralAdapter(state: .poweredOn) }
    )
    mock.startScan()
    return ContentView()
        .environment(mock)
}

