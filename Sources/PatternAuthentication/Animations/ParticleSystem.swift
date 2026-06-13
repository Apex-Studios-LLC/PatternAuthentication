//
//  File.swift
//  
//
//  Created by Shain Mack on 9/17/24.
//
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// A single path particle rendered in grid-local coordinates.
public struct Particle: Hashable, Sendable {
    /// The particle's x-coordinate in the grid canvas coordinate space.
    public let x: Double

    /// The particle's y-coordinate in the grid canvas coordinate space.
    public let y: Double

    /// The reference date used to fade and expire the particle.
    public let creationDate: TimeInterval

    /// Creates a particle at a canvas-local point.
    ///
    /// - Parameters:
    ///   - x: The x-coordinate in the grid canvas coordinate space.
    ///   - y: The y-coordinate in the grid canvas coordinate space.
    ///   - creationDate: The reference date used for aging. Defaults to
    ///     `Date.now.timeIntervalSinceReferenceDate`.
    /// - Returns: A particle ready to render.
    /// - Throws: This initializer does not throw.
    public init(
        x: Double,
        y: Double,
        creationDate: TimeInterval = Date.now.timeIntervalSinceReferenceDate
    ) {
        self.x = x
        self.y = y
        self.creationDate = creationDate
    }
}

/// Stores and expires gesture path particles for the authenticator canvas.
///
/// `ParticleSystem` is main-actor isolated because it owns SwiftUI image state
/// and is mutated by SwiftUI gesture callbacks and timeline rendering.
@MainActor
public final class ParticleSystem {
    /// The spark image loaded from the SwiftPM resource bundle.
    public let image = Image("spark", bundle: Bundle.module)

    /// The rendered point-size of each particle.
    public let particleDiameter: CGFloat

    /// The maximum point distance between interpolated particles.
    public let emissionSpacing: CGFloat

    /// The number of seconds a particle remains visible.
    public let particleLifetime: TimeInterval

    /// The active particles currently visible in the canvas.
    public var particles = Set<Particle>()

    private var lastEmissionPoint: CGPoint?

    /// Creates an empty particle system.
    ///
    /// - Parameters:
    ///   - particleDiameter: Rendered point-size of each particle. Defaults to
    ///     `44`, which approximates a fingertip-sized trail on iPhone displays.
    ///     Values below `1` are clamped to `1`.
    ///   - emissionSpacing: Maximum point distance between interpolated
    ///     particles. Defaults to `4`. Values below `1` are clamped to `1`.
    ///   - particleLifetime: Seconds before a particle expires. Defaults to `1`.
    ///     Values below `0.1` are clamped to `0.1`.
    /// - Returns: A particle system with no active particles.
    /// - Throws: This initializer does not throw.
    public init(
        particleDiameter: CGFloat = 44,
        emissionSpacing: CGFloat = 4,
        particleLifetime: TimeInterval = 1
    ) {
        self.particleDiameter = max(1, particleDiameter)
        self.emissionSpacing = max(1, emissionSpacing)
        self.particleLifetime = max(0.1, particleLifetime)
    }

    /// Removes particles older than ``particleLifetime``.
    ///
    /// - Parameter date: The current animation timeline reference date.
    /// This method does not return a value. It mutates ``particles`` in place.
    /// - Throws: This method does not throw.
    public func update(date: TimeInterval) {
        let deathDate = date - particleLifetime
        particles = particles.filter { $0.creationDate >= deathDate }
    }

    /// Clears the previous interpolation anchor without removing visible particles.
    ///
    /// This method does not return a value. It prevents a future stroke from
    /// interpolating back to the last point in a completed stroke.
    /// - Throws: This method does not throw.
    public func resetTrail() {
        lastEmissionPoint = nil
    }

    /// Adds a particle trail segment ending at a grid-local point.
    ///
    /// - Parameter location: The point in the grid canvas coordinate space.
    /// This method does not return a value. It inserts one or more interpolated
    /// particles into ``particles`` so fast drag updates render as a continuous
    /// trail instead of a dotted path.
    /// - Throws: This method does not throw.
    public func addParticle(at location: CGPoint) {
        let creationDate = Date.now.timeIntervalSinceReferenceDate
        defer { lastEmissionPoint = location }

        guard let lastEmissionPoint else {
            insertParticle(at: location, creationDate: creationDate)
            return
        }

        let distance = hypot(location.x - lastEmissionPoint.x, location.y - lastEmissionPoint.y)
        guard distance > emissionSpacing, emissionSpacing > 0 else {
            insertParticle(at: location, creationDate: creationDate)
            return
        }

        let steps = max(1, Int(ceil(distance / emissionSpacing)))
        for step in 1 ... steps {
            let progress = CGFloat(step) / CGFloat(steps)
            let interpolatedPoint = CGPoint(
                x: lastEmissionPoint.x + (location.x - lastEmissionPoint.x) * progress,
                y: lastEmissionPoint.y + (location.y - lastEmissionPoint.y) * progress
            )
            insertParticle(at: interpolatedPoint, creationDate: creationDate)
        }
    }

    /// Inserts a single particle without altering interpolation state.
    ///
    /// - Parameters:
    ///   - location: The grid canvas coordinate where the particle is rendered.
    ///   - creationDate: The reference date used for particle aging.
    /// This method does not return a value. It mutates ``particles``.
    /// - Throws: This method does not throw.
    private func insertParticle(at location: CGPoint, creationDate: TimeInterval) {
        let newParticle = Particle(x: location.x, y: location.y, creationDate: creationDate)
        particles.insert(newParticle)
    }
}

/// Probes bundled resources in tests without exposing resource details publicly.
enum PatternAuthenticationResourceProbe {
    /// Whether the SwiftPM bundle can resolve the spark image resource.
    ///
    /// - Returns: `true` when the resource exists on UIKit platforms. Non-UIKit
    ///   platforms return `true` because image probing is unavailable there.
    @MainActor
    static var sparkImageExists: Bool {
        #if canImport(UIKit)
        UIImage(named: "spark", in: .module, compatibleWith: nil) != nil
        #else
        true
        #endif
    }
}
