//
//  GridAuthenticatorViewModel.swift
//
//
//  Created by Shain Mack on 9/17/24.
//

import SwiftUI

/// Coordinates gesture input, setup, authentication, replay, and visual state.
///
/// `GridAuthenticatorViewModel` is the imperative model behind
/// `GridAuthenticator`. It is isolated to the main actor because it owns
/// SwiftUI-observed state and animation state.
@MainActor
public class GridAuthenticatorViewModel: ObservableObject {
    /// The ordered 3x3 grid indices selected during the current gesture.
    @Published public var selectedCardsIndices: [Int] = []

    /// Geometry captured from each grid circle in the grid coordinate space.
    @Published public var cardsData: [CardPreferenceData] = []

    /// The particle system used to render drag and replay particles.
    @Published public var particleSystem = ParticleSystem()

    /// Whether the current gesture is locked while setup confirmation is pending.
    @Published public var locked: Bool = false

    /// The primary color used by the grid, glow, and particles.
    @Published public var viewColor: Color

    /// Whether developer diagnostics should be shown in the view.
    @Published public var debug: Bool

    /// The high-level mode for this authenticator instance.
    public var mode: AuthType

    /// Whether the most recent authentication attempt failed.
    @Published public var incorrectHash: Bool?

    /// The input style expected by this authenticator.
    @Published public var interactionMode: InteractionMode

    /// The number of failed attempts used to drive the shake animation.
    @Published public var incorrectCount: Int = 0

    /// Whether setup should replay the entered gesture after input.
    @Published public var repeatInput: Bool?

    /// Whether setup requires the user to enter the same gesture twice.
    @Published public var requireConfirmation: Bool?

    /// The legacy v0 SHA-256 hash used by deprecated authentication APIs.
    @Published public var expectedHash: String?

    /// The v1 salted credential envelope used by credential authentication APIs.
    @Published public var expectedCredential: GestureCredentialEnvelope?

    /// The minimum number of vertices required during setup.
    public var minimumVertices: Int? = 6

    /// The hashing configuration used when creating or upgrading v1 credentials.
    public var hashConfiguration: GestureHashConfiguration = .recommended

    /// Callback invoked after authentication succeeds or fails.
    @Published public var authCompletion: ((Bool) -> Void)?

    /// Callback invoked by deprecated setup APIs with a legacy v0 hash.
    @Published public var setupCompletion: ((String) -> Void)?

    /// Callback invoked by v1 setup APIs with a credential envelope.
    @Published public var credentialSetupCompletion: ((GestureCredentialEnvelope) -> Void)?

    /// Callback invoked after successful legacy authentication creates a v1 credential.
    @Published public var legacyUpgradeCompletion: ((GestureCredentialEnvelope) -> Void)?

    /// The setup confirmation state.
    @Published public var confirmationState: ConfirmationState = .initial

    /// The legacy hash of the first setup pattern when confirmation is required.
    @Published public var firstPatternHash: String?

    /// Whether an entered pattern is currently being replayed.
    @Published public var isSimulating: Bool = false
    private var simulationTask: Task<Void, Never>?

    /// The in-flight credential derivation or verification task.
    private var credentialTask: Task<Void, Never>?

    /// Whether the user currently has an active drag gesture.
    @Published public var isDragging: Bool = false

    /// The most recent user-facing validation or credential error.
    @Published public var lastDragError: String?

    /// The last selected grid index in the current gesture.
    ///
    /// - Returns: The most recent selected vertex, or `nil` when no vertices
    ///   are selected.
    public var mostRecentSelection: Int? {
        selectedCardsIndices.last
    }

    /// The captured centers of the currently selected cards.
    ///
    /// - Returns: The selected card centers in selection order, omitting any
    ///   indices whose geometry has not yet been reported by SwiftUI.
    public var selectedCardCenters: [CGPoint] {
        selectedCardsIndices.compactMap { center(for: $0) }
    }

