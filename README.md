# Pattern Authentication

Pattern Authentication is a Swift package that provides a customizable 3x3 grid-based pattern authentication system for iOS applications. It offers a secure and visually appealing way to implement user authentication or pattern creation. This is useful in applications that may be on multi-user devices to eliminate needing to have every user login via email/password auth.

[](https://github.com/user-attachments/assets/34d3c5b0-3a0f-4a1f-b5b0-207aae6a9ef5)


## Features

- Grid-based pattern authentication
- Customizable appearance (colors, interaction modes)
- Support for both authentication and pattern creation
- Particle effects for enhanced visual feedback
- Shake animation for incorrect attempts
- Debug mode for development and testing
- Minimum pattern length enforcement
- Cryptographic hashing for secure pattern storage

## Requirements

- iOS 15.0+
- Swift 5.10+

## Installation

### Swift Package Manager

Add the following line to your `Package.swift` file's dependencies:

```swift
.package(url: "https://github.com/yourusername/PatternAuthentication.git", from: "1.0.0")
```

Then, include "PatternAuthentication" as a dependency for your target:

```swift
.target(name: "YourTarget", dependencies: ["PatternAuthentication"]),
```

## Usage

### Importing the Package

```swift
import PatternAuthentication
```

### Creating a Pattern Setup View

```swift
GridAuthenticator(.set(
    minimumVertices: 6,
    color: .green,
    interactionMode: .drag,
    repeatInput: true,
    debug: false
) { hash in
    print("New pattern hash: \(hash)")
    // Store this hash securely for later authentication
    // It is HIGHLY recommended that you do this twice to ensure that the pattern is correctly input before saving. Since patterns are hashed for security, there is no way to retrieve the pattern after creation
})
```

### Creating an Authentication View

```swift
let expectedHash = user.patternHash // retrieve expected hash from storage

GridAuthenticator(.authenticate(
    expectedHash: expectedHash,
    color: .blue,
    interactionMode: .drag,
    debug: false
) { success in
    if success {
        print("Authentication successful")
         // here's where we would navigate to a new authenticated area, show a success animation, etc
    } else {
        print("Authentication failed")
         // here's where we would show a failure message, increase attempt counts, etc
    }
})
```

## Customization

The `GridAuthenticator` view can be customized using the following parameters:

- `color`: The primary color of the grid and effects [default: `blue`]
- `interactionMode`: Choose between `.tap` or `.drag` for pattern input [default: `.drag`]
- `debug`: Enable or disable debug information display. This adds some additional logging and some debug UI elements [default: `false`]
- `minimumVertices`: Set the minimum number of points required for a valid pattern (setup mode only) [default: `6`]
- `repeatInput`: The pattern will be repeated back for the user after their initial input and before their confirmation input (setup mode only) [default: `true`]

## Security

Pattern Authentication uses SHA-256 hashing to securely store and compare patterns. The actual pattern is never stored, only its hash.

## Troubleshooting

If you encounter any issues:

1. Ensure you're using the latest version of the package.
2. Check that your iOS deployment target is set to iOS 15.0 or later.
3. If using the debug mode, verify that the current hash matches the expected hash.

## Contributing

Contributions to the Pattern Authentication package are welcome. Please feel free to submit a Merge Request.

## Support

For questions, bug reports, or feature requests, please open an issue on the GitHub repository.

## Roadmap and Known Issues

* *Known Issue* - `.tap` interaction is not currently activated. Passing the `.tap` will not change the input
* *Roadmap* - increase size of particles for a wider particle path

## License

Pattern Authentication is available under the MIT license. See the [LICENSE](LICENSE) file for more info.
