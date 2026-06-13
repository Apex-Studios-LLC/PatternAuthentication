# PatternAuthentication

Build a SwiftUI 3x3 gesture-pattern setup and authentication flow with salted v1 credentials.

## Overview

Pattern Authentication provides the client-side UI and credential helpers for gesture-pattern authentication. The package creates and verifies `GestureCredentialEnvelope` values, while your app remains responsible for fetching, storing, and protecting those credentials.

Use `GridAuthenticator` with `setCredential` for new setup:

```swift
GridAuthenticator(.setCredential { credential in
    Task {
        try await saveCredential(credential.base64Representation)
    }
})
```

Use `authenticateCredential` after your app fetches a stored envelope:

```swift
GridAuthenticator(.authenticateCredential(credential: credential) { success in
    if success {
        openAuthenticatedArea()
    }
})
```

## Topics

### SwiftUI

- ``GridAuthenticator``
- ``GridAuthenticatorViewModel``
- ``GridAuthenticatorViewModel/GridAuthenticatorOption``

### Credentials

- ``GestureCredentialEnvelope``
- ``GestureCredentialHasher``
- ``GestureHashConfiguration``
- ``GesturePattern``
- ``GestureKDF``
- ``GestureCredentialError``

### Compatibility

- ``hashArray(_:)``
