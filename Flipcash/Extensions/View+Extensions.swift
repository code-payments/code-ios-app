//
//  View+Extensions.swift
//  Code
//
//  Created by Raul Riera on 2026-03-25.
//

import SwiftUI

extension View {
    /// Applies the given transform or returns the untransformed view.
    ///
    /// Useful for availability branching on view modifiers. Do not branch with any properties that may change during runtime as this will cause errors.
    /// - Parameters:
    ///   - transform: The transform to apply to the source `View`.
    /// - Returns: The view transformed by the transform.
    /// - Warning: Only use if #available branching inside to ensure no runtime changes
    @ViewBuilder
    public func ifAvailable(@ViewBuilder _ transform: (Self) -> (some View)?) -> some View {
        if let transformed = transform(self) {
            transformed
        } else {
            self
        }
    }
}
