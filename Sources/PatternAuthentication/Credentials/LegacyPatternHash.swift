import CryptoKit
import Foundation

/// Returns the original package SHA-256 hash for a pattern.
///
/// This format is retained only for backwards compatibility with existing
/// stored hashes. New integrations should use ``GestureCredentialEnvelope``.
///
/// - Parameter array: Ordered 3x3 grid vertex indices.
/// - Returns: A lowercase hexadecimal SHA-256 hash of the legacy in-memory
///   integer-array bytes.
/// - Throws: This function does not throw.
@available(*, deprecated, message: "Use GestureCredentialHasher.createCredential(for:) instead.")
public func hashArray(_ array: [Int]) -> String {
    legacyHashArray(array)
}

/// Computes the package's original SHA-256 pattern hash.
///
/// - Parameter array: Ordered 3x3 grid vertex indices.
/// - Returns: A lowercase hexadecimal SHA-256 hash matching v0 package output.
/// - Throws: This function does not throw.
func legacyHashArray(_ array: [Int]) -> String {
    let data = array.withUnsafeBytes { Data($0) }
    let hash = SHA256.hash(data: data)
    return hash.compactMap { String(format: "%02x", $0) }.joined()
}
