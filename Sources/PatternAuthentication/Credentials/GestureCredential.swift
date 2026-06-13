import CommonCrypto
import Foundation
import Security

/// A typed error returned while creating, decoding, or verifying gesture credentials.
///
/// `GestureCredentialError` is used by the v1 credential APIs so callers can
/// distinguish malformed input, unsupported credential metadata, random-number
/// generation failures, and PBKDF2 failures.
public enum GestureCredentialError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The gesture pattern did not contain any vertices.
    case emptyPattern

    /// A gesture vertex was outside the supported 3x3 grid range.
    case invalidVertex(Int)

    /// The gesture contained more vertices than the canonical encoder can store.
    case patternTooLong(Int)

    /// The PBKDF2 iteration count was not positive.
    case invalidIterationCount(Int)

    /// The salt length was outside the supported 16...64 byte range.
    case invalidSaltLength(Int)

    /// The derived key length was outside the supported 16...64 byte range.
    case invalidDerivedKeyLength(Int)

    /// The stored hash byte count did not match the envelope's derived key length.
    case hashLengthMismatch(expected: Int, actual: Int)

    /// The credential version was not positive.
    case invalidHashVersion(Int)

    /// Secure random byte generation failed.
    case secureRandomFailed(OSStatus)

    /// The credential requested a key-derivation function this package does not support.
    case unsupportedKDF(GestureKDF)

    /// CommonCrypto failed while deriving a credential hash.
    case derivationFailed(Int32)

    /// A base64-encoded credential field could not be decoded.
    case invalidBase64(field: String)

    /// A human-readable description of the credential error.
    ///
    /// - Returns: A diagnostic string suitable for logging or developer-facing
    ///   troubleshooting. It is not localized.
    public var description: String {
        switch self {
        case .emptyPattern:
            "A gesture pattern must contain at least one vertex."
        case let .invalidVertex(vertex):
            "Gesture vertex \(vertex) is outside the supported 3x3 grid range."
        case let .patternTooLong(count):
            "Gesture pattern length \(count) exceeds the supported canonical encoding length."
        case let .invalidIterationCount(iterations):
            "PBKDF2 iteration count must be positive, got \(iterations)."
        case let .invalidSaltLength(length):
            "Salt length must be between 16 and 64 bytes, got \(length)."
        case let .invalidDerivedKeyLength(length):
            "Derived key length must be between 16 and 64 bytes, got \(length)."
        case let .hashLengthMismatch(expected, actual):
            "Credential hash length \(actual) does not match derived key length \(expected)."
        case let .invalidHashVersion(version):
            "Hash version must be positive, got \(version)."
        case let .secureRandomFailed(status):
            "Secure random salt generation failed with OSStatus \(status)."
        case let .unsupportedKDF(kdf):
            "Unsupported gesture KDF: \(kdf.rawValue)."
        case let .derivationFailed(status):
            "PBKDF2 derivation failed with status \(status)."
        case let .invalidBase64(field):
            "Credential field \(field) is not valid base64."
        }
    }
}

/// A supported key-derivation algorithm for gesture credentials.
///
/// The v1 credential format currently supports PBKDF2-HMAC-SHA256. The enum is
/// persisted in credentials so future versions can add algorithms without
/// changing the envelope shape.
public enum GestureKDF: String, Codable, CaseIterable, Sendable {
    /// PBKDF2 using HMAC-SHA256.
    case pbkdf2SHA256 = "pbkdf2-sha256"
}

/// Configuration used when creating a new gesture credential.
public struct GestureHashConfiguration: Codable, Equatable, Sendable {
    /// The default configuration for new v1 gesture credentials.
    ///
    /// - Returns: A PBKDF2-HMAC-SHA256 configuration with 600,000 iterations,
    ///   32 bytes of salt, a 32-byte derived key, and hash version `1`.
    public static let recommended = GestureHashConfiguration()

    /// The key-derivation algorithm used to derive the credential hash.
    public let kdf: GestureKDF

    /// The PBKDF2 iteration count.
    public let iterations: Int

    /// The number of random salt bytes to generate for each credential.
    public let saltLength: Int

