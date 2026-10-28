import SwiftUI

/// A single row in the device list. Shows identity, signal strength,
/// connection status, and a tap action. Does NOT embed battery, reps,
/// or diagnostics — those are composed by the parent when needed.
struct DeviceRow: View {
    let device: DiscoveredPeripheral
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(device.displayName)
                        .font(.headline)
                        .foregroundStyle(device.isLikelyPulseRope ? .green : .primary)

                    Spacer()

                    Text("RSSI: \(device.rssi)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                if device.isLikelyPulseRope {
                    Label("Likely Nelevate Pulse Rope", systemImage: "figure.jumprope")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                HStack(spacing: 6) {
                    Circle()
                        .fill(connectionColor)
                        .frame(width: 8, height: 8)

                    Text(connectionText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Identifier: \(device.id.uuidString)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var connectionColor: Color {
        switch device.connectionState {
        case .disconnected:  return .gray
        case .connecting:    return .yellow
        case .connected:     return .blue
        case .ready:         return .green
        case .failed:        return .red
        }
    }

    private var connectionText: String {
        switch device.connectionState {
        case .disconnected:
            return "Not connected — tap to connect"
        case .connecting:
            return "Connecting…"
        case .connected:
            return "Connected — preparing subscription…"
        case .ready:
            return "Ready — tap to start workout"
        case .failed(let reason):
            return "Failed: \(reason)"
        }
    }
}

#Preview {
    // Requires a mock DiscoveredPeripheral
    EmptyView()
}
