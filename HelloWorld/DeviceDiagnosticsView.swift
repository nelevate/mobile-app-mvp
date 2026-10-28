import SwiftUI

/// Debug-only diagnostic info for a connected device.
/// Consider gating this behind `#if DEBUG` or a feature flag in production.
struct DeviceDiagnosticsView: View {
    let properties: String?
    let isValidated: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let properties {
                Text("Props: "\(properties)"")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            if isValidated {
                Text("Counter validated ✓")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.green)
            } else {
                Text("Counter not yet validated…")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.orange)
            }
        }
    }
}

#Preview {
    DeviceDiagnosticsView(
        properties: "Notify | Read",
        isValidated: true
    )
}
