// BannerSlotRegistration — how a `BannerSlotView` joins the session's banner
// model without any lifecycle modifier (#1058 slot-model spec, "Slot
// registration without depending on the rendered subtree", spike S1).
//
// A `DynamicProperty` is installed on the view node and `update()` runs before
// every body evaluation — including for a slot whose body renders nothing, the
// exact case where `.task` / `.onAppear` / `.onChange` never run. The lease is
// a `@StateObject`, so its thunk runs once per view identity and its
// `isolated deinit` runs when that identity leaves the hierarchy.

public import SwiftUI

// MARK: - Environment

extension EnvironmentValues {
    // `@Entry` builds the key's `defaultValue` from the initializer, so the
    // explicit `nil` below is required.
    // swiftlint:disable redundant_optional_initialization
    /// The session's banner model (#1058). `nil` by default: a slot mounted
    /// without an injected model reports it through
    /// `BannerSessionModel.onMissingSession` instead of silently rendering
    /// nothing. Only previews, snapshot fixtures and DEBUG hooks that bypass
    /// monetization inject `BannerSessionModel.disabled`.
    @Entry public var bannerSession: BannerSessionModel? = nil
    // swiftlint:enable redundant_optional_initialization
}

// MARK: - Missing-session handler

extension BannerSessionModel {
    /// Called when a `BannerSlotView` is mounted with no `\.bannerSession` in
    /// its environment — a lost injection. Asserts in DEBUG; the slot renders
    /// nothing either way. Tests swap it to observe the call.
    public static var onMissingSession: @MainActor () -> Void = {
        assertionFailure("BannerSlotView mounted without a \\.bannerSession in its environment (#1058)")
    }
}

// MARK: - Registration

// `DynamicProperty.update()` is nonisolated in the Swift 6.3 SDK, so this
// conformance cannot be `@MainActor` (#ConformanceIsolation). SwiftUI calls
// `update()` during the main-thread view-graph pass; `assumeIsolated` traps
// loudly if that ever stops being true.
struct BannerSlotRegistration: DynamicProperty {
    @Environment(\.bannerSession) private var environmentSession
    @StateObject private var ownLease: BannerSlotLease
    // #1080: an externally owned lease, when supplied, is used INSTEAD of
    // `ownLease` — `ownLease` is still constructed (a `@StateObject`'s
    // storage exists unconditionally) but is never attached, so its
    // `isolated deinit` finds no session and unregisters nothing. This is
    // what lets a host that outlives this view's own identity (`GameRoot`,
    // for the `tabViewBottomAccessory` placement that gets natively
    // re-hosted) keep one lease alive across that re-hosting instead of
    // every remount registering a fresh one. Do not "simplify" this to a
    // single lease — `ownLease` existing-but-inert while `external` is set
    // is the point, not an oversight.
    private let external: BannerSlotLease?

    @MainActor
    init(lease: BannerSlotLease? = nil) {
        _ownLease = StateObject(wrappedValue: BannerSlotLease())
        external = lease
    }

    @MainActor
    private var effective: BannerSlotLease { external ?? ownLease }

    @MainActor
    var session: BannerSessionModel? { environmentSession }

    @MainActor
    var id: BannerSlotID { effective.id }

    nonisolated func update() {
        MainActor.assumeIsolated {
            guard let session = environmentSession else {
                BannerSessionModel.onMissingSession()
                return
            }
            effective.attach(to: session)
        }
    }
}

// MARK: - Lease

/// One slot view's registration with the session: created once per view
/// identity, released with it.
///
/// `public` (#1080): a host that outlives a placement's own view identity
/// (`GameAppKit.GameRoot`, for the `tabViewBottomAccessory` capsule) needs to
/// construct one of these itself and hand it to `BannerSlotView(lease:...)`.
/// `id` and `attach(to:)` stay `internal` — a host only ever needs to own the
/// lease's lifetime, never its registration mechanics.
@MainActor
public final class BannerSlotLease: ObservableObject {
    let id = BannerSlotID()
    private weak var session: BannerSessionModel?

    public init() {}

    /// Idempotent. `update()` runs many times per mount, so a repeat call with
    /// the same session must do nothing — re-registering would cancel and
    /// restart the slot's load. A different session (a re-injected
    /// environment) moves the registration.
    func attach(to session: BannerSessionModel) {
        guard self.session !== session else { return }
        self.session?.unregister(id)
        self.session = session
        session.register(id)
    }

    isolated deinit {
        session?.unregister(id)
    }
}
