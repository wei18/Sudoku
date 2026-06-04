// ASCClientPaginationTests — pure-function coverage for the issue #310
// metadata-snapshot reliability fixes:
//   - `nextPageLink(from:)` cursor extraction (paginated version-loc capture)
//   - `isDuplicateValueError(body:)` 409-DUPLICATE detection (CREATE→PATCH
//     self-heal fallback)
//
// Both are static + pure so they test without URLSession, matching the
// hermetic style of ASCClientErrorTests.

internal import Foundation
internal import Testing
@testable import ASCRegister

@Suite("ASCClient pagination + dup detection")
internal struct ASCClientPaginationTests {

    // MARK: - links.next extraction

    @Test("nextPageLink returns the cursor URL when links.next present")
    internal func nextLinkPresent() {
        let body = #"""
        {"data": [], "links": {"self": "https://api/x?cursor=A",
        "next": "https://api/x?cursor=B"}}
        """#
        #expect(ASCClient.nextPageLink(from: Data(body.utf8)) == "https://api/x?cursor=B")
    }

    @Test("nextPageLink returns nil on the last page (no next key)")
    internal func nextLinkAbsentIsLastPage() {
        let body = #"{"data": [], "links": {"self": "https://api/x?cursor=Z"}}"#
        #expect(ASCClient.nextPageLink(from: Data(body.utf8)) == nil)
    }

    @Test("nextPageLink returns nil for null / empty next")
    internal func nextLinkNullOrEmpty() {
        #expect(ASCClient.nextPageLink(from: Data(#"{"links": {"next": null}}"#.utf8)) == nil)
        #expect(ASCClient.nextPageLink(from: Data(#"{"links": {"next": ""}}"#.utf8)) == nil)
        #expect(ASCClient.nextPageLink(from: Data(#"{"data": []}"#.utf8)) == nil)
        #expect(ASCClient.nextPageLink(from: Data("not json".utf8)) == nil)
    }

    // MARK: - 409 duplicate detection

    @Test("isDuplicateValueError matches the live es-ES DUPLICATE body")
    internal func dupErrorLiveBody() {
        // The actual ASC 409 body shape from the live MS apply (issue #310).
        let body = #"""
        {"errors":[{"status":"409","code":"ENTITY_ERROR.ATTRIBUTE.INVALID.DUPLICATE",
        "title":"The provided entity includes an attribute with a value that has already been used",
        "detail":"The attribute 'locale' with value 'es-ES' already exists. Try updating.",
        "source":{"pointer":"/data/attributes/locale"}}]}
        """#
        #expect(ASCClient.isDuplicateValueError(body: body))
    }

    @Test("isDuplicateValueError matches the human 'already exists ... updating' phrasing")
    internal func dupErrorPhrasingFallback() {
        let body = "locale es-ES already exists. Try updating."
        #expect(ASCClient.isDuplicateValueError(body: body))
    }

    @Test("isDuplicateValueError does NOT match unrelated 409s")
    internal func dupErrorNoFalsePositive() {
        let relationshipInvalid = #"""
        {"errors":[{"status":"409","code":"ENTITY_ERROR.RELATIONSHIP.INVALID",
        "detail":"primaryCategory is not valid"}]}
        """#
        #expect(!ASCClient.isDuplicateValueError(body: relationshipInvalid))
        #expect(!ASCClient.isDuplicateValueError(body: "some unrelated error"))
        #expect(!ASCClient.isDuplicateValueError(body: ""))
    }
}
