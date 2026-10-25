import Foundation
import Observation

/// Represents one attempt at a workout: a target rep count, a rope to
/// count against, and a lifecycle from idle → armed → inProgress →
/// summary.
///
/// This type is the single source of truth for workout state. Views
/// render off `state`; `BluetoothScanner` remains unaware of workouts
/// (it just reports raw cumulative counts). WorkoutSession bridges
/// the two by observing a chosen peripheral's counter and advancing
/// its own state as validation and rep notifications arrive.
@Observable
@MainActor
final class WorkoutSession {

    // MARK: - State

    enum State: Equatable {

        /// No workout in progress.
        case idle

        /// User has committed to a target and rope, but the rope's
        /// counter is not yet validated. Waiting for the first
        /// parseable rep notification.
        case armed(target: Int)

        /// Actively counting.
        case inProgress(current: Int, target: Int, baseline: Int)

        /// Workout has terminated. The associated `WorkoutSummary`
        /// describes how it ended and with what totals.
        case summary(WorkoutSummary)
    }

    // MARK: - Observable state

    private(set) var state: State = .idle

    // MARK: - Private

    /// The peripheral being observed. Non-nil while `state` is
    /// `.armed` or `.inProgress`; nil in `.idle` and `.summary`.
    private var peripheral: DiscoveredPeripheral?

    // MARK: - Lifecycle

    init() {}

    // MARK: - Public API

    /// Begin a workout attempt.
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
    /// from any state.
    func reset() {
        peripheral = nil
        state = .idle
        print("🏋️ WorkoutSession → idle (reset)")
    }

    // MARK: - Observation

    private func observePeripheral() {
        guard let peripheral else { return }

        withObservationTracking {
            _ = peripheral.hasValidatedCumulativeCount
            _ = peripheral.repCount
            // 5A.8: also observe connection lifecycle so a mid-workout
            // disconnect terminates the session with a .disconnected
            // summary instead of leaving us stuck in .armed/.inProgress
            // pointing at a dead peripheral.
            _ = peripheral.connectionState
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.handlePeripheralChange()
                self?.observePeripheral()
            }
        }
    }

    private func handlePeripheralChange() {
        guard let peripheral else { return }

        // 5A.8 (revised): a peripheral is only trustworthy when it's
        // fully .ready AND has validated its cumulative counter. Any
        // other combination during .armed/.inProgress means the rope
        // has dropped out from under us — even if connectionState
        // hasn't caught up to .disconnected yet in this observation
        // tick. Treating "not healthy" as "disconnect" (rather than
        // waiting specifically for .disconnected) closes a race where
        // repCount is reset to 0 in one dispatch and connectionState
        // is flipped in a later one: without this guard,
        // WorkoutSession would compute current = 0 - baseline and land
        // in .inProgress with a negative count, then potentially miss
        // the connectionState change on re-registration and get stuck
        // there.
        let peripheralIsHealthy =
            peripheral.connectionState == .ready
            && peripheral.hasValidatedCumulativeCount

        if !peripheralIsHealthy {
            switch state {
            case .armed(let target):
                // .armed legitimately means "healthy but not yet
                // validated," so a peripheral that's still .ready but
                // hasn't sent "Starting..." yet is fine to keep
                // waiting on. Only bail if the connection itself has
                // gone bad.
                if peripheral.connectionState != .ready {
                    let summary = WorkoutSummary(
                        resultType: .disconnected,
                        finalCount: 0,
                        target: target
                    )
                    state = .summary(summary)
                    print("🏋️ WorkoutSession → summary(.disconnected) from .armed (target: \(target))")
                    return
                }

            case .inProgress(let current, let target, _):
                // Preserve the last known good count. Do NOT recompute
                // from peripheral.repCount here — it may have been
                // reset to 0 as part of the disconnect, and using it
                // would give a nonsense negative finalCount.
                let summary = WorkoutSummary(
                    resultType: .disconnected,
                    finalCount: current,
                    target: target
                )
                state = .summary(summary)
                print("🏋️ WorkoutSession → summary(.disconnected) from .inProgress (final: \(current), target: \(target))")
                return

            case .idle, .summary:
                return
            }
        }

        switch state {
        case .idle, .summary:
            break

        case .armed(let target):
            // Reachable only when peripheralIsHealthy is true, i.e.
            // .ready AND validated — so this is exactly the moment to
            // start counting.
            state = .inProgress(
                current: 0,
                target: target,
                baseline: peripheral.repCount
            )
            print("🏋️ WorkoutSession → inProgress (baseline: \(peripheral.repCount), target: \(target))")

        case .inProgress(_, let target, let baseline):
            // Belt-and-suspenders clamp. A negative "current" is never
            // meaningful — it can only arise if peripheral.repCount
            // ends up lower than the baseline we captured when we
            // entered .inProgress. In practice that means the
            // firmware's counter was reset (or otherwise moved
            // backwards) out from under us.
            //
            // Ordinarily the peripheralIsHealthy guard above will have
            // already routed a real disconnect to
            // .summary(.disconnected) before we get here. But there's
            // no way to prove that guard covers every possible future
            // ordering of observation callbacks — and if it ever
            // doesn't, we'd rather render a stuck "0 / target" for a
            // frame than a "-1 / target" that also crashes the
            // ProgressView with an out-of-bounds warning. Clamping is
            // cheap and monotonic-safe: once we've legitimately
            // counted a rep, we never want the displayed count to go
            // backwards.
            let rawCurrent = peripheral.repCount - baseline
            let current = max(0, rawCurrent)

            if current >= target {
                let summary = WorkoutSummary(
                    resultType: .completed,
                    finalCount: current,
                    target: target
                )
                state = .summary(summary)
                print("🏋️ WorkoutSession → summary(.completed) (final: \(current), target: \(target))")
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
