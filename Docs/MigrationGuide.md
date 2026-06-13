# Migration Guide

This guide covers migration from the original unsalted SHA-256 API to the v1 credential envelope API.

## What changed

The original API returned a single string from setup and accepted that string during authentication:

```swift
GridAuthenticator(.set { hash in
    saveLegacyHash(hash)
})

GridAuthenticator(.authenticate(expectedHash: legacyHash) { success in
    handleResult(success)
})
```

The v1 API returns a `GestureCredentialEnvelope` containing the salt, derived hash, KDF, iteration count, hash version, and derived key length:

```swift
GridAuthenticator(.setCredential { credential in
    saveCredential(credential)
})

GridAuthenticator(.authenticateCredential(credential: credential) { success in
    handleResult(success)
})
```

## New installs

Use `setCredential` for setup and store the envelope's base64 representation in your backend or local secure storage.

```swift
GridAuthenticator(.setCredential(
    minimumVertices: 6,
    requireConfirmation: true,
    repeatInput: true
) { credential in
    Task {
        try await saveCredential(credential.base64Representation)
    }
})
```

## Existing installs

For users who already have a legacy hash, authenticate once with `authenticateAndUpgrade`.

```swift
GridAuthenticator(.authenticateAndUpgrade(
    expectedHash: legacyHash,
    onCredentialUpgrade: { credential in
        Task {
            try await saveCredential(credential.base64Representation)
            try await removeLegacyHash()
        }
    },
    completion: { success in
        handleResult(success)
    }
))
```

Only remove the legacy hash after the v1 credential write succeeds. If the write fails, keep the legacy hash and retry on a later successful login.

## Backwards compatibility

The legacy APIs remain available for 1.x and are marked deprecated. This lets production apps migrate users gradually without a forced data conversion.

Two behavior fixes are worth testing in your app:

- Failed authentication calls the completion with `false`.
- Setup without confirmation now completes immediately after a valid gesture.

## Backend checklist

- Store all envelope fields: `salt`, `hash`, `kdf`, `iterations`, `hashVersion`, and `derivedKeyLength`.
- Store `salt` and `hash` as base64 strings if your database cannot store binary data cleanly.
- Protect credential reads and writes with your normal account authorization rules.
- Do not log raw credentials or legacy hashes.
- Keep lockout, rate limiting, session creation, and authorization checks outside the package.
