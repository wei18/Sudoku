// Direction — the four slide directions in classic 2048.

// swiftlint:disable identifier_name
// `up` is the canonical game-domain term (2 chars); renaming it would break
// the ubiquitous language (left/right/up/down are the 4 slide directions in
// every 2048 implementation). Disabled for this file only.
public enum Direction: String, Sendable, Codable, Hashable, CaseIterable {
    case left
    case right
    case up
    case down
}
// swiftlint:enable identifier_name
