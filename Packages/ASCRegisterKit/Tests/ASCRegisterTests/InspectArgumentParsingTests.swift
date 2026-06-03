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
}
