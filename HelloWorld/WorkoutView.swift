import SwiftUI

/// Renders the current phase of a workout and exposes user actions
/// as callbacks. Deliberately does not know about DiscoveredPeripheral
/// or BluetoothScanner — the parent view is responsible for choosing
/// which rope a workout runs against and for translating our callbacks
/// into calls on a WorkoutSession.
///
/// This separation keeps WorkoutView fully renderable in previews with
/// sample state values, no Bluetooth stack required.
struct WorkoutView: View {

    // MARK: - Inputs

    /// The current workout state, typically `session.state` from a
    /// `WorkoutSession` owned by the parent.
    let state: WorkoutSession.State

    /// Called when the user taps "Start Workout" from `.idle`. The
    /// Int is the target rep count the user selected on the stepper.
    let onStart: (Int) -> Void

    /// Called when the user taps Cancel (from `.armed` / `.inProgress`)
    /// or "New Workout" (from `.completed`). Both map to `reset()` on
    /// the session; the parent doesn't need to distinguish.
    let onReset: () -> Void

    // MARK: - Local state

    /// Target rep count the user is currently dialing on the stepper.
    /// Persists across state changes so if the user cancels mid-workout
    /// and starts again, the stepper is where they left it.
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
            case .completed(let finalCount, let target):
                completedView(finalCount: finalCount, target: target)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.default, value: stateKey)
    }

    // MARK: - Idle

    /// Stepper + Start button. The stepper's bounds (5...500 in steps
    /// of 5) are chosen loosely: 5 as a sensible minimum warm-up, 500
    /// as a soft ceiling that no reasonable single workout will hit
    /// but which leaves room for endurance sessions.
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
        // Clamp for the progress bar so we can't render >100% during
        // the brief window before .completed lands. The numeric
        // readout below intentionally shows the raw `current` so a
        // burst-overshoot is visible if it happens.
        let fraction = min(1.0, Double(current) / Double(target))

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

    // MARK: - Completed

    private func completedView(finalCount: Int, target: Int) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)

            Text("Done!")
                .font(.largeTitle)
                .fontWeight(.bold)

            // Show finalCount prominently. If it exceeds target,
            // surface that fact — the user did bonus reps and
            // deserves to see them.
            VStack(spacing: 4) {
                Text("\(finalCount) reps")
                    .font(.title2.monospacedDigit())
                if finalCount > target {
                    Text("(+\(finalCount - target) over target of \(target))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Target: \(target)")
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

    // MARK: - Helpers

    /// A stable identifier for the current state case, used to trigger
    /// the top-level `.animation(...)` when transitioning between
    /// cases. We deliberately avoid animating on every `current`
    /// update inside `.inProgress` — that's handled locally by
    /// `.contentTransition(.numericText)` on the count.
    private var stateKey: Int {
        switch state {
        case .idle:       return 0
        case .armed:      return 1
        case .inProgress: return 2
        case .completed:  return 3
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

#Preview("Completed (exact)") {
    WorkoutView(
        state: .completed(finalCount: 50, target: 50),
        onStart: { _ in },
        onReset: {}
    )
}

#Preview("Completed (overshoot)") {
    WorkoutView(
        state: .completed(finalCount: 53, target: 50),
        onStart: { _ in },
        onReset: {}
    )
}
