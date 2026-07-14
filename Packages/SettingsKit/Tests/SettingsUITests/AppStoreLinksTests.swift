// AppStoreLinksTests — pure URL-construction + validity tests (#744).
//
// No Bundle.main / SettingsScreen involved — these pin the id → URL mapping
// and the "hide the rows" validity check in isolation, per the issue's
// acceptance criteria ("unit-test the URL construction … and the row
// visibility logic").

import Foundation
import Testing
@testable import SettingsUI

@Suite("SettingsUI — AppStoreLinks")
struct AppStoreLinksTests {

    @Test func shareURL_buildsAppStoreListingLink() {
        #expect(
            AppStoreLinks.shareURL(appStoreID: "1234567890")
                == URL(string: "https://apps.apple.com/app/id1234567890")
        )
    }

    @Test func reviewURL_buildsWriteReviewDeepLink() {
        #expect(
            AppStoreLinks.reviewURL(appStoreID: "1234567890")
                == URL(string: "https://apps.apple.com/app/id1234567890?action=write-review")
        )
    }

    @Test func isValid_trueForAPlausibleId() {
        #expect(AppStoreLinks.isValid(appStoreID: "1234567890") == true)
        // The committed .example template's fake id is still "valid" — it
        // renders a well-formed (if non-functional) URL, same tradeoff as
        // ADMOB_APP_ID's check.
        #expect(AppStoreLinks.isValid(appStoreID: "0000000000") == true)
    }

    @Test func isValid_falseWhenNil() {
        #expect(AppStoreLinks.isValid(appStoreID: nil) == false)
    }

    @Test func isValid_falseWhenEmpty() {
        #expect(AppStoreLinks.isValid(appStoreID: "") == false)
    }

    @Test func isValid_falseForUnresolvedXcconfigToken() {
        // The shape Bundle.main reports when Tuist/AppStore.xcconfig was
        // never rendered (fresh clone, no local xcconfig, no XCC env vars).
        #expect(AppStoreLinks.isValid(appStoreID: "$(APP_STORE_ID)") == false)
    }

    @Test func shareURL_nilWhenInvalid() {
        #expect(AppStoreLinks.shareURL(appStoreID: nil) == nil)
        #expect(AppStoreLinks.shareURL(appStoreID: "") == nil)
        #expect(AppStoreLinks.shareURL(appStoreID: "$(APP_STORE_ID)") == nil)
    }

    @Test func reviewURL_nilWhenInvalid() {
        #expect(AppStoreLinks.reviewURL(appStoreID: nil) == nil)
        #expect(AppStoreLinks.reviewURL(appStoreID: "") == nil)
        #expect(AppStoreLinks.reviewURL(appStoreID: "$(APP_STORE_ID)") == nil)
    }
}
