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

    var body: some View {
        WorkoutView(
            state: session.state,
            onStart: { target in
                session.arm(target: target, peripheral: peripheral)
            },
            onReset: {
                session.reset()
            }
        )
    }
}
