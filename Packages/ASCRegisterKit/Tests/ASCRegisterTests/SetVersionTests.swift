// SetVersionTests — pure coverage for `metadata set-version` (#310): the
// editable-version selection / state guard (`SetVersionResolver.choose`) and
// the PATCH body shape (`ASCClient.setVersionStringBody`). No live ASC — the
// resolver is fed a decoded version list, the body builder is static (mirrors
// nextPageLink / isDuplicateValueError unit tests).

internal import Foundation
internal import Testing
@testable import ASCRegister

private typealias Ver = SetVersionResolver.Version

// MARK: - Editable-version selection / state guard

@Suite("set-version editable-state guard (#310)")
internal struct SetVersionResolverTests {

    @Test("Single PREPARE_FOR_SUBMISSION version is chosen")
    internal func singleEditableChosen() throws {
        let result = SetVersionResolver.choose(
            versions: [Ver(id: "v1", versionString: "1.0", state: "PREPARE_FOR_SUBMISSION")],
            versionFilter: nil
        )
        let chosen = try #require(try result.get())
        #expect(chosen.id == "v1")
        #expect(chosen.versionString == "1.0")
    }

    @Test("Every editable state is selectable")
    internal func eachEditableState() throws {
        for state in SetVersionResolver.editableVersionStates {
            let result = SetVersionResolver.choose(
                versions: [Ver(id: "v1", versionString: "1.0", state: state)],
                versionFilter: nil
            )
            #expect((try? result.get()) != nil, "\(state) should be selectable")
        }
    }

    @Test("Released/locked-only version → noneEditable, no mutation path")
    internal func releasedRefused() {
        for locked in ["READY_FOR_SALE", "PENDING_APPLE_RELEASE", "IN_REVIEW", "PROCESSING_FOR_APP_STORE"] {
            let result = SetVersionResolver.choose(
                versions: [Ver(id: "v1", versionString: "2.3.4", state: locked)],
                versionFilter: nil
            )
            guard case .failure(let error) = result else {
                Issue.record("expected failure for \(locked)")
                continue
            }
            #expect(error == .noneEditable(states: [locked]))
        }
    }

    @Test("--version naming a single released version → locked error names the state")
    internal func filterLockedNamesState() {
        let result = SetVersionResolver.choose(
            versions: [Ver(id: "v1", versionString: "2.3.4", state: "READY_FOR_SALE")],
            versionFilter: "2.3.4"
        )
        guard case .failure(let error) = result else {
            Issue.record("expected failure")
            return
        }
        #expect(error == .locked(versionString: "2.3.4", state: "READY_FOR_SALE"))
        #expect(error.description.contains("READY_FOR_SALE"))
    }

    @Test("Empty version list → noVersions")
    internal func emptyList() {
        let result = SetVersionResolver.choose(versions: [], versionFilter: nil)
        #expect((try? result.get()) == nil)
        if case .failure(let error) = result { #expect(error == .noVersions) }
    }

    @Test("Multiple editable, one PREPARE_FOR_SUBMISSION → picks it")
    internal func multipleEditablePicksPrepare() throws {
        let result = SetVersionResolver.choose(
            versions: [
                Ver(id: "v1", versionString: "2.3.4", state: "WAITING_FOR_REVIEW"),
                Ver(id: "v2", versionString: "1.0", state: "PREPARE_FOR_SUBMISSION"),
            ],
            versionFilter: nil
        )
        let chosen = try #require(try result.get())
        #expect(chosen.id == "v2")
    }

    @Test("Multiple editable, none PREPARE_FOR_SUBMISSION → ambiguous asks for --version")
    internal func multipleEditableAmbiguous() {
        let result = SetVersionResolver.choose(
            versions: [
                Ver(id: "v1", versionString: "2.3.4", state: "WAITING_FOR_REVIEW"),
                Ver(id: "v2", versionString: "2.3.5", state: "DEVELOPER_REJECTED"),
            ],
            versionFilter: nil
        )
        guard case .failure(let error) = result else {
            Issue.record("expected ambiguous failure")
            return
        }
        #expect(error == .ambiguous(versionStrings: ["2.3.4", "2.3.5"]))
        #expect(error.description.contains("--version"))
    }

    @Test("--version filter narrows to the matching editable version")
    internal func filterNarrows() throws {
        let result = SetVersionResolver.choose(
            versions: [
                Ver(id: "v1", versionString: "2.3.4", state: "PREPARE_FOR_SUBMISSION"),
                Ver(id: "v2", versionString: "2.3.5", state: "PREPARE_FOR_SUBMISSION"),
            ],
            versionFilter: "2.3.5"
        )
        let chosen = try #require(try result.get())
        #expect(chosen.id == "v2")
    }
}

// MARK: - Idempotent no-change detection

@Suite("set-version idempotent no-change (#310)")
internal struct SetVersionIdempotencyTests {

    // The CLI compares chosen.versionString == target and exits without a PATCH.
    // Verified here at the resolver level (the chosen version's current string),
    // which is what the no-change branch inspects.
    @Test("Editable version already at target ⇒ chosen string equals target")
    internal func alreadyAtTargetIsNoChange() throws {
        let target = "2.3.5"
        let result = SetVersionResolver.choose(
            versions: [Ver(id: "v1", versionString: "2.3.5", state: "PREPARE_FOR_SUBMISSION")],
            versionFilter: nil
        )
        let chosen = try #require(try result.get())
        #expect(chosen.versionString == target)  // CLI takes the no-mutation exit
    }

    @Test("Editable version differs from target ⇒ rename needed")
    internal func differsNeedsRename() throws {
        let result = SetVersionResolver.choose(
            versions: [Ver(id: "v1", versionString: "1.0", state: "PREPARE_FOR_SUBMISSION")],
            versionFilter: nil
        )
        let chosen = try #require(try result.get())
        #expect(chosen.versionString != "2.3.5")  // CLI sends the PATCH
    }
}

// MARK: - PATCH body shape

@Suite("set-version PATCH body shape (#310)")
internal struct SetVersionBodyTests {

    @Test("Body carries type/id/attributes.versionString")
    internal func bodyShape() throws {
        let body = ASCClient.setVersionStringBody(versionId: "abc123", versionString: "2.3.5")
        let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let dataObj = try #require(json["data"] as? [String: Any])
        #expect(dataObj["type"] as? String == "appStoreVersions")
        #expect(dataObj["id"] as? String == "abc123")
        let attrs = try #require(dataObj["attributes"] as? [String: Any])
        #expect(attrs["versionString"] as? String == "2.3.5")
        // No relationships / extra keys — a versionString-only PATCH.
        #expect(Set(dataObj.keys) == ["type", "id", "attributes"])
        #expect(Set(attrs.keys) == ["versionString"])
    }
}
