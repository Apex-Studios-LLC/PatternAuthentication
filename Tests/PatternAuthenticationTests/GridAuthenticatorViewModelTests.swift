import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import PatternAuthentication

@Suite("Grid Authenticator View Model")
@MainActor
struct GridAuthenticatorViewModelTests {
    @Test("Credential setup completes without confirmation")
    func credentialSetupCompletesWithoutConfirmation() throws {
        var completedCredential: GestureCredentialEnvelope?
        let viewModel = GridAuthenticatorViewModel(.setCredential(
            minimumVertices: 3,
            requireConfirmation: false,
            repeatInput: false,
            configuration: .testFast
        ) { credential in
            completedCredential = credential
        })

        viewModel.selectedCardsIndices = [0, 1, 2]
        viewModel.afterDrag()

        let credential = try #require(completedCredential)
        #expect(try GestureCredentialHasher.verify(vertices: [0, 1, 2], against: credential))
        #expect(!viewModel.locked)
    }

    @Test("Credential setup reports creation errors")
    func credentialSetupReportsCreationErrors() {
        var didComplete = false
        let invalidConfiguration = GestureHashConfiguration(
            iterations: 1,
            saltLength: 1
        )
        let viewModel = GridAuthenticatorViewModel(.setCredential(
            minimumVertices: 3,
            requireConfirmation: false,
            repeatInput: false,
            configuration: invalidConfiguration
        ) { _ in
            didComplete = true
        })

        viewModel.selectedCardsIndices = [0, 1, 2]
        viewModel.afterDrag()

        #expect(!didComplete)
        #expect(viewModel.lastDragError == "Unable to create gesture credential.")
        #expect(viewModel.incorrectCount == 1)
        #expect(!viewModel.locked)
    }

    @Test("Credential setup requires matching confirmation when enabled")
    func credentialSetupConfirmationFlow() throws {
        var completedCredential: GestureCredentialEnvelope?
        let viewModel = GridAuthenticatorViewModel(.setCredential(
            minimumVertices: 3,
            requireConfirmation: true,
            repeatInput: false,
            configuration: .testFast
        ) { credential in
            completedCredential = credential
        })

        viewModel.selectedCardsIndices = [0, 1, 2]
        viewModel.afterDrag()
        #expect(viewModel.locked)
        #expect(completedCredential == nil)

        viewModel.confirmPattern()
        #expect(viewModel.confirmationState == .awaitingConfirmation)

        viewModel.selectedCardsIndices = [0, 1, 2]
        viewModel.afterDrag()

        let credential = try #require(completedCredential)
        #expect(viewModel.confirmationState == .confirmed)
        #expect(try GestureCredentialHasher.verify(vertices: [0, 1, 2], against: credential))
    }

    @Test("Mismatched confirmation fails and unlocks input")
    func mismatchedConfirmationFails() {
        var completionCount = 0
        let viewModel = GridAuthenticatorViewModel(.setCredential(
            minimumVertices: 3,
            requireConfirmation: true,
            repeatInput: false,
            configuration: .testFast
        ) { _ in
            completionCount += 1
        })

        viewModel.selectedCardsIndices = [0, 1, 2]
        viewModel.afterDrag()
        viewModel.confirmPattern()
        viewModel.selectedCardsIndices = [0, 1, 3]
        viewModel.afterDrag()

        #expect(completionCount == 0)
        #expect(viewModel.lastDragError == "Patterns do not match. Please try again.")
        #expect(!viewModel.locked)
        #expect(viewModel.incorrectCount == 1)
    }

    @Test("Too-short setup pattern is rejected")
    func tooShortPatternFails() {
        var completed = false
        let viewModel = GridAuthenticatorViewModel(.setCredential(
            minimumVertices: 4,
            requireConfirmation: false,
            repeatInput: false,
            configuration: .testFast
        ) { _ in
            completed = true
        })

        viewModel.selectedCardsIndices = [0, 1, 2]
        viewModel.afterDrag()

        #expect(!completed)
        #expect(viewModel.locked)
        #expect(viewModel.lastDragError == "Not long enough. Pattern must include at least 4 vertices")
        #expect(viewModel.incorrectCount == 1)
    }

