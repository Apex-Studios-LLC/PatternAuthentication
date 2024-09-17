//
//  GridAuthenticatorViewModel.swift
//
//
//  Created by Shain Mack on 9/17/24.
//

import SwiftUI

public class GridAuthenticatorViewModel: ObservableObject {
    @Published public var selectedCardsIndices: [Int] = []
    @Published public var cardsData: [CardPreferenceData] = []
    @Published public var particleSystem = ParticleSystem()
    @Published public var locked: Bool = false
    @Published public var viewColor: Color
    @Published public var debug: Bool
    public var mode: AuthType
    @Published public var incorrectHash: Bool?
    @Published public var interactionMode: InteractionMode
    @Published public var incorrectCount: Int = 0
    @Published public var repeatInput: Bool?
    @Published public var requireConfirmation: Bool?
    @Published public var expectedHash: String?
    public var minimumVertices: Int? = 6
    @Published public var authCompletion: ((Bool) -> Void)?
    @Published public var setupCompletion: ((String) -> Void)?
    @Published public var confirmationState: ConfirmationState = .initial
    @Published public var firstPatternHash: String?

    public var mostRecentSelection: Int? {
        return selectedCardsIndices.last
    }

    public init(_ authOption: GridAuthenticatorOption) {
        switch authOption {
        case let .authenticate(expectedHash, color, interactionMode, debug, completion):
            self.expectedHash = expectedHash
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
        }
    }

    public var currentHash: String {
        return hashArray(selectedCardsIndices)
    }

    public var valid: Bool {
        return selectedCardsIndices.count >= minimumVertices ?? .max
    }

    public var validityText: String {
        switch mode {
        case .authenticate:
            return ""
        case .set:
            return !valid && locked ? "Not long enough. Pattern must include at least \(minimumVertices ?? .max) vertices" : ""
        }
    }

    public func afterDrag() {
        if !selectedCardsIndices.isEmpty {
            if debug {
                print("[DEBUG] Drag ended, hash is: \(currentHash)")
            }
            switch mode {
            case .authenticate:
                authenticateHash()
            case .set:
                locked = true
                if !valid {
                    withAnimation {
                        incorrectCount += 1
                    }
                } else {
                    if repeatInput ?? true {
                        simulatePattern(selectedCardsIndices)
                    }
                }
            }
        }
    }

    public func authenticateHash() {
        if currentHash == expectedHash {
            incorrectHash = nil
            authCompletion?(true)
        } else {
            incorrectHash = true
            selectedCardsIndices = []
            withAnimation(.easeInOut(duration: 0.3)) {
                incorrectCount += 1
            }
        }
    }

    public func duringDrag(drag: DragGesture.Value) {
        if !locked {
            if let data = cardsData.first(where: { $0.bounds.contains(drag.location) }) {
                if selectedCardsIndices.last ?? -1 != data.index {
                    selectedCardsIndices.append(data.index)
                }
            }

            particleSystem.center.x = drag.location.x / UIScreen.main.bounds.width
            particleSystem.center.y = drag.location.y / UIScreen.main.bounds.height
            particleSystem.addParticle(at: drag.location)
        }
    }

    public func simulatePattern(_ pattern: [Int]) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            var lastCenter: CGPoint?
            for index in pattern {
                if index >= 0 && index < cardsData.count {
                    let cardBounds = cardsData[index].bounds
                    let cardCenter = CGPoint(x: cardBounds.midX, y: cardBounds.midY)
                    // selectedCardsIndices.append(index)
                    particleSystem.center = UnitPoint(x: cardCenter.x / UIScreen.main.bounds.width,
                                                      y: cardCenter.y / UIScreen.main.bounds.height)
                    particleSystem.addParticle(at: cardCenter)

                    if let lastCenter = lastCenter {
                        // Generate particles between points
                        let steps = 10
                        for i in 1 ... steps {
                            let t = CGFloat(i) / CGFloat(steps)
                            let intermediatePoint = CGPoint(
                                x: lastCenter.x + (cardCenter.x - lastCenter.x) * t,
                                y: lastCenter.y + (cardCenter.y - lastCenter.y) * t
                            )
                            particleSystem.center = UnitPoint(
                                x: intermediatePoint.x / UIScreen.main.bounds.width,
                                y: intermediatePoint.y / UIScreen.main.bounds.height
                            )
                            particleSystem.addParticle(at: intermediatePoint)
                            try? await Task.sleep(nanoseconds: 20_000_000)
                        }
                    }

                    lastCenter = cardCenter
                    try? await Task.sleep(nanoseconds: 75_000_000)
                }
            }
        }
    }

    private func handleSetPattern() {
        if requireConfirmation ?? false {
            switch confirmationState {
            case .initial:
                // Do nothing, wait for user to press confirm
                if repeatInput ?? true {
                    simulatePattern(selectedCardsIndices)
                }
                break
            case .awaitingConfirmation:
                if currentHash == firstPatternHash {
                    confirmationState = .confirmed
                    setupCompletion?(currentHash)
                } else {
                    // Patterns don't match, reset
                    confirmationState = .initial
                    firstPatternHash = nil
                    selectedCardsIndices = []
                    locked = false
                    incorrectCount += 1
                }
            case .confirmed:
                // This shouldn't happen, but reset if it does
                confirmationState = .initial
                firstPatternHash = nil
                selectedCardsIndices = []
                locked = false
            }
        } else {
            // No confirmation required, complete setup immediately
            if repeatInput ?? true {
                simulatePattern(selectedCardsIndices)
            }
            setupCompletion?(currentHash)
        }
    }

    public func confirmPattern() {
        if valid {
            firstPatternHash = currentHash
            confirmationState = .awaitingConfirmation
            selectedCardsIndices = []
            locked = false
        }
    }

    public enum GridAuthenticatorOption {
        case authenticate(expectedHash: String, color: Color = .blue, interactionMode: InteractionMode = .drag, debug: Bool = false, completion: (Bool) -> Void)
        case set(minimumVertices: Int = 6, color: Color = .blue, interactionMode: InteractionMode = .drag, requireConfirmation: Bool = true, repeatInput: Bool = true, debug: Bool = false, completion: (String) -> Void)
    }

    public enum AuthType {
        case authenticate, set
    }

    public enum InteractionMode {
        case tap, drag
    }

    public enum ConfirmationState {
        case initial, awaitingConfirmation, confirmed
    }
}
