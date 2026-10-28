import SwiftUI

/// Reusable battery level indicator with color-coded urgency.
struct BatteryIndicator: View {
    let level: Int?

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .foregroundStyle(color)

            if let level {
                Text("Battery: "\(level)%"")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else {
                Text("Battery unavailable")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }

    private var symbol: String {
        guard let level else { return "battery.0percent" }
        switch level {
        case 0..<20:  return "battery.25percent"
        case 20..<50: return "battery.50percent"
        case 50..<75: return "battery.75percent"
        default:      return "battery.100percent"
        }
    }

    private var color: Color {
        guard let level else { return .secondary }
        if level <= 20 { return .red }
        if level <= 50 { return .orange }
        return .green
    }
}

#Preview("High") {
    BatteryIndicator(level: 85)
}

#Preview("Low") {
    BatteryIndicator(level: 12)
}

#Preview("Unknown") {
    BatteryIndicator(level: nil)
}
