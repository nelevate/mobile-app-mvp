# Milestone 5A — Minimal Timer-Gated Workout Session

**Status:** ✅ Closed
**Closed:** August 2026
**Commit:** see `git log` for the "Milestone 5A" checkpoint on `main`

---

## Objective

Transform the Milestone 4D BLE diagnostic prototype into the first minimal
workout-session prototype: a real Start → count → Stop / auto-stop → frozen
summary lifecycle, physically validated against the Nelevate Pulse Rope.

## What Was Built

### Workout state machine

A single enum in `WorkoutSession` is the source of truth for workout
lifecycle. No conflicting booleans, no ad-hoc flags.

```swift
enum State: Equatable {
    case idle
    case armed(target: Int)
    case inProgress(current: Int, target: Int, baseline: Int)
    case summary(WorkoutSummary)
}
