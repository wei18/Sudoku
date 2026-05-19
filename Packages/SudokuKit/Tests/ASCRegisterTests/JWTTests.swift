// JWTTests — sign with an in-test P256 key, verify with its public key,
// assert header + payload claims.

internal import CryptoKit
internal import Foundation
internal import Testing
@testable import ASCRegister

@Suite("JWT")
internal struct JWTTests {

    @Test("ES256 sign produces a verifiable compact JWS")
    internal func signsAndVerifies() throws {
        let key = P256.Signing.PrivateKey()
        let pem = key.pemRepresentation

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let token = try JWT.sign(
            keyId: "test",
            issuerId: "issuer-uuid",
            keyPEM: pem,
            now: now,
            lifetimeSeconds: 20 * 60
        )

        let parts = token.split(separator: ".")
        #expect(parts.count == 3)

        // Verify signature with public key.
        let signingInput = "\(parts[0]).\(parts[1])"
        let inputData = try #require(signingInput.data(using: .utf8))
        let sigData = try #require(JWT.base64URLDecode(String(parts[2])))
        let signature = try P256.Signing.ECDSASignature(rawRepresentation: sigData)
        #expect(key.publicKey.isValidSignature(signature, for: inputData))

        // Decode and assert header.
        let headerData = try #require(JWT.base64URLDecode(String(parts[0])))
        let header = try JSONDecoder().decode(JWT.Header.self, from: headerData)
        #expect(header.alg == "ES256")
        #expect(header.kid == "test")
        #expect(header.typ == "JWT")

        // Decode and assert payload.
        let payloadData = try #require(JWT.base64URLDecode(String(parts[1])))
        let payload = try JSONDecoder().decode(JWT.Payload.self, from: payloadData)
        #expect(payload.iss == "issuer-uuid")
        #expect(payload.aud == "appstoreconnect-v1")
        #expect(payload.iat == Int(now.timeIntervalSince1970))
        let lifetime = payload.exp - payload.iat
        #expect(lifetime == 20 * 60)
    }

    @Test("Invalid PEM throws keyParseFailed")
    internal func invalidPEM() {
        #expect(throws: JWT.Error.keyParseFailed) {
            try JWT.sign(
                keyId: "k",
                issuerId: "i",
                keyPEM: "not-a-pem"
            )
        }
    }
}
