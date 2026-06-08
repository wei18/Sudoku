// InspectArgumentParsingTests — verify the shared `Options` argv parser
// extracts the `--leaderboard <vendor-id>` flag introduced for the new
// `inspect` subcommand (issue #22). Network behavior is not exercised here.

internal import Foundation
internal import Testing
@testable import ASCRegister

@Suite("inspect argv parsing")
internal struct InspectArgumentParsingTests {

    @Test("--leaderboard <vendor-id> is captured by Options.parse")
    internal func leaderboardFlagCaptured() throws {
        let argv = [
            "--key", "/tmp/AuthKey.p8",
            "--key-id", "ABC123",
            "--issuer", "issuer-uuid",
            "--app-id", "1234567890",
            "--leaderboard", "test.bootstrap.delete"
        ]
        let opts = Options.parse(argv)
        #expect(opts["leaderboard"] == "test.bootstrap.delete")
        #expect(try opts.required("leaderboard") == "test.bootstrap.delete")
    }

    @Test("Missing --leaderboard surfaces CLIError.missingFlag")
    internal func missingLeaderboardFlag() {
        let opts = Options.parse(["--key", "/tmp/x.p8"])
        #expect(throws: CLIError.self) {
            _ = try opts.required("leaderboard")
        }
    }

    // MARK: - bare-flag vs value regression (#370 CR)

    /// Regression guard: `--version 2.5` must parse as the VALUE pair
    /// `version=2.5`, not as a bare boolean flag. A numeric value that does not
    /// start with `--` is consumed as the flag's argument.
    @Test("--version 2.5 is a value pair, not a bare flag")
    internal func versionWithNumericValueIsAPair() throws {
        let opts = Options.parse(["--version", "2.5"])
        #expect(opts["version"] == "2.5")
        #expect(try opts.required("version") == "2.5")
        // It must NOT be misread as a bare boolean flag.
        #expect(opts.has("version") == false)
    }

    /// A trailing `--flag` with no following token is a bare boolean (e.g.
    /// `--i-am-sure`); `has()` reports it, `subscript` does not return a value.
    @Test("trailing --i-am-sure is a bare boolean flag")
    internal func trailingBareFlag() {
        let opts = Options.parse(["--version", "2.5", "--i-am-sure"])
        #expect(opts.has("i-am-sure") == true)
        #expect(opts["i-am-sure"] == nil)
        #expect(opts["version"] == "2.5")
    }

    /// `--flag` immediately followed by another `--flag` is bare; the second is
    /// its own flag/pair — the first must NOT swallow the `--` token as a value.
    @Test("--flag followed by another --flag does not swallow it as a value")
    internal func bareFlagBeforeAnotherFlag() {
        let opts = Options.parse(["--i-am-sure", "--version", "2.5"])
        #expect(opts.has("i-am-sure") == true)
        #expect(opts["i-am-sure"] == nil)
        #expect(opts["version"] == "2.5")
    }
}
