import SwiftUI

/// Displays either a populated list of devices or an empty-state placeholder.
struct DeviceList: View {
    let devices: [DiscoveredPeripheral]
    let isScanning: Bool
    let onDeviceTap: (DiscoveredPeripheral) -> Void

    var body: some View {
        Group {
            if devices.isEmpty {
                emptyState
            } else {
                list
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text(isScanning
                 ? "Listening for advertisements…"
                 : "No devices yet. Press Scan to begin.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var list: some View {
        List(devices) { device in
            DeviceRow(device: device, onTap: { onDeviceTap(device) })
        }
        .listStyle(.plain)
    }
}

#Preview("Empty") {
    DeviceList(devices: [], isScanning: false, onDeviceTap: { _ in })
}

#Preview("Populated") {
    // Populate with mock peripherals if you have a mock factory
    DeviceList(devices: [], isScanning: true, onDeviceTap: { _ in })
}
