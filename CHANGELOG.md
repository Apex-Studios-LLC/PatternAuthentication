# Changelog

This project follows semantic versioning. Major releases handle public API removals when possible.

## Unreleased

- No unreleased changes yet.

## 1.1.0 - 2026-06-12

The security credential upgrade release keeps the original 1.x gesture UI APIs available for existing apps and adds the v1 credential-envelope flow for production use.

### Added

- Added the v1 `GestureCredentialEnvelope` API for storing gesture credentials as a structured envelope rather than a single legacy hash string.
- Added `GesturePattern` to canonicalize selected grid indices before hashing, including a package-specific domain separator so the encoded gesture carries package and version context.
- Added `GestureHashConfiguration` for KDF parameters, with `.recommended` using PBKDF2-HMAC-SHA256, 600,000 iterations, a 32-byte salt, and a 32-byte derived key.
- Added `GestureKDF` so stored credentials can record the derivation algorithm used to create them.
- Added `GestureCredentialError` for typed failures around salt generation, hashing, unsupported credential versions, malformed base64, malformed JSON, and invalid KDF metadata.
- Added cryptographically secure random salt generation through Security framework APIs.
- Added constant-time comparison for derived hash verification.
- Added `Codable`, JSON, and base64 helpers for backend-friendly storage in document databases and APIs.
- Added `GridAuthenticator(.setCredential(...))` for new credential setup.
- Added `GridAuthenticator(.authenticateCredential(...))` for authenticating against a fetched v1 credential.
- Added `GridAuthenticator(.authenticateAndUpgrade(...))` for verifying a legacy v0 hash and returning a v1 credential envelope after a successful match.
- Added Swift 6 language mode in `Package.swift`.
- Added `Sendable` conformance for credential model types that can safely cross concurrency boundaries.
- Added main-actor isolation for UI-owned state.
- Added package tests for canonical gesture encoding, PBKDF2-HMAC-SHA256 known vectors, salt uniqueness, v1 credential verification, Codable round trips, base64 round trips, legacy verification, legacy-to-v1 migration, particle resource loading, and replay path behavior.
- Added GitHub Actions CI for Swift 6 builds, tests, coverage extraction, and a 90% package-logic coverage gate.
- Added Codecov configuration, LCOV conversion for Swift/Xcode coverage upload, and README badges for CI and coverage.
- Added a DocC catalog for package documentation.
- Added public API DocC comments for the non-view public types and methods.
- Added `Docs/MigrationGuide.md` for legacy SHA-256 migration.
- Added `SECURITY.md` with storage, lockout, session, and vulnerability-reporting guidance.

### Changed

- Reworked the README into a production integration guide with quickstart setup/authentication examples, backend responsibilities, Firestore-style storage guidance, security model notes, configuration defaults, troubleshooting, and versioning.
- Updated the package security model from unsalted SHA-256-only storage to a salted credential envelope while preserving source compatibility for existing 1.x clients.
- Updated setup and authentication examples to show app-owned backend fetch/save behavior.
- Updated particle rendering so the particle canvas, drag hit testing, and circle geometry all use the same grid-local coordinate space.
- Updated particle trails to interpolate fast drag movement and render at a fingertip-like thickness, reducing dotted gaps during quick swipes.
- Preserved the original particle-only visual style rather than switching to a deterministic path overlay.
- Updated SwiftUI layout so the grid itself defines the interactive drawing surface, avoiding full-screen coordinate drift in package consumers.
- Updated debug behavior so raw gesture hashes are no longer printed.
- Updated setup without confirmation so it completes after the first valid gesture while still honoring the default `repeatInput: true` replay.
- Updated failed authentication behavior so the completion handler is called with `false`.
- Updated the mutable static preference default to be Swift 6 concurrency friendly.

### Deprecated

- Deprecated `hashArray(_:)`. Use `GestureCredentialEnvelope.create(from:configuration:)` or the new `GridAuthenticator(.setCredential(...))` flow instead.
- Deprecated `GridAuthenticator(.set(... completion: (String) -> Void))`. Use `GridAuthenticator(.setCredential(...))` for new setup flows.
- Deprecated `GridAuthenticator(.authenticate(expectedHash: ...))`. Use `GridAuthenticator(.authenticateCredential(...))` once a v1 envelope is stored.

### Fixed

- Fixed particle trails that could appear vertically offset from the selected circles in SwiftPM consumers.
- Fixed particle trails that could look like a dotted line during fast finger movement.
- Fixed replay cleanup so a previous path does not bleed into the next setup or authentication attempt.
- Fixed SwiftPM resource loading coverage for the `spark` asset bundle.
- Fixed failed authentication callbacks so integrators can reliably update UI after an incorrect pattern.

### Security

- New v1 credentials use a fresh per-credential salt and PBKDF2-HMAC-SHA256 rather than a raw unsalted gesture hash.
- Verification derives a candidate hash with the stored credential parameters and compares it in constant time.
- Credential metadata records KDF, iteration count, hash version, and derived key length so future migrations have enough context.
- Legacy SHA-256 APIs remain only for compatibility and migration. New production integrations should use v1 credentials.
- Apps remain responsible for backend storage, authorization, sessions, lockouts, attempt limits, audit logging, recovery, and deciding what a successful gesture unlocks.

### Backwards Compatibility

- This release adds APIs in 1.x.
- Existing calls to `GridAuthenticator(.set(... completion: (String) -> Void))`, `GridAuthenticator(.authenticate(expectedHash: ...))`, and `hashArray(_:)` should continue to compile with deprecation warnings.
- Existing stored legacy hashes can still be verified.
- Existing production apps can migrate one user at a time with `authenticateAndUpgrade` after a successful legacy match.
- `repeatInput` remains `true` by default.
- Apps that exhaustively switch over package enums may need to recompile and handle newer cases.
- Apps that depended on raw debug hash output should remove that dependency.

### Migration Notes

- For new users, store `GestureCredentialEnvelope.Base64Representation` fields in your app-owned backend or local secure storage.
- For existing users, keep the legacy hash until `authenticateAndUpgrade` succeeds and your app has saved the returned v1 credential.
- Do not delete a legacy hash if saving the new envelope fails.
- Store all v1 fields together: `salt`, `hash`, `kdf`, `iterations`, `hashVersion`, and `derivedKeyLength`.
- Treat the credential record as sensitive authenticator material.

### Testing

- Verified Swift 6 package builds for iOS.
- Added a focused package test suite covering credential creation, verification, migration, encoding, resources, and particle behavior.
- Added CI coverage enforcement at 90% or higher for package logic.
- Verified the updated package through the sibling `PatternAuthTest` app on a physical iPhone.

### Known Non-Goals

- Argon2id remains a candidate for memory-hard offline attack resistance. v1 uses PBKDF2-HMAC-SHA256 to keep the package dependency-free and SwiftPM-friendly.
