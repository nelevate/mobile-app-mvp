import SwiftUI

/// Bottom status bar showing the scanner's current human-readable message.
struct StatusFooter: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Status")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(message)
                .font(.footnote)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}

#Preview {
    StatusFooter(message: "Scanning…")
}
