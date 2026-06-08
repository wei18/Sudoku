// ScreenshotSetIndexTests — pure coverage for the remote-screenshot indexing
// that drives upload idempotency (#370). The orchestration must distinguish a
// COMPLETE asset (truly present → skip) from a non-COMPLETE one (a prior
// reserve whose PUT/commit failed → re-upload), and detect content drift via
// `sourceFileChecksum`. These build the lookup from a canned JSON:API response
// with no live ASC call.

internal import Foundation
internal import Testing
@testable import ASCRegister

@Suite("ScreenshotSetIndex remote state (#370)")
internal struct ScreenshotSetIndexTests {

    /// A `listScreenshotSets` body with one set holding three screenshots:
    /// a COMPLETE one, a non-COMPLETE (AWAITING_UPLOAD) one, and a COMPLETE one
    /// carrying a sourceFileChecksum (for drift comparison).
    private static let body = #"""
    {"data":[
      {"id":"set-67","type":"appScreenshotSets",
       "attributes":{"screenshotDisplayType":"APP_IPHONE_67"},
       "relationships":{"appScreenshots":{"data":[
         {"id":"shot-complete","type":"appScreenshots"},
         {"id":"shot-pending","type":"appScreenshots"},
         {"id":"shot-checksum","type":"appScreenshots"}
       ]}}}
    ],
    "included":[
      {"id":"shot-complete","type":"appScreenshots",
       "attributes":{"fileName":"01-home.png",
         "assetDeliveryState":{"state":"COMPLETE"}}},
      {"id":"shot-pending","type":"appScreenshots",
       "attributes":{"fileName":"02-game.png",
         "assetDeliveryState":{"state":"AWAITING_UPLOAD"}}},
      {"id":"shot-checksum","type":"appScreenshots",
       "attributes":{"fileName":"03-win.png",
         "sourceFileChecksum":"abc123",
         "assetDeliveryState":{"state":"COMPLETE"}}}
    ],
    "links":{}}
    """#

    private static func index() throws -> [String: [String: ScreenshotRemoteState]] {
        let collection = try APICollectionWithIncluded.decode(
            from: Data(Self.body.utf8), path: "/test", status: 200
        )
        return ScreenshotSetIndex.screenshotsBySetId(collection)
    }

    @Test("indexes each screenshot by setId then fileName with id + delivery state")
    internal func indexesByName() throws {
        let index = try Self.index()
        let inSet = try #require(index["set-67"])
        #expect(inSet.count == 3)
        #expect(inSet["01-home.png"]?.id == "shot-complete")
        #expect(inSet["01-home.png"]?.assetDeliveryState == "COMPLETE")
        #expect(inSet["02-game.png"]?.assetDeliveryState == "AWAITING_UPLOAD")
    }

    @Test("COMPLETE asset reports isComplete; non-COMPLETE does not")
    internal func completeFlag() throws {
        let inSet = try #require(try Self.index()["set-67"])
        #expect(inSet["01-home.png"]?.isComplete == true)
        #expect(inSet["02-game.png"]?.isComplete == false)
    }

    @Test("surfaces sourceFileChecksum when present, nil otherwise")
    internal func checksumSurfaced() throws {
        let inSet = try #require(try Self.index()["set-67"])
        #expect(inSet["03-win.png"]?.sourceFileChecksum == "abc123")
        #expect(inSet["01-home.png"]?.sourceFileChecksum == nil)
    }
}
