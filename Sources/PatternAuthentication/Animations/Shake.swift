//
//  Shake.swift
//
//
//  Created by Shain Mack on 9/17/24.
//

import SwiftUI

/// A horizontal shake effect used to signal failed gesture attempts.
public struct Shake: GeometryEffect {
    /// The maximum horizontal translation in points.
    public var amount: CGFloat = 10

    /// The number of shake oscillations per animation unit.
    public var shakesPerUnit = 3

    /// The animatable value that advances the shake.
    public var animatableData: CGFloat

    /// Creates a shake geometry effect.
    ///
    /// - Parameters:
    ///   - amount: Maximum horizontal translation in points. Defaults to `10`.
    ///   - shakesPerUnit: Number of oscillations per animation unit. Defaults
    ///     to `3`.
    ///   - animatableData: The animatable progress value. Defaults to `0`.
    /// - Returns: A geometry effect that translates content horizontally.
    /// - Throws: This initializer does not throw.
    public init(
        amount: CGFloat = 10,
        shakesPerUnit: Int = 3,
        animatableData: CGFloat = 0
    ) {
        self.amount = amount
        self.shakesPerUnit = shakesPerUnit
        self.animatableData = animatableData
    }

    /// Calculates the translation transform for the current shake progress.
    ///
    /// - Parameter size: The size of the affected view. The shake effect does
    ///   not depend on this value.
    /// - Returns: A projection transform that translates the view on the x-axis.
    /// - Throws: This method does not throw.
    public func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX:
            amount * sin(animatableData * .pi * CGFloat(shakesPerUnit)),
            y: 0))
    }
}