    /// Creates a view model for one setup or authentication flow.
    ///
    /// - Parameter authOption: The setup or authentication option that
    ///   configures mode, defaults, expected credential material, and callbacks.
    /// - Returns: A main-actor view model configured for `authOption`.
    /// - Throws: This initializer does not throw.
    public init(_ authOption: GridAuthenticatorOption) {
        switch authOption {
        case let .authenticate(expectedHash, color, interactionMode, debug, completion):
            self.expectedHash = expectedHash
            viewColor = color
            self.interactionMode = interactionMode
            self.debug = debug
            mode = .authenticate
            authCompletion = completion

        case let .authenticateAndUpgrade(expectedHash, color, interactionMode, debug, configuration, onCredentialUpgrade, completion):
            self.expectedHash = expectedHash
            viewColor = color
            self.interactionMode = interactionMode
            self.debug = debug
            hashConfiguration = configuration
            mode = .authenticate
            legacyUpgradeCompletion = onCredentialUpgrade
            authCompletion = completion

        case let .authenticateCredential(credential, color, interactionMode, debug, completion):
            expectedCredential = credential
            viewColor = color
            self.interactionMode = interactionMode
            self.debug = debug
            mode = .authenticate
            authCompletion = completion

        case let .set(minimumVertices, color, interactionMode, requireConfirmation, repeatInput, debug, completion):
            self.minimumVertices = minimumVertices
            self.repeatInput = repeatInput
            viewColor = color
            self.interactionMode = interactionMode
            self.requireConfirmation = requireConfirmation
            self.debug = debug
            mode = .set
            setupCompletion = completion

        case let .setCredential(minimumVertices, color, interactionMode, requireConfirmation, repeatInput, debug, configuration, completion):
            self.minimumVertices = minimumVertices
            self.repeatInput = repeatInput
            viewColor = color
            self.interactionMode = interactionMode
            self.requireConfirmation = requireConfirmation
            self.debug = debug
            hashConfiguration = configuration
            mode = .set
            credentialSetupCompletion = completion
        }
    }

    /// The legacy v0 hash for the current gesture selection.
    ///
    /// - Returns: A hexadecimal SHA-256 hash produced by the legacy hash
    ///   algorithm.
    public var currentHash: String {
        legacyHashArray(selectedCardsIndices)
    }

    /// Whether the current gesture satisfies the configured minimum length.
    ///
    /// - Returns: `true` when `selectedCardsIndices.count` is greater than or
    ///   equal to ``minimumVertices``; otherwise, `false`.
    public var valid: Bool {
        selectedCardsIndices.count >= (minimumVertices ?? .max)
    }

    /// The validation text currently safe to show to the user.
    ///
    /// - Returns: An empty string while dragging, then the latest validation
    ///   message after drag end.
    public var validityText: String {
        if isDragging {
            return ""
        }
        return lastDragError ?? ""
    }

    /// Handles an in-progress drag gesture over the grid.
    ///
    /// - Parameter drag: The SwiftUI drag value whose `location` is expressed
    ///   in the grid coordinate space.
    /// The method does not return a value. It mutates selected vertices and
    /// particle state.
    /// - Throws: This method does not throw.
    public func duringDrag(drag: DragGesture.Value) {
        let wasDragging = isDragging
        isDragging = true
        guard !locked else { return }

        if !wasDragging {
            particleSystem.resetTrail()
        }

        if let data = cardsData.first(where: { $0.bounds.contains(drag.location) }),
           selectedCardsIndices.last ?? -1 != data.index {
            selectedCardsIndices.append(data.index)
        }

        particleSystem.addParticle(at: drag.location)
    }