    /// The number of bytes produced by the key-derivation function.
    public let derivedKeyLength: Int

    /// The version marker stored with new credentials.
    public let hashVersion: Int

    /// Creates a credential hashing configuration.
    ///
    /// - Parameters:
    ///   - kdf: The key-derivation algorithm. Defaults to `.pbkdf2SHA256`.
    ///   - iterations: The PBKDF2 iteration count. Defaults to `600_000`.
    ///   - saltLength: The random salt length in bytes. Defaults to `32`.
    ///   - derivedKeyLength: The derived key length in bytes. Defaults to `32`.
    ///   - hashVersion: The credential hash version to write. Defaults to `1`.
    /// - Returns: A value describing how new gesture credentials should be
    ///   derived.
    /// - Throws: This initializer does not throw. Values are validated when a
    ///   credential is created.
    public init(
        kdf: GestureKDF = .pbkdf2SHA256,
        iterations: Int = 600_000,
        saltLength: Int = 32,
        derivedKeyLength: Int = 32,
        hashVersion: Int = 1
    ) {
        self.kdf = kdf
        self.iterations = iterations
        self.saltLength = saltLength
        self.derivedKeyLength = derivedKeyLength
        self.hashVersion = hashVersion
    }
}

/// A validated 3x3-grid gesture pattern.
public struct GesturePattern: Codable, Equatable, Hashable, Sendable {
    /// The ordered vertex indices selected by the user.
    ///
    /// Vertices are zero-based indices in a 3x3 grid and must be in the range
    /// `0...8`.
    public let vertices: [Int]

    /// Creates a validated gesture pattern.
    ///
    /// - Parameter vertices: Ordered 3x3 grid vertex indices in the range
    ///   `0...8`.
    /// - Returns: A validated gesture pattern ready for canonical encoding.
    /// - Throws: ``GestureCredentialError/emptyPattern`` when `vertices` is
    ///   empty, ``GestureCredentialError/patternTooLong(_:)`` when the pattern
    ///   is too long to encode, or ``GestureCredentialError/invalidVertex(_:)``
    ///   when any index is outside `0...8`.
    public init(_ vertices: [Int]) throws(GestureCredentialError) {
        guard !vertices.isEmpty else {
            throw .emptyPattern
        }
        guard vertices.count <= Int(UInt16.max) else {
            throw .patternTooLong(vertices.count)
        }
        for vertex in vertices where !(0 ... 8).contains(vertex) {
            throw .invalidVertex(vertex)
        }
        self.vertices = vertices
    }

    /// Stable v1 binary representation used as PBKDF2 input.
    ///
    /// - Returns: Canonical bytes containing a domain separator, the big-endian
    ///   vertex count, and the ordered vertex bytes.
    public var canonicalData: Data {
        var data = Data("PatternAuthentication.GesturePattern.v1".utf8)
        data.append(0)

        var count = UInt16(vertices.count).bigEndian
        withUnsafeBytes(of: &count) { bytes in
            data.append(contentsOf: bytes)
        }

        data.append(contentsOf: vertices.map { UInt8($0) })
        return data
    }
}

/// A salted, versioned gesture credential suitable for app-controlled storage.
public struct GestureCredentialEnvelope: Codable, Equatable, Hashable, Sendable {
    /// The random salt used when deriving ``hash``.
    public let salt: Data

    /// The derived credential hash.
    public let hash: Data

    /// The key-derivation algorithm used to create ``hash``.
    public let kdf: GestureKDF

    /// The iteration count used to create ``hash``.
    public let iterations: Int

    /// The version marker for this credential format.
    public let hashVersion: Int

    /// The expected byte length of ``hash``.
    public let derivedKeyLength: Int

