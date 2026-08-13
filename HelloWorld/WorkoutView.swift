import SwiftUI

/// Renders the current phase of a workout and exposes user actions
/// as callbacks.
struct WorkoutView: View {

    // MARK: - Inputs

    let state: WorkoutSession.State
    let onStart: (Int) -> Void
    let onReset: () -> Void

    // MARK: - Local state

    @State private var targetInput: Int = 20

    // MARK: - Body

    var body: some View {
        VStack(spacing: 24) {
            switch state {
            case .idle:
                idleView
            case .armed(let target):
                armedView(target: target)
            case .inProgress(let current, let target, _):
                inProgressView(current: current, target: target)
            case .summary(let summary):
                summaryView(summary: summary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.default, value: stateKey)
    }

    // MARK: - Idle

    private var idleView: some View {
        VStack(spacing: 20) {
            Text("Set a target")
                .font(.title2)
                .foregroundStyle(.secondary)

            Stepper(
                value: $targetInput,
                in: 5...500,
                step: 5
            ) {
                Text("\(targetInput) reps")
                    .font(.title.monospacedDigit())
                    .fontWeight(.semibold)
            }
            .padding(.horizontal)

            Button {
                onStart(targetInput)
            } label: {
                Text("Start Workout")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.tint)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - Armed

    private func armedView(target: Int) -> some View {
        VStack(spacing: 20) {
            ProgressView()
                .controlSize(.large)

            Text("Waiting for rope…")
                .font(.title2)
            Text("Swing once to begin (target: \(target))")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Cancel", role: .destructive, action: onReset)
                .buttonStyle(.bordered)
                .padding(.top)
        }
    }

    // MARK: - In progress

    private func inProgressView(current: Int, target: Int) -> some View {
        // Defensive clamping for the progress fraction.
        //
        // WorkoutSession already clamps `current` to be non-negative and
        // transitions to .summary(.completed) when `current >= target`,
        // so in normal operation `fraction` will land in [0, 1] without
        // any help from us. But a value view like ProgressView should
        // not trust its inputs to be pre-clamped — SwiftUI logs a
        // runtime warning ("ProgressView initialized with an
        // out-of-bounds progress value…") if the value ever falls
        // outside the range, and that warning has bitten us during
        // disconnect races in earlier tasks.
        //
        // Two-sided clamp:
        //   * `max(0, …)` guards against a negative `current` sneaking
        //     through (would produce a negative fraction).
        //   * `min(1, …)` guards against the one-frame window where
        //     `current == target` has been observed but the state
        //     machine hasn't yet flipped to .summary — the ratio would
        //     be exactly 1.0 there, which is fine, but any overshoot
        //     from a burst of notifications would push it above 1.0.
        //
        // Also guards against target == 0 (which would divide by zero)
        // even though WorkoutSession's `arm()` precondition forbids it
        // — cheap insurance against a future caller path we haven't
        // written yet.
        let safeTarget = max(1, target)
        let rawFraction = Double(current) / Double(safeTarget)
        let fraction = min(1.0, max(0.0, rawFraction))

        return VStack(spacing: 20) {
            Text("\(current) / \(target)")
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(current)))

            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .padding(.horizontal)

            Button("Cancel", role: .destructive, action: onReset)
                .buttonStyle(.bordered)
                .padding(.top)
        }
    }

    // MARK: - Summary

    private func summaryView(summary: WorkoutSummary) -> some View {
        VStack(spacing: 20) {
            summaryIcon(for: summary.resultType)

            Text(summaryHeadline(for: summary.resultType))
                .font(.largeTitle)
                .fontWeight(.bold)

            VStack(spacing: 4) {
                Text("\(summary.finalCount) reps")
                    .font(.title2.monospacedDigit())
                if summary.finalCount > summary.target {
                    Text("(+\(summary.finalCount - summary.target) over target of \(summary.target))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Target: \(summary.target)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                onReset()
            } label: {
                Text("New Workout")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.tint)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.top)
        }
    }

    @ViewBuilder
    private func summaryIcon(for resultType: WorkoutSummary.ResultType) -> some View {
        switch resultType {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)
        case .disconnected:
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 80))
                .foregroundStyle(.orange)
        }
    }

    private func summaryHeadline(for resultType: WorkoutSummary.ResultType) -> String {
        switch resultType {
        case .completed:
            return "Done!"
        case .disconnected:
            return "Rope disconnected"
        }
    }

    // MARK: - Helpers

    private var stateKey: Int {
        switch state {
        case .idle:       return 0
        case .armed:      return 1
        case .inProgress: return 2
        case .summary:    return 3
        }
    }
}

// MARK: - Previews

#Preview("Idle") {
    WorkoutView(
        state: .idle,
        onStart: { _ in },
        onReset: {}
    )
}

#Preview("Armed") {
    WorkoutView(
        state: .armed(target: 50),
        onStart: { _ in },
        onReset: {}
    )
}

#Preview("In progress") {
    WorkoutView(
        state: .inProgress(current: 23, target: 50, baseline: 100),
        onStart: { _ in },
        onReset: {}
    )
}

#Preview("Summary (exact)") {
    WorkoutView(
        state: .summary(
            WorkoutSummary(resultType: .completed, finalCount: 50, target: 50)
        ),
        onStart: { _ in },
        onReset: {}
    )
}

#Preview("Summary (overshoot)") {
    WorkoutView(
        state: .summary(
            WorkoutSummary(resultType: .completed, finalCount: 53, target: 50)
        ),
        onStart: { _ in },
        onReset: {}
    )
}

#Preview("Summary (disconnected mid-workout)") {
    WorkoutView(
        state: .summary(
            WorkoutSummary(resultType: .disconnected, finalCount: 17, target: 50)
        ),
        onStart: { _ in },
        onReset: {}
    )
}

#Preview("Summary (disconnected before start)") {
    WorkoutView(
        state: .summary(
            WorkoutSummary(resultType: .disconnected, finalCount: 0, target: 50)
        ),
        onStart: { _ in },
        onReset: {}
    )
}
