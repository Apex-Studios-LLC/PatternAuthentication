import Foundation
import Testing
@testable import PatternAuthentication

@Suite("Gesture Credential Core")
struct GestureCredentialTests {
    @Test("Canonical encoding is stable")
    func canonicalEncodingIsStable() throws {
        let pattern = try GesturePattern([0, 4, 8])
        var expected = Data("PatternAuthentication.GesturePattern.v1".utf8)
        expected.append(0)
        expected.append(contentsOf: [0, 3, 0, 4, 8])

        #expect(pattern.canonicalData == expected)
    }

    @Test("PBKDF2-HMAC-SHA256 matches known vector")
    func pbkdf2SHA256KnownVector() throws {
        let key = try GestureCredentialHasher.deriveKey(
            password: Data("password".utf8),
            salt: Data("salt".utf8),
            kdf: .pbkdf2SHA256,
            iterations: 1,
            derivedKeyLength: 32
        )

        #expect(key.hexString == "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b")
    }

    @Test("Credentials use unique salts")
    func credentialsUseUniqueSalts() throws {
        let configuration = GestureHashConfiguration(iterations: 1, saltLength: 16)
        let first = try GestureCredentialHasher.createCredential(
            for: [0, 1, 2, 5, 8, 7],
            configuration: configuration
        )
        let second = try GestureCredentialHasher.createCredential(
            for: [0, 1, 2, 5, 8, 7],
            configuration: configuration
        )

        #expect(first.salt != second.salt)
        #expect(first.hash != second.hash)
    }

    @Test("Credential verification succeeds and fails correctly")
    func credentialVerification() throws {
        let configuration = GestureHashConfiguration(iterations: 1, saltLength: 16)
        let credential = try GestureCredentialHasher.createCredential(
            for: [0, 1, 2, 5, 8, 7],
            configuration: configuration
        )

        let success = try GestureCredentialHasher.verify(
            vertices: [0, 1, 2, 5, 8, 7],
            against: credential
        )
        let failure = try GestureCredentialHasher.verify(
            vertices: [0, 1, 2, 5, 8, 6],
            against: credential
        )

        #expect(success)
        #expect(!failure)
    }

    @Test("Base64 and JSON round trips preserve credentials")
    func storageRoundTrips() throws {
        let configuration = GestureHashConfiguration(iterations: 1, saltLength: 16)
        let credential = try GestureCredentialHasher.createCredential(
            for: [0, 3, 6, 7, 8, 5],
            configuration: configuration
        )

        let base64RoundTrip = try GestureCredentialEnvelope(
            base64Representation: credential.base64Representation
        )
        let jsonRoundTrip = try GestureCredentialEnvelope.fromJSONData(
            credential.jsonData()
        )

        #expect(base64RoundTrip == credential)
        #expect(jsonRoundTrip == credential)
    }

    @Test("Invalid base64 storage fields throw typed errors")
    func invalidBase64StorageThrows() {
        #expect(throws: GestureCredentialError.self) {
            try GestureCredentialEnvelope(base64Representation: .init(
                salt: "not-base64",
                hash: Data([1, 2, 3]).base64EncodedString(),
                kdf: .pbkdf2SHA256,
                iterations: 1,
                hashVersion: 1,
                derivedKeyLength: 32
            ))
        }