    /// Creates a credential envelope from already-derived credential material.
    ///
    /// Use `GestureCredentialHasher.createCredential(for:configuration:)` for
    /// normal setup. This initializer is intended for decoding, tests, and
    /// backend-provided credential material.
    ///
    /// - Parameters:
    ///   - salt: The salt bytes stored with the credential.
    ///   - hash: The derived credential hash bytes.
    ///   - kdf: The key-derivation algorithm used for `hash`. No default.
    ///   - iterations: The iteration count used for `hash`. No default.
    ///   - hashVersion: The credential version. No default.
    ///   - derivedKeyLength: The expected `hash` byte count. No default.
    /// - Returns: A credential envelope containing the supplied material.
    /// - Throws: This initializer does not throw. Credential metadata is
    ///   validated by verification APIs.
    public init(
        salt: Data,
        hash: Data,
        kdf: GestureKDF,
        iterations: Int,
        hashVersion: Int,
        derivedKeyLength: Int
    ) {
        self.salt = salt
        self.hash = hash
        self.kdf = kdf
        self.iterations = iterations
        self.hashVersion = hashVersion
        self.derivedKeyLength = derivedKeyLength
    }

    /// A storage-friendly representation for systems that prefer base64 strings.
    public struct Base64Representation: Codable, Equatable, Hashable, Sendable {
        /// The base64-encoded salt bytes.
        public let salt: String

        /// The base64-encoded derived hash bytes.
        public let hash: String

        /// The key-derivation algorithm used to create ``hash``.
        public let kdf: GestureKDF

        /// The iteration count used to create ``hash``.
        public let iterations: Int

        /// The credential version marker.
        public let hashVersion: Int

        /// The expected decoded byte count of ``hash``.
        public let derivedKeyLength: Int

        /// Creates a base64 credential representation.
        ///
        /// - Parameters:
        ///   - salt: Base64-encoded salt bytes. No default.
        ///   - hash: Base64-encoded derived hash bytes. No default.
        ///   - kdf: The key-derivation algorithm used for `hash`. No default.
        ///   - iterations: The iteration count used for `hash`. No default.
        ///   - hashVersion: The credential version. No default.
        ///   - derivedKeyLength: The expected decoded `hash` byte count. No
        ///     default.
        /// - Returns: A storage-friendly credential representation.
        /// - Throws: This initializer does not throw. Base64 strings are decoded
        ///   by ``GestureCredentialEnvelope/init(base64Representation:)``.
        public init(
            salt: String,
            hash: String,
            kdf: GestureKDF,
            iterations: Int,
            hashVersion: Int,
            derivedKeyLength: Int
        ) {
            self.salt = salt
            self.hash = hash
            self.kdf = kdf
            self.iterations = iterations
            self.hashVersion = hashVersion
            self.derivedKeyLength = derivedKeyLength
        }
    }

    /// The envelope as base64 strings for JSON-friendly storage.
    ///
    /// - Returns: A representation with base64-encoded `salt` and `hash`
    ///   fields and unchanged credential metadata.
    public var base64Representation: Base64Representation {
        Base64Representation(
            salt: salt.base64EncodedString(),
            hash: hash.base64EncodedString(),
            kdf: kdf,
            iterations: iterations,
            hashVersion: hashVersion,
            derivedKeyLength: derivedKeyLength
        )
    }

    /// Creates a credential envelope from a base64 representation.
    ///
    /// - Parameter base64Representation: The representation containing
    ///   base64-encoded `salt` and `hash` fields.
    /// - Returns: A credential envelope with decoded binary salt and hash data.
    /// - Throws: ``GestureCredentialError/invalidBase64(field:)`` when either
    ///   `salt` or `hash` is not valid base64.
    public init(base64Representation: Base64Representation) throws(GestureCredentialError) {
        guard let salt = Data(base64Encoded: base64Representation.salt) else {
            throw .invalidBase64(field: "salt")
        }
        guard let hash = Data(base64Encoded: base64Representation.hash) else {
            throw .invalidBase64(field: "hash")
        }
        self.init(
            salt: salt,
            hash: hash,
            kdf: base64Representation.kdf,
            iterations: base64Representation.iterations,
            hashVersion: base64Representation.hashVersion,
            derivedKeyLength: base64Representation.derivedKeyLength
        )
    }

    /// Encodes the base64 representation as JSON for local storage or transport.
    ///
    /// - Parameter encoder: The JSON encoder used to encode the base64
    ///   representation. Defaults to `JSONEncoder()`.
    /// - Returns: JSON bytes containing the base64 representation.
    /// - Throws: Any error thrown by `encoder`.
    public func jsonData(encoder: JSONEncoder = JSONEncoder()) throws -> Data {
        try encoder.encode(base64Representation)
    }