    @Test("Credential authentication reports success and failure")
    func credentialAuthenticationReportsResult() throws {
        let credential = try GestureCredentialHasher.createCredential(
            for: [0, 1, 2, 5],
            configuration: .testFast
        )
        var results: [Bool] = []
        let viewModel = GridAuthenticatorViewModel(.authenticateCredential(
            credential: credential
        ) { success in
            results.append(success)
        })

        viewModel.selectedCardsIndices = [0, 1, 2, 5]
        viewModel.afterDrag()
        viewModel.selectedCardsIndices = [0, 1, 2, 6]
        viewModel.afterDrag()

        #expect(results == [true, false])
        #expect(viewModel.incorrectCount == 1)
    }

    @Test("Legacy authentication reports success and failure")
    func legacyAuthenticationReportsResult() {
        let pattern = [0, 1, 2, 5]
        let expectedHash = legacyHashArray(pattern)
        var results: [Bool] = []
        let viewModel = GridAuthenticatorViewModel(.authenticate(expectedHash: expectedHash) { success in
            results.append(success)
        })

        viewModel.selectedCardsIndices = pattern
        viewModel.afterDrag()
        viewModel.selectedCardsIndices = [0, 1, 2, 6]
        viewModel.afterDrag()

        #expect(results == [true, false])
        #expect(viewModel.incorrectCount == 1)
    }

    @Test("Legacy setup returns the original hash")
    func legacySetupReturnsOriginalHash() {
        var completedHash: String?
        let pattern = [0, 1, 2]
        let viewModel = GridAuthenticatorViewModel(.set(
            minimumVertices: 3,
            requireConfirmation: false,
            repeatInput: false
        ) { hash in
            completedHash = hash
        })

        viewModel.selectedCardsIndices = pattern
        viewModel.afterDrag()

        #expect(completedHash == legacyHashArray(pattern))
    }

    @Test("Legacy auth can emit an upgraded credential")
    func legacyAuthUpgradeCallback() throws {
        let pattern = [0, 4, 8, 5]
        let legacyHash = legacyHashArray(pattern)
        var upgradedCredential: GestureCredentialEnvelope?
        var authResults: [Bool] = []
        let viewModel = GridAuthenticatorViewModel(.authenticateAndUpgrade(
            expectedHash: legacyHash,
            configuration: .testFast,
            onCredentialUpgrade: { credential in
                upgradedCredential = credential
            },
            completion: { success in
                authResults.append(success)
            }
        ))

        viewModel.selectedCardsIndices = pattern
        viewModel.afterDrag()

        let credential = try #require(upgradedCredential)
        #expect(authResults == [true])
        #expect(try GestureCredentialHasher.verify(vertices: pattern, against: credential))
    }

    @Test("Credential authentication reports malformed envelopes")
    func credentialAuthenticationReportsMalformedEnvelope() {
        let malformedCredential = GestureCredentialEnvelope(
            salt: Data([1]),
            hash: Data(repeating: 2, count: 32),
            kdf: .pbkdf2SHA256,
            iterations: 1,
            hashVersion: 1,
            derivedKeyLength: 32
        )
        var results: [Bool] = []
        let viewModel = GridAuthenticatorViewModel(.authenticateCredential(
            credential: malformedCredential
        ) { success in
            results.append(success)
        })

        viewModel.selectedCardsIndices = [0, 1, 2]
        viewModel.afterDrag()

        #expect(results == [false])
        #expect(viewModel.lastDragError == "Unable to verify gesture credential.")
    }

    @Test("Authentication fails when no expected material is configured")
    func authenticationFailsWithoutExpectedMaterial() {
        var results: [Bool] = []
        let viewModel = GridAuthenticatorViewModel(.authenticate(expectedHash: "unused") { success in
            results.append(success)
        })
        viewModel.expectedHash = nil
        viewModel.selectedCardsIndices = [0, 1, 2]

        viewModel.authenticateHash()

        #expect(results == [false])
        #expect(viewModel.incorrectHash == true)
    }

