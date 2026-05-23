// swiftlint:disable identifier_name

import Foundation
import Testing
@testable import MonetizationCore

// Test stand-in for a platform window. The registry stores `AnyObject`
// weakly; using a plain class here exercises the weak-ref / deinit path
// without dragging UIKit / AppKit into the test target.
private final class StubWindow {
    let tag: String
    init(_ tag: String) { self.tag = tag }
}

@Suite("AdPresentationAnchorRegistry — register / resolve / weak-clear")
struct AdPresentationAnchorRegistryTests {

    @Test func registerThenResolveRoundTrips() async {
        let registry = AdPresentationAnchorRegistry()
        let anchor = AdPresentationAnchor()
        let window = StubWindow("a")
        await registry.register(anchor, window: WindowRef(window))
        let resolved = await registry.resolve(anchor)?.unsafeAnyObject as? StubWindow
        #expect(resolved === window)
    }

    @Test func resolveUnregisteredReturnsNil() async {
        let registry = AdPresentationAnchorRegistry()
        let anchor = AdPresentationAnchor()
        let resolved = await registry.resolve(anchor)
        #expect(resolved == nil)
    }

    @Test func unregisterRemovesEntry() async {
        let registry = AdPresentationAnchorRegistry()
        let anchor = AdPresentationAnchor()
        let window = StubWindow("a")
        await registry.register(anchor, window: WindowRef(window))
        await registry.unregister(anchor)
        #expect(await registry.resolve(anchor) == nil)
    }

    @Test func reRegisterReplacesPriorEntry() async {
        let registry = AdPresentationAnchorRegistry()
        let anchor = AdPresentationAnchor()
        let firstWindow = StubWindow("first")
        let secondWindow = StubWindow("second")
        await registry.register(anchor, window: WindowRef(firstWindow))
        await registry.register(anchor, window: WindowRef(secondWindow))
        let resolved = await registry.resolve(anchor)?.unsafeAnyObject as? StubWindow
        #expect(resolved === secondWindow)
        #expect(resolved?.tag == "second")
    }

    @Test func weakReferenceClearsAfterDeinit() async {
        let registry = AdPresentationAnchorRegistry()
        let anchor = AdPresentationAnchor()
        // Scope the window so it deinitialises before we resolve.
        do {
            let window = StubWindow("transient")
            await registry.register(anchor, window: WindowRef(window))
            // Sanity: still alive inside the scope.
            #expect(await registry.resolve(anchor) != nil)
        }
        // Window has been deallocated; weak ref should now resolve nil.
        #expect(await registry.resolve(anchor) == nil)
    }

    @Test func liveEntryCountExcludesDeallocatedEntries() async {
        let registry = AdPresentationAnchorRegistry()
        let aliveAnchor = AdPresentationAnchor()
        let deadAnchor = AdPresentationAnchor()
        let aliveWindow = StubWindow("alive")
        await registry.register(aliveAnchor, window: WindowRef(aliveWindow))
        do {
            let transient = StubWindow("dead")
            await registry.register(deadAnchor, window: WindowRef(transient))
        }
        // Two registered, but the `dead` entry's window was scoped to the
        // `do` block and has been deallocated.
        #expect(await registry.liveEntryCount == 1)
        #expect(await registry.resolve(aliveAnchor) != nil)
        #expect(await registry.resolve(deadAnchor) == nil)
    }
}
