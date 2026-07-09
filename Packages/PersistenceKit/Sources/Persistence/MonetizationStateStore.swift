// MonetizationStateStore — Persistence seam for AppMonetizationKit's `AdGate`
// state (docs/v1/design.md §How.3, plan.md v2.3.1).
//
// The protocol is a type alias for `AdGateStateStore` from `MonetizationCore`:
// AdGate already operates against `AdGateStateStore`, so re-exposing the same
// shape under a Persistence-local name lets the Sudoku App's Persistence layer
// own the concrete CloudKit-Private implementation without forcing AdGate to
// know anything about CloudKit. Callers (SudokuAppComposition) can refer to either
// name; they pick the resolved underlying type at the seam.

public import MonetizationCore

/// Persistence-side alias for `MonetizationCore.AdGateStateStore`. Concrete
/// implementation is `LiveMonetizationStateStore`, which routes the load /
/// save calls through `PrivateCKGateway` onto a `MonetizationState` record
/// in `com.wei18.sudoku.userZone`.
public typealias MonetizationStateStore = AdGateStateStore
