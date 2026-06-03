// JWT — ES256 signer for App Store Connect API.
//
// ASC requires a short-lived ES256 JWT signed with the issuer's .p8 key:
//   header  = { "alg": "ES256", "kid": <keyId>, "typ": "JWT" }
//   payload = { "iss": <issuerId>, "iat": now, "exp": now+20min,
//               "aud": "appstoreconnect-v1" }
//   token   = base64url(header) + "." + base64url(payload) + "." + base64url(sig)
//
// We sign with CryptoKit `P256.Signing.PrivateKey.signature(for:)`, which
// produces a 64-byte raw IEEE P1363 R||S — exactly what JWT ES256 expects
// (no DER unwrap needed). No external deps.

import CryptoKit
import Foundation

// swiftlint:disable identifier_name

internal struct JWT: Sendable {

    internal struct Header: Codable, Sendable {
        internal let alg: String
        internal let kid: String
        internal let typ: String
    }

    internal struct Payload: Codable, Sendable {
        internal let iss: String
        internal let iat: Int
        internal let exp: Int
        internal let aud: String
    }

    internal enum Error: Swift.Error, Equatable {
        case keyFileUnreadable(path: String)
        case keyParseFailed
        case encodingFailed
    }

    /// Sign a fresh ASC token. `now` injected for testability.
    internal static func sign(
        keyId: String,
        issuerId: String,
        keyPEM: String,
        now: Date = Date(),
        lifetimeSeconds: Int = 20 * 60
    ) throws -> String {
        let key = try parsePrivateKey(pem: keyPEM)
        let header = Header(alg: "ES256", kid: keyId, typ: "JWT")
        let issued = Int(now.timeIntervalSince1970)
        let payload = Payload(
            iss: issuerId,
            iat: issued,
            exp: issued + lifetimeSeconds,
            aud: "appstoreconnect-v1"
        )
        let encoder = JSONEncoder()
        // Stable key ordering — JWT verifiers don't care about order but
        // it makes test fixtures byte-stable.
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let headerData = try encoder.encode(header)
        let payloadData = try encoder.encode(payload)
        let signingInput = base64URL(headerData) + "." + base64URL(payloadData)
        guard let signingBytes = signingInput.data(using: .utf8) else {
            throw Error.encodingFailed
        }
        let signature = try key.signature(for: signingBytes)
        // CryptoKit returns rawRepresentation = R||S, 64 bytes — already P1363.
        let sigBytes = signature.rawRepresentation
        return signingInput + "." + base64URL(sigBytes)
    }

    /// Read a `.p8` file and sign with it.
    internal static func sign(
        keyId: String,
        issuerId: String,
        keyFileURL: URL,
        now: Date = Date(),
        lifetimeSeconds: Int = 20 * 60
    ) throws -> String {
        guard let data = try? Data(contentsOf: keyFileURL),
              let pem = String(data: data, encoding: .utf8)
        else {
            throw Error.keyFileUnreadable(path: keyFileURL.path)
        }
        return try sign(
            keyId: keyId,
            issuerId: issuerId,
            keyPEM: pem,
            now: now,
            lifetimeSeconds: lifetimeSeconds
        )
    }

    // MARK: - Helpers

    /// CryptoKit accepts PEM via `PrivateKey(pemRepresentation:)` (CryptoKit
    /// for Apple platforms exposes this API; on macOS 13+ it ships in the
    /// system framework).
    internal static func parsePrivateKey(pem: String) throws -> P256.Signing.PrivateKey {
        do {
            return try P256.Signing.PrivateKey(pemRepresentation: pem)
        } catch {
            throw Error.keyParseFailed
        }
    }

    internal static func base64URL(_ data: Data) -> String {
        var s = data.base64EncodedString()
        s = s.replacingOccurrences(of: "+", with: "-")
        s = s.replacingOccurrences(of: "/", with: "_")
        s = s.replacingOccurrences(of: "=", with: "")
        return s
    }

    /// Decode a base64url segment back to Data (for tests / debug).
    internal static func base64URLDecode(_ s: String) -> Data? {
        var t = s
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // Re-pad
        while t.count % 4 != 0 { t.append("=") }
        return Data(base64Encoded: t)
    }
}
// swiftlint:enable identifier_name
