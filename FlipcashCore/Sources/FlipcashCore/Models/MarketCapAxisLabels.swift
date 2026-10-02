//
//  MarketCapAxisLabels.swift
//  FlipcashCore
//

import Foundation

/// Which axis labels the Market Cap slider draws, and where.
public enum MarketCapAxisLabels {

    /// The minimum clear space between two drawn labels.
    public static let labelGap: CGFloat = 6

    /// A labeled tick, with its label's measured width (nil until measured).
    public struct Item: Equatable {
        public let id: Foundation.Decimal
        /// The tick's position along the track, 0...1.
        public let position: Double
        public let width: CGFloat?
        public let isToday: Bool

        public init(id: Foundation.Decimal, position: Double, width: CGFloat?, isToday: Bool) {
            self.id = id
            self.position = position
            self.width = width
            self.isToday = isToday
        }
    }

    /// Center x for each label that gets drawn, from measured widths. Labels are
    /// clamped inside the track, Today always draws, and a fixed label whose frame
    /// would come within ``labelGap`` of one already drawn is dropped (its tick stays).
    public static func layout(_ items: [Item], trackWidth: CGFloat) -> [Foundation.Decimal: CGFloat] {
        func frame(_ item: Item) -> (center: CGFloat, half: CGFloat)? {
            guard let measured = item.width else { return nil }
            let half = measured / 2
            return (min(max(trackWidth * item.position, half), max(trackWidth - half, half)), half)
        }
        var drawn: [(center: CGFloat, half: CGFloat)] = []
        var result: [Foundation.Decimal: CGFloat] = [:]
        let ordered = items.sorted { $0.isToday && !$1.isToday }
        for item in ordered {
            guard let f = frame(item) else { continue }
            let collides = drawn.contains { abs($0.center - f.center) < $0.half + f.half + labelGap }
            if collides && !item.isToday { continue }
            drawn.append(f)
            result[item.id] = f.center
        }
        return result
    }
}
