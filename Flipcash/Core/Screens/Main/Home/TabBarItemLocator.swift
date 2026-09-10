//
//  TabBarItemLocator.swift
//  Flipcash
//

import UIKit

/// Maps a point in a `UITabBar` back to the `HomeTab` whose item is under it.
///
/// UIKit exposes no API from a touch to a `UITabBarItem`, so this reads the
/// bar's item buttons (the `UIControl`s in its view tree) in left-to-right
/// order, which is the order the items were given in. Anything that does not
/// line up — a different button count, a point between items — resolves to
/// nil rather than guessing.
@MainActor
enum TabBarItemLocator {

    /// The item buttons' frames in the bar's coordinate space, left to right,
    /// one per item.
    ///
    /// iOS 26 draws every item twice — a plain copy and a selected copy the
    /// glass lens reveals — at the same frame, so buttons that share a frame
    /// collapse to one. Earlier systems have a single button per item.
    static func itemFrames(in bar: UITabBar) -> [CGRect] {
        var controls: [UIView] = []
        var queue = bar.subviews
        while !queue.isEmpty {
            let view = queue.removeFirst()
            if view is UIControl {
                controls.append(view)
            } else {
                queue.append(contentsOf: view.subviews)
            }
        }

        var frames: [CGRect] = []
        for control in controls where !control.isHidden && control.bounds.width > 0 {
            let frame = bar.convert(control.bounds, from: control)
            let isDuplicate = frames.contains { abs($0.midX - frame.midX) < 1 && abs($0.midY - frame.midY) < 1 }
            if !isDuplicate {
                frames.append(frame)
            }
        }
        return frames.sorted { $0.minX < $1.minX }
    }

    /// The tab whose item holds `point` (in the bar's coordinates), or nil
    /// when the bar's buttons do not pair up with `tabs` or none holds the point.
    ///
    /// iOS 26 lays the buttons out wider than their pitch — 114pt buttons every
    /// 85pt on a 402pt bar — so neighbours overlap and a press near a boundary
    /// falls inside two. The nearer centre wins, which is the item the press
    /// looks like it is on.
    static func tab(at point: CGPoint, in bar: UITabBar, tabs: [HomeTab]) -> HomeTab? {
        let frames = itemFrames(in: bar)
        guard frames.count == tabs.count else { return nil }

        let holding = frames.indices.filter { frames[$0].contains(point) }
        guard let index = holding.min(by: { abs(frames[$0].midX - point.x) < abs(frames[$1].midX - point.x) })
        else { return nil }

        return tabs[index]
    }
}
