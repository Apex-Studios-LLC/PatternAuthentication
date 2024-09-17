//
//  File.swift
//  
//
//  Created by Shain Mack on 9/17/24.
//
import SwiftUI
import CryptoKit

public struct Particle: Hashable {
    public let x: Double
    public let y: Double
    public let creationDate = Date.now.timeIntervalSinceReferenceDate
}

public class ParticleSystem {
    public let image = Image("spark", bundle: Bundle.module)
    public var particles = Set<Particle>()
    public var center = UnitPoint.center
    
    public func update(date: TimeInterval) {
        let deathDate = date - 1
        
        for particle in particles {
            if particle.creationDate < deathDate {
                particles.remove(particle)
            }
        }
    }
    
    public func addParticle(at location: CGPoint) {
        let newParticle = Particle(x: center.x, y: center.y)
        particles.insert(newParticle)
    }
}

public func hashArray(_ array: [Int]) -> String {
    let data = array.withUnsafeBytes { Data($0) }
    let hash = SHA256.hash(data: data)
    return hash.compactMap { String(format: "%02x", $0) }.joined()
}
