import Foundation
import Observation

/// Represents one attempt at a workout: a target rep count, a rope to
/// count against, and a lifecycle from idle → armed → inProgress →
/// completed.
///
/// This type is the single source of truth for workout state. Views
/// render off `state`; `BluetoothScanner` remains unaware of workouts
/// (it just reports raw cumulative counts). WorkoutSession bridges
/// the two by observing a chosen peripheral's counter and advancing
/// its own state as validation and rep notifications arrive.
///
/// State machine:
///
///   idle
///     │  arm(target:peripheral:)
///     ▼
///   armed(target:)
///     │  peripheral.hasValidatedCumulativeCount becomes true
///     ▼
///   inProgress(current:target:baseline:)
///     │  current reaches target  (implemented in Task 5A.5)
///     ▼
///   completed(finalCount:target:)
///     │  reset()
///     ▼
///   idle
///
/// Task 5A.4 (this task) implements armed → inProgress and updates
/// to current within inProgress. The transition to completed is
/// deliberately deferred to 5A.5, so during this task's tests a
/// workout will count reps but never terminate — that's expected.
@Observable
@MainActor
final class WorkoutSession {

    // MARK: - State

    enum State: Equatable {

        /// No workout in progress.
        case idle

        /// User has committed to a target and rope, but the rope's
        /// counter is not yet validated. Waiting for the first
        /// parseable rep notification (see DiscoveredPeripheral's
        /// hasValidatedCumulativeCount flag).
        case armed(target: Int)

        /// Actively counting.
        ///
        /// - `current`: reps completed toward this workout, computed
        ///   as `peripheral.repCount - baseline` when notifications
        ///   arrive.
        /// - `target`: the goal.
        /// - `baseline`: the rope's cumulative count at the moment
        ///   this state was entered. Stored on the state so that a
        ///   baseline cannot exist without an in-progress workout.
        case inProgress(current: Int, target: Int, baseline: Int)

        /// Target reached. Further rep notifications are ignored.
        case completed(finalCount: Int, target: Int)
    }

    // MARK: - Observable state

    private(set) var state: State = .idle

    // MARK: - Private

    /// The peripheral being observed. Non-nil while `state` is
    /// `.armed` or `.inProgress`; nil in `.idle` and `.completed`.
    /// Held so observation callbacks can read fresh property values
    /// from the same instance the caller passed to `arm(…)`.
    private var peripheral: DiscoveredPeripheral?

    // MARK: - Lifecycle

    init() {}

    // MARK: - Public API

    /// Begin a workout attempt.
    ///
    /// If the peripheral has already validated its counter (e.g. the
    /// user swung a few warm-up reps before tapping "Start"), we skip
    /// `.armed` entirely and go straight to `.inProgress`, using the
    /// peripheral's current cumulative count as the baseline. This
    /// keeps the "Waiting for rope…" UI from flashing when there is
    /// nothing to wait for.
    ///
    /// Otherwise we enter `.armed(target:)` and start observing; the
    /// first change to `hasValidatedCumulativeCount` will advance us
    /// to `.inProgress`.
    ///
    /// - Parameters:
    ///   - target: Number of reps to complete. Must be > 0.
    ///   - peripheral: The rope to count against.
    func arm(target: Int, peripheral: DiscoveredPeripheral) {
        precondition(target > 0, "Workout target must be positive; got \(target)")
        precondition(state == .idle, "arm() called from non-idle state: \(state)")

        self.peripheral = peripheral

        if peripheral.hasValidatedCumulativeCount {
            state = .inProgress(
                current: 0,
                target: target,
                baseline: peripheral.repCount
            )
            print("🏋️ WorkoutSession → inProgress (rope already validated; baseline: \(peripheral.repCount), target: \(target))")
        } else {
            state = .armed(target: target)
            print("🏋️ WorkoutSession → armed (target: \(target); waiting for counter validation)")
        }

        observePeripheral()
    }

    /// End the current workout and return to `.idle`. Safe to call
    /// from any state. Used both to abandon an in-progress workout
    /// and to clear a completed one before starting a new attempt.
    func reset() {
        peripheral = nil
        state = .idle
        // Observation naturally stops: any pending onChange will
        // find `peripheral` nil (or `state` idle) and no-op, and we
        // will not re-register.
        print("🏋️ WorkoutSession → idle (reset)")
    }

    // MARK: - Observation

    /// Register a one-shot observation for the peripheral's counter
    /// state. See the `withObservationTracking` gotchas discussed in
    /// the doc comment on `onChange` inside the body.
    private func observePeripheral() {
        guard let peripheral else { return }

        withObservationTracking {
            // Any property read inside this closure becomes tracked.
            // We assign to `_` to make the intent explicit — we are
            // reading solely to register interest, not to use the
            // value here. The real read happens later, in
            // `handlePeripheralChange`, after the write completes.
            _ = peripheral.hasValidatedCumulativeCount
            _ = peripheral.repCount
        } onChange: { [weak self] in
                    // Gotchas encoded here:
                    //
                    //   1. `onChange` fires ONCE, then tracking is torn down.
                    //      We must re-call `observePeripheral()` at the end
                    //      to continue observing.
                    //
                    //   2. `onChange` fires on the willSet side — reading a
                    //      tracked property here would return the OLD value.
                    //      Hopping into a Task defers the read to after the
                    //      write has completed.
                    //
                    //   3. `onChange`'s closure is @Sendable and nonisolated.
                    //      `self` is @MainActor-isolated, so we hop to the
                    //      main actor explicitly.
                    //
                    //   4. Under Swift 6, the Task closure needs its OWN
                    //      capture of `self` rather than reaching into the
                    //      outer closure's `weak self` var (which would be
                    //      a concurrent read of a captured var). Hence the
                    //      `[weak self]` on the Task itself.
                    Task { @MainActor [weak self] in
                        self?.handlePeripheralChange()
                        self?.observePeripheral()
                    }
                }
    }

    /// React to a change on the observed peripheral. Called from the
    /// `onChange` continuation after the write has landed.
    private func handlePeripheralChange() {
        guard let peripheral else { return }

        switch state {
        case .idle, .completed:
            // A pending onChange raced with reset() (or with a
            // completion that will land in 5A.5). Nothing to do.
            break

        case .armed(let target):
            // Waiting for the rope to validate. If it just did,
            // snapshot the current cumulative count as the baseline
            // and begin counting.
            if peripheral.hasValidatedCumulativeCount {
                state = .inProgress(
                    current: 0,
                    target: target,
                    baseline: peripheral.repCount
                )
                print("🏋️ WorkoutSession → inProgress (baseline: \(peripheral.repCount), target: \(target))")
            }

        case .inProgress(_, let target, let baseline):
                    // A rep notification (or, harmlessly, a spurious change
                    // to hasValidatedCumulativeCount). Recompute `current`
                    // from the fresh cumulative count, then decide whether
                    // we have reached the target.
                    let current = peripheral.repCount - baseline

                    if current >= target {
                        // Completion. We store `current` as `finalCount`
                        // rather than `target` on purpose: if a burst of
                        // notifications pushed us past the target in a
                        // single update, we preserve the actual number of
                        // reps observed instead of silently rounding down.
                        // Normal case: current == target and this is a
                        // no-op distinction.
                        state = .completed(finalCount: current, target: target)
                        print("🏋️ WorkoutSession → completed (final: \(current), target: \(target))")
                    } else {
                        state = .inProgress(
                            current: current,
                            target: target,
                            baseline: baseline
                        )
                        print("🏋️ WorkoutSession → inProgress update (current: \(current) / \(target))")
                    }
                }
    }
}