    /// Completes the current drag gesture and dispatches setup or authentication.
    ///
    /// The method does not return a value. It mutates flow state and may invoke
    /// a completion callback.
    /// - Throws: This method does not throw. Credential errors are converted to
    ///   user-facing state.
    public func afterDrag() {
        isDragging = false
        guard !selectedCardsIndices.isEmpty else { return }
        particleSystem.resetTrail()

        if debug {
            print("[DEBUG] Drag ended with \(selectedCardsIndices.count) selected vertices.")
        }

        switch mode {
        case .authenticate:
            authenticateHash()
        case .set:
            locked = true
            lastDragError = nil
            guard valid else {
                withAnimation {
                    incorrectCount += 1
                }
                lastDragError = "Not long enough. Pattern must include at least \(minimumVertices ?? .max) vertices"
                return
            }
            handleSetPattern()
        }
    }

    /// Authenticates the currently selected pattern.
    ///
    /// The method does not return a value. The configured authentication
    /// completion is invoked with `true` or `false`.
    /// - Throws: This method does not throw. Verification errors are converted
    ///   to failed authentication state.
    public func authenticateHash() {
        let pattern = selectedCardsIndices

        if let expectedCredential {
            authenticateCredential(pattern, credential: expectedCredential)
            return
        }

        authenticateLegacyHash(pattern)
    }

    /// Replays a pattern by emitting particles along captured grid centers.
    ///
    /// - Parameter pattern: Ordered 3x3 grid vertex indices to replay.
    /// This method does not return a value. Replay state and particles are
    /// updated asynchronously on the main actor.
    /// - Throws: This method does not throw.
    public func simulatePattern(_ pattern: [Int]) {
        simulatePattern(
            pattern,
            initialDelayNanoseconds: 500_000_000,
            pointDelayNanoseconds: 20_000_000
        )
    }

    /// Replays a pattern with explicit timing for tests and preview harnesses.
    ///
    /// - Parameters:
    ///   - pattern: Ordered 3x3 grid vertex indices to replay.
    ///   - initialDelayNanoseconds: Delay before the first particle is emitted.
    ///     No default.
    ///   - pointDelayNanoseconds: Delay between emitted replay points. No
    ///     default.
    /// This method does not return a value. Replay state and particles are
    /// updated asynchronously on the main actor.
    /// - Throws: This method does not throw.
    func simulatePattern(
        _ pattern: [Int],
        initialDelayNanoseconds: UInt64,
        pointDelayNanoseconds: UInt64
    ) {
        cancelSimulation()
        isSimulating = true
        simulationTask = Task { @MainActor in
            particleSystem.resetTrail()
            defer {
                particleSystem.resetTrail()
                isSimulating = false
            }
            if initialDelayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: initialDelayNanoseconds)
            }
            let replayPoints = simulationPoints(for: pattern)

