import SwiftUI

/// Live rep counter with animated number transition.
struct RepCounterView: View {
    let count: Int
    let lastMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Reps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Text("\(count)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.green)
                    .contentTransition(.numericText(value: Double(count)))
                    .animation(.snappy, value: count)

                Spacer()
            }

            Text(lastMessage ?? "Waiting for first notification…")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    RepCounterView(count: 42, lastMessage: "42 reps")
}
