//
//  EasedStops.swift
//  FlipcashUI
//

import SwiftUI

/// Gradient stops that fade a color in along a smootherstep curve, so there is no visible band
/// where the ramp meets the flat color the way a two-stop linear gradient shows one.
nonisolated enum EasedStops {

    /// Stops that take `color` from 0% opacity at `start` to 100% at `end`, both 0…1 along the gradient.
    static func fade(to color: Color, start: Double = 0, end: Double = 1, count: Int = 14) -> [Gradient.Stop] {
        let start = min(max(start, 0), 1)
        let end = max(min(max(end, 0), 1), start + 0.001)
        var stops: [Gradient.Stop] = []
        if start > 0 { stops.append(.init(color: color.opacity(0), location: 0)) }
        for index in 0...count {
            let t = Double(index) / Double(count)
            stops.append(.init(color: color.opacity(smootherstep(t)), location: start + (end - start) * t))
        }
        if end < 1 { stops.append(.init(color: color, location: 1)) }
        return stops
    }

    /// The smootherstep ease of `t`, clamped to 0…1.
    static func smootherstep(_ t: Double) -> Double {
        let t = min(max(t, 0), 1)
        return t * t * t * (t * (t * 6 - 15) + 10)
    }
}