            for point in replayPoints {
                if Task.isCancelled { return }
                particleSystem.addParticle(at: point)
                if pointDelayNanoseconds > 0 {
                    try? await Task.sleep(nanoseconds: pointDelayNanoseconds)
                }
            }
        }
    }

    /// Builds the deterministic grid-local replay path for a gesture pattern.
    ///
    /// - Parameters:
    ///   - pattern: Ordered 3x3 grid vertex indices to replay.
    ///   - stepsBetweenCenters: Number of interpolated steps between two
    ///     adjacent selected centers. Defaults to `10`.
    /// - Returns: Grid-local points beginning at the first available center and
    ///   ending at the final available center.
    /// - Throws: This method does not throw.
    func simulationPoints(for pattern: [Int], stepsBetweenCenters: Int = 10) -> [CGPoint] {
        guard stepsBetweenCenters > 0 else {
            return pattern.compactMap { center(for: $0) }
        }

        var points: [CGPoint] = []
        var lastCenter: CGPoint?

        for index in pattern {
            guard let cardCenter = center(for: index) else { continue }

            if let lastCenter {
                for step in 1 ... stepsBetweenCenters {
                    let t = CGFloat(step) / CGFloat(stepsBetweenCenters)
                    points.append(CGPoint(
                        x: lastCenter.x + (cardCenter.x - lastCenter.x) * t,
                        y: lastCenter.y + (cardCenter.y - lastCenter.y) * t
                    ))
                }
            } else {
                points.append(cardCenter)
            }

            lastCenter = cardCenter
        }

        return points
    }

    /// Cancels an active replay animation.
    ///
    /// This method does not return a value. Replay state is reset immediately.
    /// - Throws: This method does not throw.
    public func cancelSimulation() {
        simulationTask?.cancel()
        simulationTask = nil
        isSimulating = false
    }

    /// Stores the first setup pattern and moves to confirmation input.
    ///
    /// This method does not return a value. If the current pattern is valid,
    /// confirmation state is updated and the selection is cleared.
    /// - Throws: This method does not throw.
    public func confirmPattern() {
        if valid {
            firstPatternHash = currentHash
            confirmationState = .awaitingConfirmation
            selectedCardsIndices = []
            locked = false
            lastDragError = nil
        }
    }

    /// Resets the current setup or authentication attempt.
    ///
    /// This method does not return a value. Selection, lock state,
    /// confirmation state, replay, and validation messages are cleared.
    /// - Throws: This method does not throw.
    public func reset() {
        cancelSimulation()
        cancelCredentialTask()
        selectedCardsIndices = []
        locked = false
        confirmationState = .initial
        firstPatternHash = nil
        lastDragError = nil
    }

    /// Finds the grid-space center point for a grid index.
    ///
    /// - Parameter index: A zero-based 3x3 grid index.
    /// - Returns: The captured center point for `index`, or `nil` when geometry
    ///   has not been reported.
    /// - Throws: This method does not throw.
    public func center(for index: Int) -> CGPoint? {
        cardsData.first(where: { $0.index == index }).map {
            CGPoint(x: $0.bounds.midX, y: $0.bounds.midY)
        }
    }

    /// Processes a completed setup gesture.
    ///
    /// This method does not return a value. It advances confirmation state,
    /// creates a credential, or records validation failure state.
    /// - Throws: This method does not throw. Credential creation errors are
    ///   converted to `lastDragError`.
    private func handleSetPattern() {
        let pattern = selectedCardsIndices

        if requireConfirmation ?? false {
            switch confirmationState {
            case .initial:
                if repeatInput ?? true {
                    simulatePattern(pattern)
                }
            case .awaitingConfirmation:
                if legacyHashArray(pattern) == firstPatternHash {
                    confirmationState = .confirmed
                    completeSetup(with: pattern)
                } else {
                    incorrectCount += 1
                    lastDragError = "Patterns do not match. Please try again."
                    selectedCardsIndices = []
                    locked = false
                }
            case .confirmed:
                reset()
            }
        } else {
            if repeatInput ?? true {
                simulatePattern(pattern)
            }
            completeSetup(with: pattern)
        }
    }

    /// Completes setup by invoking the configured legacy or v1 setup callback.
    ///
    /// - Parameter pattern: The validated vertex sequence to store.
    /// This method does not return a value. It invokes a setup callback and
    /// clears the current gesture on success.
    /// - Throws: This method does not throw. Credential creation errors are
    ///   converted to `lastDragError`.
    private func completeSetup(with pattern: [Int]) {
        if credentialSetupCompletion != nil {
            startCredentialSetupTask(for: pattern)
            return
        }

        setupCompletion?(legacyHashArray(pattern))
        finishSetup()
    }

    /// Starts credential setup work without blocking the main actor.
    ///
    /// - Parameter pattern: The validated vertex sequence to store.
    /// This method does not return a value. It invokes the credential setup
    /// callback on the main actor after derivation finishes.
    /// - Throws: This method does not throw. Credential creation errors are
    ///   converted to `lastDragError`.
    private func startCredentialSetupTask(for pattern: [Int]) {
        cancelCredentialTask()
        let configuration = hashConfiguration

        credentialTask = Task { @MainActor [weak self] in
            do {
                let credential = try await Self.createCredentialOffMainActor(
                    for: pattern,
                    configuration: configuration
                )
                guard let self, !Task.isCancelled else { return }
                credentialSetupCompletion?(credential)
                finishSetup()
            } catch {
                guard let self, !Task.isCancelled else { return }
                incorrectCount += 1
                lastDragError = "Unable to create gesture credential."
                finishSetup()
            }
        }
    }

    /// Verifies a v1 credential without blocking the main actor.
    ///
    /// - Parameters:
    ///   - pattern: The selected vertex sequence to authenticate.
    ///   - credential: The stored credential envelope fetched by the app.
    /// This method does not return a value. It invokes the authentication
    /// callback on the main actor after verification finishes.
    /// - Throws: This method does not throw. Verification errors are converted
    ///   to failed authentication state.
    private func authenticateCredential(_ pattern: [Int], credential: GestureCredentialEnvelope) {
        cancelCredentialTask()

        credentialTask = Task { @MainActor [weak self] in
            do {
                let success = try await Self.verifyCredentialOffMainActor(
                    vertices: pattern,
                    credential: credential
                )
                guard let self, !Task.isCancelled else { return }
                if success {
                    incorrectHash = nil
                    authCompletion?(true)
                } else {
                    failAuthentication()
                }
            } catch {
                guard let self, !Task.isCancelled else { return }
                lastDragError = "Unable to verify gesture credential."
                failAuthentication()
            }
        }
    }

    /// Authenticates a legacy v0 hash and optionally upgrades it to a v1 credential.
    ///
    /// - Parameter pattern: The selected vertex sequence to authenticate.
    /// This method does not return a value. Legacy hash comparison happens
    /// synchronously; optional v1 upgrade derivation runs off the main actor.
    /// - Throws: This method does not throw. Migration errors are converted to
    ///   `lastDragError` while preserving successful authentication.
    private func authenticateLegacyHash(_ pattern: [Int]) {
        guard let expectedHash else {
            failAuthentication()
            return
        }
        let success = GestureCredentialHasher.verifyLegacySHA256(
            vertices: pattern,
            expectedHash: expectedHash
        )

        guard success else {
            failAuthentication()
            return
        }

        guard legacyUpgradeCompletion != nil else {
            incorrectHash = nil
            authCompletion?(true)
            return
        }

        startLegacyUpgradeAuthenticationTask(for: pattern)
    }

    /// Creates an upgraded v1 credential after a successful legacy match.
    ///
    /// - Parameter pattern: The legacy-authenticated vertex sequence to upgrade.
    /// This method does not return a value. It invokes the upgrade callback
    /// before reporting authentication success, matching the previous callback
    /// order without blocking the main actor.
    /// - Throws: This method does not throw. Migration errors are converted to
    ///   `lastDragError` while preserving successful authentication.
    private func startLegacyUpgradeAuthenticationTask(for pattern: [Int]) {
        cancelCredentialTask()
        let configuration = hashConfiguration

        credentialTask = Task { @MainActor [weak self] in
            do {
                let credential = try await Self.createCredentialOffMainActor(
                    for: pattern,
                    configuration: configuration
                )
                guard let self, !Task.isCancelled else { return }
                legacyUpgradeCompletion?(credential)
            } catch {
                guard let self, !Task.isCancelled else { return }
                lastDragError = "Gesture matched, but credential migration failed."
            }

            guard let self, !Task.isCancelled else { return }
            incorrectHash = nil
            authCompletion?(true)
        }
    }

    /// Clears setup state after a setup attempt completes.
    ///
    /// This method does not return a value. It clears the selected pattern and
    /// unlocks input.
    /// - Throws: This method does not throw.
    private func finishSetup() {
        selectedCardsIndices = []
        locked = false
    }

    /// Cancels any in-flight credential derivation or verification task.
    ///
    /// This method does not return a value. Already-started key derivation may
    /// finish in the background, but cancelled tasks do not update view state.
    /// - Throws: This method does not throw.
    private func cancelCredentialTask() {
        credentialTask?.cancel()
        credentialTask = nil
    }

    /// Creates a v1 credential on a background executor.
    ///
    /// - Parameters:
    ///   - pattern: Ordered 3x3 grid vertex indices in the range `0...8`.
    ///   - configuration: The hashing configuration to use.
    /// - Returns: A new credential envelope with a fresh random salt.
    /// - Throws: Any error thrown by `GestureCredentialHasher.createCredential`.
    private nonisolated static func createCredentialOffMainActor(
        for pattern: [Int],
        configuration: GestureHashConfiguration
    ) async throws -> GestureCredentialEnvelope {
        try await Task.detached(priority: .userInitiated) {
            try GestureCredentialHasher.createCredential(
                for: pattern,
                configuration: configuration
            )
        }.value
    }

    /// Verifies a v1 credential on a background executor.
    ///
    /// - Parameters:
    ///   - vertices: Ordered 3x3 grid vertex indices in the range `0...8`.
    ///   - credential: The stored credential envelope fetched by the app.
    /// - Returns: `true` when `vertices` derive the stored credential hash;
    ///   otherwise, `false`.
    /// - Throws: Any error thrown by `GestureCredentialHasher.verify`.
    private nonisolated static func verifyCredentialOffMainActor(
        vertices: [Int],
        credential: GestureCredentialEnvelope
    ) async throws -> Bool {
        try await Task.detached(priority: .userInitiated) {
            try GestureCredentialHasher.verify(vertices: vertices, against: credential)
        }.value
    }

    /// Applies failed-authentication UI state.
    ///
    /// This method does not return a value. It clears the selection, increments
    /// the shake counter, and invokes the authentication completion with
    /// `false`.
    /// - Throws: This method does not throw.
    private func failAuthentication() {
        incorrectHash = true
        selectedCardsIndices = []
        withAnimation(.easeInOut(duration: 0.3)) {
            incorrectCount += 1
        }
        authCompletion?(false)
    }

    /// Defines the setup or authentication flow hosted by `GridAuthenticator`.
    public enum GridAuthenticatorOption {
        /// Creates a deprecated v0 setup flow that returns a legacy SHA-256 hash.
        ///
        /// - Parameters:
        ///   - minimumVertices: Minimum selected vertices required before setup
        ///     succeeds. Defaults to `6`.
        ///   - color: Primary grid and particle color. Defaults to `.blue`.
        ///   - interactionMode: Input style for the grid. Defaults to `.drag`.
        ///   - requireConfirmation: Whether the user must repeat the pattern
        ///     before completion. Defaults to `true`.
        ///   - repeatInput: Whether the package replays the pattern after setup
        ///     input. Defaults to `true`.
        ///   - debug: Whether to show developer diagnostics. Defaults to
        ///     `false`.
        ///   - completion: Callback receiving the legacy hexadecimal SHA-256
        ///     hash.
        @available(*, deprecated, message: "Use setCredential(...) for salted gesture credentials.")
        case set(
            minimumVertices: Int = 6,
            color: Color = .blue,
            interactionMode: InteractionMode = .drag,
            requireConfirmation: Bool = true,
            repeatInput: Bool = true,
            debug: Bool = false,
            completion: (String) -> Void
        )

        /// Creates a deprecated v0 authentication flow against a legacy hash.
        ///
        /// - Parameters:
        ///   - expectedHash: The legacy hexadecimal SHA-256 hash fetched by the
        ///     app.
        ///   - color: Primary grid and particle color. Defaults to `.blue`.
        ///   - interactionMode: Input style for the grid. Defaults to `.drag`.
        ///   - debug: Whether to show developer diagnostics. Defaults to
        ///     `false`.
        ///   - completion: Callback receiving `true` for a match or `false` for
        ///     a failed attempt.
        @available(*, deprecated, message: "Use authenticateCredential(...) for salted gesture credentials.")
        case authenticate(
            expectedHash: String,
            color: Color = .blue,
            interactionMode: InteractionMode = .drag,
            debug: Bool = false,
            completion: (Bool) -> Void
        )

        /// Creates a v1 setup flow that returns a salted credential envelope.
        ///
        /// - Parameters:
        ///   - minimumVertices: Minimum selected vertices required before setup
        ///     succeeds. Defaults to `6`.
        ///   - color: Primary grid and particle color. Defaults to `.blue`.
        ///   - interactionMode: Input style for the grid. Defaults to `.drag`.
        ///   - requireConfirmation: Whether the user must repeat the pattern
        ///     before completion. Defaults to `true`.
        ///   - repeatInput: Whether the package replays the pattern after setup
        ///     input. Defaults to `true`.
        ///   - debug: Whether to show developer diagnostics. Defaults to
        ///     `false`.
        ///   - configuration: Hashing configuration for the new credential.
        ///     Defaults to ``GestureHashConfiguration/recommended``.
        ///   - completion: Callback receiving the newly created v1 credential
        ///     envelope.
        case setCredential(
            minimumVertices: Int = 6,
            color: Color = .blue,
            interactionMode: InteractionMode = .drag,
            requireConfirmation: Bool = true,
            repeatInput: Bool = true,
            debug: Bool = false,
            configuration: GestureHashConfiguration = .recommended,
            completion: (GestureCredentialEnvelope) -> Void
        )

        /// Creates a v1 authentication flow against a credential envelope.
        ///
        /// - Parameters:
        ///   - credential: The stored credential envelope fetched by the app.
        ///   - color: Primary grid and particle color. Defaults to `.blue`.
        ///   - interactionMode: Input style for the grid. Defaults to `.drag`.
        ///   - debug: Whether to show developer diagnostics. Defaults to
        ///     `false`.
        ///   - completion: Callback receiving `true` for a match or `false` for
        ///     a failed attempt.
        case authenticateCredential(
            credential: GestureCredentialEnvelope,
            color: Color = .blue,
            interactionMode: InteractionMode = .drag,
            debug: Bool = false,
            completion: (Bool) -> Void
        )

        /// Creates a legacy authentication flow that upgrades successful logins to v1.
        ///
        /// - Parameters:
        ///   - expectedHash: The legacy hexadecimal SHA-256 hash fetched by the
        ///     app.
        ///   - color: Primary grid and particle color. Defaults to `.blue`.
        ///   - interactionMode: Input style for the grid. Defaults to `.drag`.
        ///   - debug: Whether to show developer diagnostics. Defaults to
        ///     `false`.
        ///   - configuration: Hashing configuration for the upgraded v1
        ///     credential. Defaults to ``GestureHashConfiguration/recommended``.
        ///   - onCredentialUpgrade: Callback receiving the new v1 credential
        ///     envelope after legacy authentication succeeds.
        ///   - completion: Callback receiving `true` for a legacy match or
        ///     `false` for a failed attempt.
        case authenticateAndUpgrade(
            expectedHash: String,
            color: Color = .blue,
            interactionMode: InteractionMode = .drag,
            debug: Bool = false,
            configuration: GestureHashConfiguration = .recommended,
            onCredentialUpgrade: (GestureCredentialEnvelope) -> Void,
            completion: (Bool) -> Void
        )
    }

    /// The high-level authenticator flow type.
    public enum AuthType {
        /// Authenticate an entered gesture against expected credential material.
        case authenticate

        /// Create new credential material from an entered gesture.
        case set
    }

    /// The supported grid interaction styles.
    public enum InteractionMode {
        /// Tap-based selection.
        case tap

        /// Drag-based selection. This is the current default.
        case drag
    }

    /// The setup confirmation state.
    public enum ConfirmationState {
        /// The user is entering the first setup pattern.
        case initial

        /// The user is entering the confirmation pattern.
        case awaitingConfirmation

        /// The setup pattern was confirmed.
        case confirmed
    }
}