    /// Decodes an envelope from JSON produced by ``jsonData(encoder:)``.
    ///
    /// - Parameters:
    ///   - data: JSON bytes containing a ``Base64Representation``.
    ///   - decoder: The JSON decoder used to decode `data`. Defaults to
    ///     `JSONDecoder()`.
    /// - Returns: A credential envelope decoded from the JSON payload.
    /// - Throws: Any error thrown by `decoder`, or
    ///   ``GestureCredentialError/invalidBase64(field:)`` when the decoded
    ///   representation contains invalid base64.
    public static func fromJSONData(
        _ data: Data,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> GestureCredentialEnvelope {
        let representation = try decoder.decode(Base64Representation.self, from: data)
        return try GestureCredentialEnvelope(base64Representation: representation)
    }
}

/// Creates and verifies gesture credential envelopes.
public enum GestureCredentialHasher {
    /// Creates a salted v1 credential for a raw vertex array.
    ///
    /// - Parameters:
    ///   - vertices: Ordered 3x3 grid vertex indices in the range `0...8`.
    ///   - configuration: The hashing configuration to use. Defaults to
    ///     ``GestureHashConfiguration/recommended``.
    /// - Returns: A new credential envelope with a fresh random salt.
    /// - Throws: A ``GestureCredentialError`` when the pattern or configuration
    ///   is invalid, random salt generation fails, or PBKDF2 derivation fails.
    public static func createCredential(
        for vertices: [Int],
        configuration: GestureHashConfiguration = .recommended
    ) throws(GestureCredentialError) -> GestureCredentialEnvelope {
        let pattern = try GesturePattern(vertices)
        return try createCredential(for: pattern, configuration: configuration)
    }

    /// Creates a salted v1 credential for a validated gesture pattern.
    ///
    /// - Parameters:
    ///   - pattern: The validated gesture pattern to encode and hash.
    ///   - configuration: The hashing configuration to use. Defaults to
    ///     ``GestureHashConfiguration/recommended``.
    /// - Returns: A new credential envelope with a fresh random salt.
    /// - Throws: A ``GestureCredentialError`` when the configuration is invalid,
    ///   random salt generation fails, or PBKDF2 derivation fails.
    public static func createCredential(
        for pattern: GesturePattern,
        configuration: GestureHashConfiguration = .recommended
    ) throws(GestureCredentialError) -> GestureCredentialEnvelope {
        try validate(configuration: configuration)
        let salt = try secureRandomData(count: configuration.saltLength)
        let hash = try deriveKey(
            password: pattern.canonicalData,
            salt: salt,
            kdf: configuration.kdf,
            iterations: configuration.iterations,
            derivedKeyLength: configuration.derivedKeyLength
        )
        return GestureCredentialEnvelope(
            salt: salt,
            hash: hash,
            kdf: configuration.kdf,
            iterations: configuration.iterations,
            hashVersion: configuration.hashVersion,
            derivedKeyLength: configuration.derivedKeyLength
        )
    }

    /// Verifies a raw vertex array against a stored credential envelope.
    ///
    /// - Parameters:
    ///   - vertices: Ordered 3x3 grid vertex indices in the range `0...8`.
    ///   - credential: The stored credential envelope fetched by the app.
    /// - Returns: `true` when `vertices` derive the stored credential hash;
    ///   otherwise, `false`.
    /// - Throws: A ``GestureCredentialError`` when the pattern or credential
    ///   metadata is invalid, or PBKDF2 derivation fails.
    public static func verify(
        vertices: [Int],
        against credential: GestureCredentialEnvelope
    ) throws(GestureCredentialError) -> Bool {
        let pattern = try GesturePattern(vertices)
        return try verify(pattern, against: credential)
    }

