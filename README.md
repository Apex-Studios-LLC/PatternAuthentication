[![Swift versions](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FApex-Studios-LLC%2FPatternAuthentication%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/Apex-Studios-LLC/PatternAuthentication)
[![Platforms](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FApex-Studios-LLC%2FPatternAuthentication%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/Apex-Studios-LLC/PatternAuthentication)
[![CI](https://github.com/Apex-Studios-LLC/PatternAuthentication/actions/workflows/ci.yml/badge.svg?branch=dev)](https://github.com/Apex-Studios-LLC/PatternAuthentication/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/Apex-Studios-LLC/PatternAuthentication/branch/dev/graph/badge.svg)](https://codecov.io/gh/Apex-Studios-LLC/PatternAuthentication)

# Pattern Authentication

Pattern Authentication gives iOS apps a polished 3x3 gesture-pattern setup and authentication flow. Multi-user apps can use it for profile switching, household access, or secondary checks without asking each user for a password on each handoff.

The package owns the client-side gesture UI, canonical pattern encoding, salted credential creation, credential verification, legacy migration helpers, and particle-path feedback.

Your app owns the backend, account model, lockout policy, session creation, and authorization checks. Fetch stored credentials, save new credentials, enforce attempt limits, and grant access after a successful gesture match in your app or service.

[Demo video](Images/PatternAuthenticationDemo.mp4)

## Requirements

- iOS 15.0+
- Swift 6.0+
- Xcode 16+ or a Swift 6-compatible toolchain

## Install

Add the package in Xcode:

```text
https://github.com/Apex-Studios-LLC/PatternAuthentication.git
```

Or add it to a `Package.swift` manifest:

```swift
.package(
    url: "https://github.com/Apex-Studios-LLC/PatternAuthentication.git",
    from: "1.1.0"
)
```

Then add `PatternAuthentication` to your app target.

```swift
.target(
    name: "YourApp",
    dependencies: ["PatternAuthentication"]
)
```

## Quick Start

Import the package anywhere you present the gesture UI.

```swift
import PatternAuthentication
import SwiftUI
```

Create a new v1 credential during setup:

```swift
struct GestureSetupView: View {
    let userID: String
    let saveCredential: (String, GestureCredentialEnvelope) async throws -> Void

    @State private var status = ""

    var body: some View {
        GridAuthenticator(.setCredential(
            minimumVertices: 6,
            color: .green,
            interactionMode: .drag,
            requireConfirmation: true,
            repeatInput: true,
            debug: false
        ) { credential in
            Task {
                do {
                    try await saveCredential(userID, credential)
                    status = "Pattern saved"
                } catch {
                    status = "Could not save pattern"
                }
            }
        })
    }
}
```

Authenticate against a credential your app fetched from storage:

```swift
struct GestureLoginView: View {
    let credential: GestureCredentialEnvelope
    let onAuthenticated: () -> Void

    @State private var failed = false

    var body: some View {
        GridAuthenticator(.authenticateCredential(
            credential: credential,
            color: .blue,
            interactionMode: .drag,
            debug: false
        ) { success in
            if success {
                onAuthenticated()
            } else {
                failed = true
            }
        })
    }
}
```

## Credential Flow

The v1 API returns a `GestureCredentialEnvelope`:

```swift
public struct GestureCredentialEnvelope: Codable, Hashable, Sendable {
    public let salt: Data
    public let hash: Data
    public let kdf: GestureKDF
    public let iterations: Int
    public let hashVersion: Int
    public let derivedKeyLength: Int
}
```

For JSON or document databases, use the base64 representation:

```swift
let representation = credential.base64Representation

let payload: [String: Any] = [
    "salt": representation.salt,
    "hash": representation.hash,
    "kdf": representation.kdf.rawValue,
    "iterations": representation.iterations,
    "hashVersion": representation.hashVersion,
    "derivedKeyLength": representation.derivedKeyLength
]
```

To rebuild the envelope after fetching it:

```swift
let representation = GestureCredentialEnvelope.Base64Representation(
    salt: storedSalt,
    hash: storedHash,
    kdf: .pbkdf2SHA256,
    iterations: storedIterations,
    hashVersion: storedHashVersion,
    derivedKeyLength: storedDerivedKeyLength
)

let credential = try GestureCredentialEnvelope(
    base64Representation: representation
)
```

You can also encode and decode JSON directly:

```swift
let data = try credential.jsonData()
let decoded = try GestureCredentialEnvelope.fromJSONData(data)
```

## Backend Responsibilities

Store the envelope fields with the user or profile record your app controls. A Firestore-style document might look like this:

```json
{
  "gestureCredential": {
    "salt": "base64 salt",
    "hash": "base64 hash",
    "kdf": "pbkdf2-sha256",
    "iterations": 600000,
    "hashVersion": 1,
    "derivedKeyLength": 32,
    "updatedAt": "server timestamp"
  }
}
```

Your app or backend should also own:

- Fetching the envelope before presenting `GridAuthenticator(.authenticateCredential(...))`.
- Saving the envelope returned by `GridAuthenticator(.setCredential(...))`.
- Enforcing lockouts, rate limits, re-authentication windows, and audit logging.
- Deciding what a successful gesture unlocks.
- Protecting reads and writes with your normal account authorization rules.
- Migrating legacy hashes only after a successful legacy gesture match.

Attackers can read a salt without gaining the gesture. Treat the full credential record as sensitive authenticator material: restrict reads, use TLS, avoid logging it, and expose it only to clients authorized to authenticate that account.

## Legacy Migration

The original package API returned a single unsalted SHA-256 string. The 1.x line keeps those APIs source-compatible and marks them deprecated:

```swift
GridAuthenticator(.set { legacyHash in
    // Deprecated: store only while migrating old installations.
})

GridAuthenticator(.authenticate(expectedHash: legacyHash) { success in
    // Deprecated: prefer authenticateCredential(credential:).
})
```

For production apps that already have legacy hashes, use `authenticateAndUpgrade`. It verifies the old hash first, then gives your app a v1 envelope to save.

```swift
GridAuthenticator(.authenticateAndUpgrade(
    expectedHash: legacyHash,
    configuration: .recommended,
    onCredentialUpgrade: { credential in
        Task {
            try await saveCredential(userID, credential)
            try await deleteLegacyHash(userID)
        }
    },
    completion: { success in
        if success {
            openUserWorkspace()
        }
    }
))
```

This upgrade callback only fires after a successful legacy match. If saving the new credential fails, keep the legacy hash and retry migration on a later successful login.

## Security Model

The v1 credential format uses:

- Canonical gesture encoding with a package-specific domain separator.
- A fresh cryptographically secure random salt per credential.
- PBKDF2-HMAC-SHA256 with 600,000 iterations by default.
- 32-byte salts and 32-byte derived hashes by default.
- Constant-time comparison for hash verification.
- `Codable`, base64, and JSON helpers for app-controlled storage.

Gesture patterns have limited entropy compared with passwords or passkeys. Use this package for local app re-authentication, profile switching, child or household user gates, or lightweight secondary checks. Do not use a pattern gesture as your only account security boundary for high-value accounts. Pair it with your app's normal signed-in session, backend authorization, attempt limits, and recovery flow.

Argon2id would add memory-hard offline attack resistance. v1 uses PBKDF2-HMAC-SHA256 because Apple platforms provide it without a native dependency, which keeps SwiftPM integration simple.

## Configuration

`setCredential` uses these defaults:

| Parameter | Default | Notes |
| --- | --- | --- |
| `minimumVertices` | `6` | Rejects short setup gestures. |
| `color` | `.blue` | Drives circles, glow, and particles. |
| `interactionMode` | `.drag` | Drag input is the supported production path. |
| `requireConfirmation` | `true` | Requires the user to repeat a setup pattern. |
| `repeatInput` | `true` | Replays the entered pattern by default. |
| `debug` | `false` | Shows safe diagnostics without printing raw hashes. |
| `configuration` | `.recommended` | PBKDF2-HMAC-SHA256, 600,000 iterations. |

`InteractionMode.tap` remains for source compatibility and future UI work. Use `.drag` for production flows.

## Troubleshooting

If the particle trail appears offset, check whether a wrapper view overrides the `"GridSpace"` coordinate space. The package draws particles from grid-local geometry captured through SwiftUI preferences.

If the particle trail appears dotted after direct customization, keep `ParticleSystem.emissionSpacing` lower than `ParticleSystem.particleDiameter`. The defaults interpolate fast drag movement and draw fingertip-sized particles so normal swipes read as a continuous trail.

If authentication always fails, confirm that you are passing the exact fetched `GestureCredentialEnvelope` back into `.authenticateCredential`. Salt, hash, KDF, iteration count, hash version, and derived key length must all match the stored record.

If migration does not save a v1 credential, check your `onCredentialUpgrade` callback. The package creates the envelope after a successful legacy match; your app writes it to storage.

If CI coverage fails, run the same command locally:

```bash
xcodebuild test \
  -scheme PatternAuthentication \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -enableCodeCoverage YES \
  -resultBundlePath TestResults.xcresult \
  SWIFT_VERSION=6 \
  SWIFT_STRICT_CONCURRENCY=complete

xcrun xccov view --report --json TestResults.xcresult > coverage.json
python3 Scripts/check_coverage.py coverage.json \
  --threshold 90 \
  --ignore Sources/PatternAuthentication/PatternAuthentication.swift
```

## Versioning

The security credential upgrade adds APIs in 1.x. Deprecated legacy APIs stay available so existing apps can migrate without a breaking release. A future 2.0 release may remove legacy SHA-256 setup/authentication APIs and revisit reserved interaction modes.

See [CHANGELOG.md](CHANGELOG.md) for the full `1.1.0` release notes. See [Docs/MigrationGuide.md](Docs/MigrationGuide.md) and [SECURITY.md](SECURITY.md) for migration and operating guidance.

## License

Pattern Authentication uses the MIT license. See [LICENSE](LICENSE).
