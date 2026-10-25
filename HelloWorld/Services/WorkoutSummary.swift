import Foundation

/// Terminal record of a workout attempt.
///
/// Produced by `WorkoutSession` when a workout leaves the active phase
/// and enters `.summary`. Modeling the terminal state as a value type
/// — rather than folding its fields into the `State.summary` case's
/// associated values — buys us two things:
///
///   1. Extensibility. When 5A.7 introduces inactivity auto-stop, the
///      state case itself won't need new associated values; the new
///      `ResultType` case slots into this struct. Similarly, if we
///      later want to attach duration, average rep interval, or a
///      session UUID, they land here, not on the enum.
///
///   2. Ergonomics for the view. `WorkoutView` pattern-matches on
///      `summary.resultType` to swap iconography and copy without the
///      outer `State` switch having to fan out into N cases.
///
/// The type is `Equatable` so `WorkoutSession.State: Equatable`
/// continues to hold, which matters both for SwiftUI diffing and for
/// tests that compare expected vs. actual states.
struct WorkoutSummary: Equatable {

    /// How this workout ended.
    ///
    /// Cancellation is deliberately NOT a result type here: `reset()`
    /// from an active phase produces no summary — it drops directly
    /// back to `.idle` — on the theory that an abandoned workout is
    /// a non-event, not a result worth surfacing to the user.
    enum ResultType: Equatable {
        /// User reached (or exceeded) the target rep count.
        case completed

        /// The rope disconnected while the workout was in `.armed` or
        /// `.inProgress`. Added in 5A.8. Distinct from `.completed`
        /// because the user did not necessarily hit their target, and
        /// distinct from cancellation (which produces no summary) because
        /// the workout ended without user intent — surfacing "the rope
        /// went away" is more useful than silently dropping to idle.
        case disconnected

        // 5A.7 will add:
        // case inactivityTimeout
    }

    let resultType: ResultType

    /// Actual reps observed by the time the workout terminated. May
    /// exceed `target` when a burst of notifications lands in a single
    /// update; see the note in `WorkoutSession.handlePeripheralChange`
    /// where this is set.
    let finalCount: Int

    /// The target the user selected when arming the workout. Preserved
    /// on the summary so the view can render "X reps (target: Y)" and
    /// "+N over target" copy without reaching back into the session.
    let target: Int
}
