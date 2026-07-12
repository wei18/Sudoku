// MotionGate — reduce-motion gate for the design-system's Motion table
// (docs/designs/design-system.md §Motion).
//
// The spec's Reduced-motion column is uniformly "off", not "shorter": every
// transform animation must be gated behind `accessibilityReduceMotion` so it
// simply doesn't run (the view snaps straight to its end state) rather than
// playing at a reduced duration. Before this file, that gate existed at
// exactly one call site in the repo (SettingsUI/ReminderPrimerSheet) as an
// inline ternary; every other animatable surface had no gate because it had
// no animation at all. Centralizing the ternary here means new call sites
// can't reintroduce an ungated animation by omission.

public import SwiftUI

public enum MotionGate {
    /// Returns `animation` unchanged, or `nil` (no animation — the value
    /// change applies instantly) when `reduceMotion` is true.
    public static func animation(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}