    /// Verifies a validated gesture pattern against a stored credential envelope.
    ///
    /// - Parameters:
    ///   - pattern: The validated gesture pattern to verify.
    ///   - credential: The stored credential envelope fetched by the app.
    /// - Returns: `true` when `pattern` derives the stored credential hash;
    ///   otherwise, `false`.
    /// - Throws: A ``GestureCredentialError`` when the credential metadata is
    ///   invalid or PBKDF2 derivation fails.
    public static func verify(
        _ pattern: GesturePattern,
        against credential: GestureCredentialEnvelope
    ) throws(GestureCredentialError) -> Bool {
        try validate(credential: credential)
        let derivedHash = try deriveKey(
            password: pattern.canonicalData,
            salt: credential.salt,
            kdf: credential.kdf,
            iterations: credential.iterations,
            derivedKeyLength: credential.derivedKeyLength
        )
        return constantTimeEquals(derivedHash, credential.hash)
    }

    /// Verifies the package's original SHA-256 string hash format.
    ///
    /// - Parameters:
    ///   - vertices: Ordered 3x3 grid vertex indices to hash using the legacy
    ///     algorithm.
    ///   - expectedHash: The legacy hexadecimal SHA-256 hash string to compare
    ///     against.
    /// - Returns: `true` when the legacy hash of `vertices` matches
    ///   `expectedHash`; otherwise, `false`.
    /// - Throws: This method does not throw.
    public static func verifyLegacySHA256(vertices: [Int], expectedHash: String) -> Bool {
        let expectedHashBytes = expectedHash.utf8
        guard expectedHashBytes.count == 64,
              expectedHashBytes.allSatisfy({ byte in
                  (48 ... 57).contains(byte)
                      || (65 ... 70).contains(byte)
                      || (97 ... 102).contains(byte)
              })
        else { return false }

        let actualHash = legacyHashArray(vertices)
        return constantTimeEquals(Data(actualHash.utf8), Data(expectedHash.lowercased().utf8))
    }

    /// Creates a v1 envelope after a successful legacy SHA-256 verification.
    ///
    /// - Parameters:
    ///   - vertices: Ordered 3x3 grid vertex indices to verify and migrate.
    ///   - expectedHash: The existing legacy hexadecimal SHA-256 hash string.
    ///   - configuration: The hashing configuration for the new v1 credential.
    ///     Defaults to ``GestureHashConfiguration/recommended``.
    /// - Returns: A new v1 credential envelope when legacy verification
    ///   succeeds, or `nil` when the legacy hash does not match.
    /// - Throws: A ``GestureCredentialError`` when the new credential cannot be
    ///   created.
    public static func upgradeLegacyCredential(
        vertices: [Int],
        expectedHash: String,
        configuration: GestureHashConfiguration = .recommended
    ) throws(GestureCredentialError) -> GestureCredentialEnvelope? {
        guard verifyLegacySHA256(vertices: vertices, expectedHash: expectedHash) else {
            return nil
        }
        return try createCredential(for: vertices, configuration: configuration)
    }

    /// Compares two byte buffers in constant time with respect to content.
    ///
    /// The loop always examines the length of the longer input and folds the
    /// length difference into the result.
    ///
    /// - Parameters:
    ///   - lhs: The first byte buffer.
    ///   - rhs: The second byte buffer.
    /// - Returns: `true` when both buffers have the same bytes and length;
    ///   otherwise, `false`.
    /// - Throws: This method does not throw.
    public static func constantTimeEquals(_ lhs: Data, _ rhs: Data) -> Bool {
        let lhsBytes = [UInt8](lhs)
        let rhsBytes = [UInt8](rhs)
        let maxCount = max(lhsBytes.count, rhsBytes.count)
        var difference = lhsBytes.count ^ rhsBytes.count

        for index in 0 ..< maxCount {
            let left = index < lhsBytes.count ? lhsBytes[index] : 0
            let right = index < rhsBytes.count ? rhsBytes[index] : 0
            difference |= Int(left ^ right)
        }

        return difference == 0
    }

