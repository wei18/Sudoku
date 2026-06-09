// ConfigLocaleMappingTests — pin the xcstrings → ASC locale code map.
// Issue #31: round-6 apply failed with `LOCALE_INVALID` because we sent
// the bare xcstrings code (e.g. `"en"`) to ASC, which wants the regional
// form (`"en-US"`). One assertion per known code + a default-passthrough
// guard so an unknown code surfaces ASC-side rather than silently
// short-circuiting.

internal import Testing
@testable import ASCRegister

@Suite("Config.ascLocaleCode")
internal struct ConfigLocaleMappingTests {

    @Test("en → en-US")
    internal func en() {
        #expect(Config.ascLocaleCode(for: "en") == "en-US")
    }

    @Test("zh-Hant → zh-Hant (no region, per issue #37)")
    internal func zhHant() {
        #expect(Config.ascLocaleCode(for: "zh-Hant") == "zh-Hant")
    }

    @Test("zh-Hans → zh-Hans (no region, per issue #37)")
    internal func zhHans() {
        #expect(Config.ascLocaleCode(for: "zh-Hans") == "zh-Hans")
    }

    @Test("ja → ja (educated guess; see §未決)")
    internal func ja() {
        #expect(Config.ascLocaleCode(for: "ja") == "ja")
    }

    @Test("es → es-ES (educated guess; see §未決)")
    internal func es() {
        #expect(Config.ascLocaleCode(for: "es") == "es-ES")
    }

    @Test("th → th-TH")
    internal func th() {
        #expect(Config.ascLocaleCode(for: "th") == "th-TH")
    }

    @Test("ko → ko-KR")
    internal func ko() {
        #expect(Config.ascLocaleCode(for: "ko") == "ko-KR")
    }

    @Test("Unknown code passes through unchanged")
    internal func unknownPassthrough() {
        // Preserves any future-added locale without re-touching the map;
        // ASC will reply LOCALE_INVALID and the gap surfaces on apply.
        #expect(Config.ascLocaleCode(for: "fr") == "fr")
        #expect(Config.ascLocaleCode(for: "xx-YY") == "xx-YY")
    }
}

// IAP localizations use ASC's app-level locale catalog (like metadata), which
// wants bare `th` / `ko` — NOT the GC-tuned `th-TH` / `ko-KR`. A live `iap
// apply` (#432, 2026-06-09) got IAP_LOCALIZATION_UNSUPPORTED_LOCALE_CODE for
// `th-TH`; this suite pins the IAP variant so the two paths can't re-converge.
@Suite("Config.ascIAPLocaleCode")
internal struct ConfigIAPLocaleMappingTests {

    @Test("th → th (NOT th-TH, unlike Game Center)")
    internal func th() {
        #expect(Config.ascIAPLocaleCode(for: "th") == "th")
        #expect(Config.ascLocaleCode(for: "th") == "th-TH")  // GC path unchanged
    }

    @Test("ko → ko (NOT ko-KR, unlike Game Center)")
    internal func ko() {
        #expect(Config.ascIAPLocaleCode(for: "ko") == "ko")
        #expect(Config.ascLocaleCode(for: "ko") == "ko-KR")  // GC path unchanged
    }

    @Test("Other locales delegate to ascLocaleCode")
    internal func delegates() {
        #expect(Config.ascIAPLocaleCode(for: "en") == "en-US")
        #expect(Config.ascIAPLocaleCode(for: "es") == "es-ES")
        #expect(Config.ascIAPLocaleCode(for: "zh-Hant") == "zh-Hant")
        #expect(Config.ascIAPLocaleCode(for: "ja") == "ja")
    }
}
