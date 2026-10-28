import SwiftUI

/// Start / Stop scan buttons with disabled-state logic.
struct ScanControlBar: View {
    let isScanning: Bool
    let canScan: Bool
    let onStart: () -> Void
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onStart) {
                Label("Scan for Devices", systemImage: "dot.radiowaves.left.and.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canScan || isScanning)

            Button(action: onStop) {
                Label("Stop Scan", systemImage: "stop.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!isScanning)
        }
    }
}

#Preview {
    ScanControlBar(
        isScanning: false,
        canScan: true,
        onStart: {},
        onStop: {}
    )
}
