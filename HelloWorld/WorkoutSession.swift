import Foundation
import Observation

/// Represents one attempt at a workout: a target rep count, a rope to
/// count against, and a lifecycle from idle → armed → inProgress →
/// completed.
///
/// This type is the single source of truth for workout state. Views
/// render off `state`; `BluetoothScanner` remains unaware of workouts
/// (it just reports raw cumulative counts). The two are wired together
/// in a later task, where WorkoutSession observes a chosen peripheral
/// and advances its state as rep counts arrive.
///
/// The state machine is deliberately small:
///
///   idle
///     │  arm(target:peripheral:)
///     ▼
///   armed(target:)
///     │  (peripheral validates its counter — Task 5A.4)
///     ▼
///   inProgress(current:target:baseline:)
///     │  (current reaches target — Task 5A.5)
///     ▼
///   completed(finalCount:target:)
///     │  reset()
///     ▼
///   idle
///
/// Task 5A.3 builds only the skeleton: the state enum, the class,
/// stub methods. No observation logic yet — that lands in 5A.4.
@Observable
final class WorkoutSession {

    // MARK: - State

    /// The lifecycle state of a workout attempt. See the type-level
    /// doc comment for the transition diagram.
    enum State: Equatable {

        /// No workout in progress. The app boots in this state, and
        /// returns to it after `reset()`.
        case idle

        /// User has committed to a target and selected a rope, but we
        /// are waiting for the rope's cumulative counter to be
        /// validated before we start counting. Typically lasts
        /// milliseconds; exists as a distinct state so the UI can
        /// show "Waiting for rope…" honestly instead of showing a
        /// misleading "0 / target" that might jump once real data
        /// arrives.
        case armed(target: Int)

        /// Actively counting.
        ///
        /// - `current`: reps completed toward this workout (not the
        ///   rope's raw cumulative count).
        /// - `target`: the goal.
        /// - `baseline`: the rope's cumulative count at the moment
        ///   the workout transitioned into this state. `current` is
        ///   computed as `repCount - baseline` when rep notifications
        ///   arrive. Stored on the state (rather than as a separate
        ///   property on the class) so it is impossible to have a
        ///   baseline without an in-progress workout, or vice versa.
        case inProgress(current: Int, target: Int, baseline: Int)

        /// Target reached. Further rep notifications are ignored
        /// until `reset()` is called.
        ///
        /// - `finalCount`: reps counted toward the workout at the
        ///   moment it completed. Normally equals `target`, but
        ///   preserved as a separate field so we don't lose data if
        ///   a burst of notifications pushes the count past the
        ///   target in a single update.
        case completed(finalCount: Int, target: Int)
    }

    // MARK: - Observable state

    /// The current lifecycle state. Views observe this to render.
    private(set) var state: State = .idle

    // MARK: - Lifecycle

    /// No-op initializer. WorkoutSession starts in `.idle` and does
    /// nothing until `arm(target:peripheral:)` is called.
    init() {}

    // MARK: - Public API (stubs — logic lands in 5A.4 / 5A.5)

    /// Begin a workout attempt.
    ///
    /// Transitions state to `.armed(target:)`. Once the peripheral's
    /// `hasValidatedCumulativeCount` becomes true, an internal
    /// observer (added in Task 5A.4) will advance state to
    /// `.inProgress`, capturing the peripheral's current `repCount`
    /// as the baseline.
    ///
    /// Calling this while a workout is already armed, in progress,
    /// or completed is a programmer error and will be enforced with
    /// a precondition in a later task. For now it silently no-ops so
    /// the skeleton compiles cleanly.
    ///
    /// - Parameters:
    ///   - target: The number of reps the user wants to complete.
    ///     Must be > 0.
    ///   - peripheral: The rope to count against. WorkoutSession
    ///     holds a reference to observe its rep count.
    func arm(target: Int, peripheral: DiscoveredPeripheral) {
        // TODO(5A.4): validate arguments, store peripheral, set up
        // observation, transition state to .armed(target:).
    }

    /// End the current workout and return to `.idle`. Safe to call
    /// from any state — including `.idle` itself, in which case it
    /// is a no-op. Used both after a completed workout and to
    /// abandon an in-progress one.
    func reset() {
        // TODO(5A.4): tear down observation, clear peripheral
        // reference, transition state to .idle.
        state = .idle
    }
}
