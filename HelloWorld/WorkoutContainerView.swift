import SwiftUI

/// Owns a `WorkoutSession` and connects its state to `WorkoutView`.
/// This is the glue layer between the state machine (WorkoutSession)
/// and the presentation layer (WorkoutView).
///
/// WorkoutSession is `@Observable` (the new Observation framework),
/// not `ObservableObject`, so we own it with plain `@State`. SwiftUI
/// tracks reads of `session.state` automatically and re-renders on
/// change — no `@StateObject` / `@ObservedObject` needed.
///
/// The peripheral is stored as a plain `let` rather than folded into
/// the session's init because `WorkoutSession` is designed to accept
/// a peripheral at `arm(target:peripheral:)` time. That means one
/// session instance could in principle run successive workouts
/// against different ropes; for this container we simply always
/// pass the peripheral we were constructed with.
struct WorkoutContainerView: View {

    let peripheral: DiscoveredPeripheral

    /// Session lifetime is tied to this view's SwiftUI identity.
    /// `@State` here is correct because WorkoutSession is @Observable;
    /// SwiftUI will keep the same instance across re-evaluations of
    /// the view body and dispose of it when the view leaves the
    /// hierarchy.
    @State private var session = WorkoutSession()

    /// Provided by the NavigationStack ancestor. Calling this pops
    /// WorkoutContainerView back to ContentView's scan list.
    ///
    /// We drive dismissal from here (rather than mutating ContentView's
    /// `openWorkoutForID` binding directly) so the container remains
    /// self-contained: ContentView doesn't need to know that "reset"
    /// or "cancel" means "go back", it just knows how to push us.
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        WorkoutView(
            state: session.state,
            onStart: { target in
                session.arm(target: target, peripheral: peripheral)
            },
            onReset: {
                // Two things happen here, in this order:
                //
                //   1. session.reset() drops the state machine back to
                //      .idle. Strictly redundant — we're about to be
                //      deallocated — but it makes the intent explicit
                //      and stops the observation of `peripheral` on the
                //      same runloop tick, rather than waiting for the
                //      view teardown to release the session.
                //
                //   2. dismiss() pops us off the NavigationStack, which
                //      clears ContentView's openWorkoutForID binding
                //      automatically (that's how navigationDestination(item:)
                //      is wired).
                //
                // This is invoked from three places in WorkoutView:
                //   - "Cancel" while .armed  → user backed out before the
                //                              first rep
                //   - "Cancel" while .inProgress → user gave up mid-set
                //   - "New Workout" from .summary → user acknowledging
                //                                   the result screen
                //
                // In all three, "back to the scanner" is the right
                // destination. If we ever want "New Workout" to instead
                // start another set against the same rope without
                // popping, that becomes a new callback (e.g. onRestart)
                // rather than an overload of this one.
                session.reset()
                dismiss()
            }
        )
    }
}
