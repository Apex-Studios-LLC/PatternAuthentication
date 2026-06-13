# Security Notes

Pattern Authentication handles the client-side gesture UI and credential derivation/verification. Apps integrating the package remain responsible for backend storage, user identity, sessions, lockout policy, authorization, and audit logging.

## Supported credential format

The v1 credential format uses:

- Canonical gesture encoding with a package domain separator.
- A fresh secure-random salt for each credential.
- PBKDF2-HMAC-SHA256 with 600,000 iterations by default.
- 32-byte salts and 32-byte derived hashes by default.
- Constant-time hash comparison.

## Storage guidance

Store these fields together:

- `salt`: base64-encoded salt bytes.
- `hash`: base64-encoded derived hash bytes.
- `kdf`: currently `pbkdf2-sha256`.
- `iterations`: currently `600000` by default.
- `hashVersion`: currently `1`.
- `derivedKeyLength`: currently `32` by default.

The salt is not secret, but the credential record is sensitive. Restrict reads and writes, use TLS, and avoid logging credential material.

## Operational guidance

- Use gesture authentication as a local or secondary gate, not as the only proof of account ownership for high-value data.
- Enforce attempt limits and cool-downs in your app or backend.
- Create sessions and authorize data access through your normal backend checks after a successful gesture match.
- Provide a recovery flow for forgotten gestures.
- Migrate legacy SHA-256 hashes only after a successful legacy match.

## Reporting vulnerabilities

Please open a private security advisory or contact the repository owner before disclosing a vulnerability publicly.
