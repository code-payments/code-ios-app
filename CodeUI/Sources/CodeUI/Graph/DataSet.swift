//
//  DataSet.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

public struct DataSet {
    
    public let trend: Trend
    
    public let points: [Double]
    public let baseline: Double?
    
    public let normalizedPoints: [Double]
    public let normalizedBaseline: Double?
    
    public let minY: Double
    public let maxY: Double
    
    public let height: Double
    
    /// If the computed height is smaller than the minimumHeight
    /// we'll need to compute the delta between the two so we
    /// can center the contents vertically
    public let heightScale: Double
    
    public var count: Int {
        points.count
    }
    
    // MARK: - Init -
    
    public init(candles: [CandlePoint], strategy: InterpolationStrategy, baseline: Double? = nil) {
        self.init(points: candles.interpolate(using: strategy), baseline: baseline)
    }
    
    public init(points: [Double], baseline: Double? = nil, minimumHeight: Double? = nil) {
        self.trend = Self.computeTrend(points: points, baseline: baseline)
        
        let (minY, maxY) = Self.computeMinMaxY(points: points, baseline: baseline)
        let computedHeight = maxY - minY
        
        let minHeight = minimumHeight ?? 0
        let height = max(computedHeight, minHeight)
        
        self.minY     = minY
        self.maxY     = maxY
        self.height   = height
        self.points   = points
        self.baseline = baseline
        
        if computedHeight < minHeight {
            heightScale = computedHeight / minHeight
        } else {
            heightScale = 1
        }
        
        self.normalizedPoints = points.normalize(in: height, minY: minY)
        self.normalizedBaseline = baseline?.normalize(in: height, minY: minY)        
    }
    
    // MARK: - Computations -
    
    func xInterval(in width: CGFloat) -> CGFloat? {
        guard normalizedPoints.count > 1 else {
            return nil
        }
        
        return width / CGFloat(normalizedPoints.count - 1)
    }
    
    func yOffset(in geometry: GeometryProxy) -> CGFloat {
        (geometry.size.height - (geometry.size.height * heightScale)) * -0.5
    }
    
    private static func computeTrend(points: [Double], baseline: Double?) -> Trend {
        guard let lastValue = points.last else {
            return .neutral
        }
        
        guard let baseline = baseline else {
            return .neutral
        }
        
        if lastValue == baseline {
            return .neutral
        } else if lastValue > baseline {
            return .positive
        } else {
            return .negative
        }
    }
    
    private static func computeMinMaxY(points: [Double], baseline: Double?) -> (min: Double, max: Double) {
        var minY: Double = .greatestFiniteMagnitude
        var maxY: Double = 0
        
        var pointsWithBaseline = points
        if let baseline = baseline {
            pointsWithBaseline.append(baseline)
        }
        
        pointsWithBaseline.forEach { point in
            if point < minY {
                minY = point
            }
            
            if point > maxY {
                maxY = point
            }
        }
        
        return (minY, maxY)
    }
    
    // MARK: - Subsets -
    
    func subset(in range: Range<Int>) -> DataSet {
        DataSet(
            points: Array(points[range]),
            baseline: baseline
        )
    }
}

// MARK: - Trend -

extension DataSet {
    public enum Trend {
        case neutral
        case positive
        case negative
    }
}

// MARK: - InterpolationStrategy -

extension DataSet {
    public enum InterpolationStrategy {
        case close
    }
}

// MARK: - Double -

extension Double {
    func normalize(in height: Double, minY: Double) -> Double {
        if height > 0 {
            return (self - minY) / height
        }
        return 0
    }
}

extension Array where Element == Double {
    func normalize(in height: Double, minY: Double) -> [Element] {
        map { $0.normalize(in: height, minY: minY) }
    }
}

// MARK: - CandlePoint -

public struct CandlePoint {
    
    public var open: Double
    public var high: Double
    public var low: Double
    public var close: Double
    
    public init(open: Double, high: Double, low: Double, close: Double) {
        self.open  = open
        self.high  = high
        self.low   = low
        self.close = close
    }
}

extension Array where Element == CandlePoint {
    func interpolate(using strategy: DataSet.InterpolationStrategy) -> [Double] {
        map { candle in
            switch strategy {
            case .close:
                return candle.close
            }
        }
    }
}