    /// Derives a key using the supplied key-derivation metadata.
    ///
    /// - Parameters:
    ///   - password: The canonical gesture bytes used as the PBKDF2 password.
    ///   - salt: The salt bytes used by PBKDF2.
    ///   - kdf: The key-derivation algorithm. No default.
    ///   - iterations: The PBKDF2 iteration count. No default.
    ///   - derivedKeyLength: The number of bytes to derive. No default.
    /// - Returns: The derived key bytes.
    /// - Throws: ``GestureCredentialError/invalidIterationCount(_:)`` when
    ///   `iterations` is not positive,
    ///   ``GestureCredentialError/invalidDerivedKeyLength(_:)`` when
    ///   `derivedKeyLength` is not positive,
    ///   ``GestureCredentialError/unsupportedKDF(_:)`` when `kdf` is not
    ///   supported, or ``GestureCredentialError/derivationFailed(_:)`` when
    ///   CommonCrypto fails.
    static func deriveKey(
        password: Data,
        salt: Data,
        kdf: GestureKDF,
        iterations: Int,
        derivedKeyLength: Int
    ) throws(GestureCredentialError) -> Data {
guard iterations > 0, iterations <= Int(UInt32.max) else {
    throw .invalidIterationCount(iterations)
}
        guard derivedKeyLength > 0 else {
            throw .invalidDerivedKeyLength(derivedKeyLength)
        }
        guard kdf == .pbkdf2SHA256 else {
            throw .unsupportedKDF(kdf)
        }

        var derivedKey = Data(repeating: 0, count: derivedKeyLength)
        let status = password.withUnsafeBytes { passwordBytes in
            salt.withUnsafeBytes { saltBytes in
                derivedKey.withUnsafeMutableBytes { derivedKeyBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.bindMemory(to: Int8.self).baseAddress,
                        password.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        derivedKeyBytes.bindMemory(to: UInt8.self).baseAddress,
                        derivedKeyLength
                    )
                }
            }
        }

        guard status == kCCSuccess else {
            throw .derivationFailed(status)
        }
        return derivedKey
    }

    /// Validates a credential creation configuration.
    ///
    /// - Parameter configuration: The configuration to validate.
    /// If validation succeeds, this method returns normally without producing a
    /// value.
    /// - Throws: A ``GestureCredentialError`` when iteration count, salt length,
    ///   derived key length, or hash version is outside the supported range.
    private static func validate(
        configuration: GestureHashConfiguration
    ) throws(GestureCredentialError) {
        guard configuration.iterations > 0 else {
            throw .invalidIterationCount(configuration.iterations)
        }
        guard (16 ... 64).contains(configuration.saltLength) else {
            throw .invalidSaltLength(configuration.saltLength)
        }
        guard (16 ... 64).contains(configuration.derivedKeyLength) else {
            throw .invalidDerivedKeyLength(configuration.derivedKeyLength)
        }
        guard configuration.hashVersion > 0 else {
            throw .invalidHashVersion(configuration.hashVersion)
        }
    }

    /// Validates a stored credential envelope before verification.
    ///
    /// - Parameter credential: The credential envelope to validate.
    /// If validation succeeds, this method returns normally without producing a
    /// value.
    /// - Throws: A ``GestureCredentialError`` when iteration count, salt length,
    ///   derived key length, hash byte count, or hash version is invalid.
    private static func validate(
        credential: GestureCredentialEnvelope
    ) throws(GestureCredentialError) {
        guard credential.iterations > 0 else {
            throw .invalidIterationCount(credential.iterations)
        }
        guard (16 ... 64).contains(credential.salt.count) else {
            throw .invalidSaltLength(credential.salt.count)
        }
        guard (16 ... 64).contains(credential.derivedKeyLength) else {
            throw .invalidDerivedKeyLength(credential.derivedKeyLength)
        }
        guard credential.hash.count == credential.derivedKeyLength else {
            throw .hashLengthMismatch(
                expected: credential.derivedKeyLength,
                actual: credential.hash.count
            )
        }
        guard credential.hashVersion > 0 else {
            throw .invalidHashVersion(credential.hashVersion)
        }
    }

    /// Generates cryptographically secure random bytes.
    ///
    /// - Parameter count: The number of random bytes to generate.
    /// - Returns: A `Data` value containing `count` bytes.
    /// - Throws: ``GestureCredentialError/secureRandomFailed(_:)`` when
    ///   Security framework random generation fails.
    private static func secureRandomData(count: Int) throws(GestureCredentialError) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw .secureRandomFailed(status)
        }
        return Data(bytes)
    }
}