    @Test("Selected card centers follow preference data")
    func selectedCardCentersFollowPreferenceData() {
        let viewModel = GridAuthenticatorViewModel(.setCredential(repeatInput: false) { _ in })
        viewModel.cardsData = [
            CardPreferenceData(index: 0, bounds: CGRect(x: 0, y: 0, width: 10, height: 10)),
            CardPreferenceData(index: 4, bounds: CGRect(x: 40, y: 40, width: 10, height: 10)),
            CardPreferenceData(index: 8, bounds: CGRect(x: 80, y: 80, width: 10, height: 10)),
        ]
        viewModel.selectedCardsIndices = [0, 4, 8]

        #expect(viewModel.selectedCardCenters == [
            CGPoint(x: 5, y: 5),
            CGPoint(x: 45, y: 45),
            CGPoint(x: 85, y: 85),
        ])
        #expect(viewModel.mostRecentSelection == 8)
    }

    @Test("Validity text hides while dragging")
    func validityTextHidesWhileDragging() {
        let viewModel = GridAuthenticatorViewModel(.setCredential(repeatInput: false) { _ in })
        viewModel.lastDragError = "Visible"
        #expect(viewModel.validityText == "Visible")

        viewModel.isDragging = true
        #expect(viewModel.validityText == "")
    }

    @Test("Nil minimum vertices requires an impossible length")
    func nilMinimumVerticesRequiresImpossibleLength() {
        let viewModel = GridAuthenticatorViewModel(.setCredential(repeatInput: false) { _ in })
        viewModel.minimumVertices = nil
        viewModel.selectedCardsIndices = [0, 1, 2, 3, 4, 5, 6, 7, 8]

        #expect(!viewModel.valid)
    }

    @Test("Simulation path follows configured centers")
    func simulationPathFollowsConfiguredCenters() {
        let viewModel = GridAuthenticatorViewModel(.setCredential(repeatInput: true) { _ in })
        viewModel.cardsData = [
            CardPreferenceData(index: 0, bounds: CGRect(x: 0, y: 0, width: 10, height: 10)),
            CardPreferenceData(index: 1, bounds: CGRect(x: 40, y: 0, width: 10, height: 10)),
        ]

        let points = viewModel.simulationPoints(for: [0, 1], stepsBetweenCenters: 4)

        #expect(points.count == 5)
        #expect(points.first == CGPoint(x: 5, y: 5))
        #expect(points.last == CGPoint(x: 45, y: 5))
        #expect(points.contains(CGPoint(x: 25, y: 5)))
    }

    @Test("Simulation path supports zero interpolation steps")
    func simulationPathSupportsZeroInterpolationSteps() {
        let viewModel = GridAuthenticatorViewModel(.setCredential(repeatInput: true) { _ in })
        viewModel.cardsData = [
            CardPreferenceData(index: 0, bounds: CGRect(x: 0, y: 0, width: 10, height: 10)),
            CardPreferenceData(index: 1, bounds: CGRect(x: 40, y: 0, width: 10, height: 10)),
        ]

        let points = viewModel.simulationPoints(for: [0, 1], stepsBetweenCenters: 0)

        #expect(points == [
            CGPoint(x: 5, y: 5),
            CGPoint(x: 45, y: 5),
        ])
    }

    @Test("Simulation emits particles with injected timing")
    func simulationEmitsParticlesWithInjectedTiming() async throws {
        let viewModel = GridAuthenticatorViewModel(.setCredential(repeatInput: true) { _ in })
        viewModel.cardsData = [
            CardPreferenceData(index: 0, bounds: CGRect(x: 0, y: 0, width: 10, height: 10)),
            CardPreferenceData(index: 1, bounds: CGRect(x: 40, y: 0, width: 10, height: 10)),
        ]

        viewModel.simulatePattern(
            [0, 1],
            initialDelayNanoseconds: 0,
            pointDelayNanoseconds: 0
        )
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(!viewModel.isSimulating)
        #expect(!viewModel.particleSystem.particles.isEmpty)
    }

    @Test("Reset clears setup state")
    func resetClearsState() {
        let viewModel = GridAuthenticatorViewModel(.setCredential(repeatInput: false) { _ in })
        viewModel.selectedCardsIndices = [0, 1, 2]
        viewModel.locked = true
        viewModel.firstPatternHash = "hash"
        viewModel.lastDragError = "error"
        viewModel.confirmationState = .awaitingConfirmation

        viewModel.reset()

        #expect(viewModel.selectedCardsIndices.isEmpty)
        #expect(!viewModel.locked)
        #expect(viewModel.firstPatternHash == nil)
        #expect(viewModel.lastDragError == nil)
        #expect(viewModel.confirmationState == .initial)
    }

    @Test("SwiftUI body smoke test")
    func swiftUIBodySmokeTest() {
        let view = GridAuthenticator(.setCredential(repeatInput: false) { _ in })
        _ = view.body

        let circle = GlowyCircle(
            index: 0,
            viewModel: GridAuthenticatorViewModel(.setCredential(repeatInput: false) { _ in })
        )
        _ = circle.body
    }
}

private extension GestureHashConfiguration {
    static let testFast = GestureHashConfiguration(iterations: 1, saltLength: 16)
}
