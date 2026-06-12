import CoreGraphics
import SwiftUI
import Testing
@testable import PatternAuthentication

@Suite("Animation Support")
@MainActor
struct AnimationSupportTests {
    @Test("Particle system adds and expires particles")
    func particleSystemLifecycle() {
        let system = ParticleSystem()
        system.addParticle(at: CGPoint(x: 10, y: 20))
        #expect(system.particles.count == 1)
        #expect(system.particles.first?.x == 10)
        #expect(system.particles.first?.y == 20)

        let futureDate = Date.now.timeIntervalSinceReferenceDate + 2
        system.update(date: futureDate)
        #expect(system.particles.isEmpty)
    }

    @Test("Particle system interpolates fast movement")
    func particleSystemInterpolatesFastMovement() {
        let system = ParticleSystem(particleDiameter: 44, emissionSpacing: 5, particleLifetime: 1)

        system.addParticle(at: CGPoint(x: 0, y: 0))
        system.addParticle(at: CGPoint(x: 20, y: 0))

        let emittedXPositions = Set(system.particles.map { Int($0.x.rounded()) })
        #expect(system.particles.count == 5)
        #expect(emittedXPositions == [0, 5, 10, 15, 20])
    }

    @Test("Particle trail reset prevents cross-stroke interpolation")
    func particleTrailResetPreventsCrossStrokeInterpolation() {
        let system = ParticleSystem(emissionSpacing: 5)

        system.addParticle(at: CGPoint(x: 0, y: 0))
        system.resetTrail()
        system.addParticle(at: CGPoint(x: 100, y: 0))

        #expect(system.particles.count == 2)
    }

    @Test("Particle system clamps rendering configuration")
    func particleSystemClampsRenderingConfiguration() {
        let system = ParticleSystem(particleDiameter: -10, emissionSpacing: 0, particleLifetime: -1)

        #expect(system.particleDiameter == 1)
        #expect(system.emissionSpacing == 1)
        #expect(system.particleLifetime == 0.1)
    }

    @Test("Shake effect creates a projection transform")
    func shakeEffectProducesTransform() {
        let shake = Shake(amount: 10, shakesPerUnit: 3, animatableData: 1)
        _ = shake.effectValue(size: CGSize(width: 100, height: 100))
    }

    @Test("Preference key appends card data")
    func preferenceKeyReducesValues() {
        var value = CardPreferenceKey.defaultValue
        CardPreferenceKey.reduce(value: &value) {
            [CardPreferenceData(index: 1, bounds: CGRect(x: 0, y: 0, width: 20, height: 20))]
        }

        #expect(value == [
            CardPreferenceData(index: 1, bounds: CGRect(x: 0, y: 0, width: 20, height: 20)),
        ])
    }
}
