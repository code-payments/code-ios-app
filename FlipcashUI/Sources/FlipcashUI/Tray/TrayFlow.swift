//
//  TrayFlow.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Observation

/// The steps of one tray flow and the direction of the last move, which drive the back control
/// and the step transition.
@Observable @MainActor
public final class TrayFlow<Step: Hashable> {

    /// Which way the flow last moved.
    public enum Direction: Sendable {
        case forward
        case back
    }

    /// The steps from the root to the current one; never empty.
    public private(set) var path: [Step]

    /// Which way the flow last moved: forward for a push, back for a pop.
    public private(set) var direction: Direction = .forward

    /// The step on screen.
    public var current: Step { path[path.count - 1] }

    /// Whether there is a step to go back to.
    public var canGoBack: Bool { path.count > 1 }

    /// Creates a flow showing `root`.
    public init(root: Step) {
        path = [root]
    }

    /// Moves forward to `step`.
    public func push(_ step: Step) {
        direction = .forward
        path.append(step)
    }

    /// Returns to the previous step; does nothing on the root.
    public func back() {
        guard canGoBack else { return }
        direction = .back
        path.removeLast()
    }

    /// Does what the tray's X does: goes back a step, or calls `dismiss` on the root.
    public func close(dismiss: () -> Void) {
        if canGoBack {
            back()
        } else {
            dismiss()
        }
    }
}