        #expect(throws: GestureCredentialError.self) {
            try GestureCredentialEnvelope(base64Representation: .init(
                salt: Data([1, 2, 3]).base64EncodedString(),
                hash: "not-base64",
                kdf: .pbkdf2SHA256,
                iterations: 1,
                hashVersion: 1,
                derivedKeyLength: 32
            ))
        }
    }

    @Test("Legacy hashes remain verifiable")
    func legacyVerification() {
        let pattern = [0, 4, 8, 5, 2, 1]
        let legacyHash = legacyHashArray(pattern)

        #expect(hashArray(pattern) == legacyHash)
        #expect(GestureCredentialHasher.verifyLegacySHA256(vertices: pattern, expectedHash: legacyHash))
        #expect(!GestureCredentialHasher.verifyLegacySHA256(vertices: [0, 4, 8], expectedHash: legacyHash))
    }

    @Test("Legacy hashes can be migrated after a successful match")
    func legacyMigration() throws {
        let pattern = [0, 4, 8, 5, 2, 1]
        let legacyHash = legacyHashArray(pattern)
        let configuration = GestureHashConfiguration(iterations: 1, saltLength: 16)

        let credential = try #require(try GestureCredentialHasher.upgradeLegacyCredential(
            vertices: pattern,
            expectedHash: legacyHash,
            configuration: configuration
        ))

        let verifies = try GestureCredentialHasher.verify(vertices: pattern, against: credential)
        #expect(verifies)

        let failedUpgrade = try GestureCredentialHasher.upgradeLegacyCredential(
            vertices: [0, 4, 8],
            expectedHash: legacyHash,
            configuration: configuration
        )
        #expect(failedUpgrade == nil)
    }

    @Test("Constant-time comparison returns correct equality")
    func constantTimeComparison() {
        #expect(GestureCredentialHasher.constantTimeEquals(Data([1, 2, 3]), Data([1, 2, 3])))
        #expect(!GestureCredentialHasher.constantTimeEquals(Data([1, 2, 3]), Data([1, 2, 4])))
        #expect(!GestureCredentialHasher.constantTimeEquals(Data([1, 2, 3]), Data([1, 2, 3, 4])))
    }

    @Test("Invalid patterns are rejected")
    func invalidPatternFails() {
        #expect(throws: GestureCredentialError.self) {
            try GesturePattern([0, 9])
        }

        #expect(throws: GestureCredentialError.self) {
            try GesturePattern([])
        }
    }

    @Test("Configuration validation rejects unusable values")
    func invalidConfigurationFails() {
        #expect(throws: GestureCredentialError.self) {
            try GestureCredentialHasher.createCredential(
                for: [0, 1, 2],
                configuration: GestureHashConfiguration(iterations: 0)
            )
        }

        #expect(throws: GestureCredentialError.self) {
            try GestureCredentialHasher.createCredential(
                for: [0, 1, 2],
                configuration: GestureHashConfiguration(iterations: 1, saltLength: 15)
            )
        }

        #expect(throws: GestureCredentialError.self) {
            try GestureCredentialHasher.createCredential(
                for: [0, 1, 2],
                configuration: GestureHashConfiguration(
                    iterations: 1,
                    saltLength: 16,
                    derivedKeyLength: 15
                )
            )
        }

        #expect(throws: GestureCredentialError.self) {
            try GestureCredentialHasher.createCredential(
                for: [0, 1, 2],
                configuration: GestureHashConfiguration(
                    iterations: 1,
                    saltLength: 16,
                    derivedKeyLength: 16,
                    hashVersion: 0
                )
            )
        }
    }

    @Test("Credential validation rejects malformed envelopes")
    func malformedCredentialFails() {
        #expect(throws: GestureCredentialError.self) {
            try GestureCredentialHasher.verify(
                vertices: [0, 1, 2],
                against: GestureCredentialEnvelope(
                    salt: Data(repeating: 1, count: 15),
                    hash: Data(repeating: 2, count: 32),
                    kdf: .pbkdf2SHA256,
                    iterations: 1,
                    hashVersion: 1,
                    derivedKeyLength: 32
                )
            )
        }

        #expect(throws: GestureCredentialError.self) {
            try GestureCredentialHasher.verify(
                vertices: [0, 1, 2],
                against: GestureCredentialEnvelope(
                    salt: Data(repeating: 1, count: 16),
                    hash: Data(repeating: 2, count: 31),
                    kdf: .pbkdf2SHA256,
                    iterations: 1,
                    hashVersion: 1,
                    derivedKeyLength: 32
                )
            )
        }
    }

    @Test("Credential errors have readable descriptions")
    func credentialErrorDescriptions() {
        let errors: [GestureCredentialError] = [
            .emptyPattern,
            .invalidVertex(9),
            .patternTooLong(70_000),
            .invalidIterationCount(0),
            .invalidSaltLength(1),
            .invalidDerivedKeyLength(1),
            .invalidHashVersion(0),
            .secureRandomFailed(-1),
            .unsupportedKDF(.pbkdf2SHA256),
            .derivationFailed(-1),
            .invalidBase64(field: "salt"),
        ]

        #expect(errors.allSatisfy { !$0.description.isEmpty })
    }

    @Test("Spark asset is available from the package bundle")
    @MainActor
    func sparkAssetLoads() {
        #expect(PatternAuthenticationResourceProbe.sparkImageExists)
    }
}

private extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
