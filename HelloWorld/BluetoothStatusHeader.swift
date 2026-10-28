import CoreBluetooth
import SwiftUI

/// Displays the system Bluetooth state as a traffic-light dot + label.
struct BluetoothStatusHeader: View {
    let state: CBManagerState

    var body: some View {
        HStack {
            Circle()
                .fill(stateColor)
                .frame(width: 12, height: 12)

            Text("Bluetooth: "\(BluetoothManager.description(for: state))"")
                .font(.subheadline)
                .fontWeight(.medium)

            Spacer()
        }
        .padding(.horizontal)
    }

    private var stateColor: Color {
        switch state {
        case .poweredOn:
            return .green
        case .poweredOff, .unauthorized, .unsupported:
            return .red
        case .resetting, .unknown:
            return .yellow
        @unknown default:
            return .gray
        }
    }
}

#Preview {
    BluetoothStatusHeader(state: .poweredOn)
}
