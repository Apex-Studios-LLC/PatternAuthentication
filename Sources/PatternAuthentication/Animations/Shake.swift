//
//  Shake.swift
//
//
//  Created by Shain Mack on 9/17/24.
//

import SwiftUI

public struct Shake: GeometryEffect {
    public var amount: CGFloat = 10
    public var shakesPerUnit = 3
    public var animatableData: CGFloat

    public func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX:
            amount * sin(animatableData * .pi * CGFloat(shakesPerUnit)),
            y: 0))
    }
}
