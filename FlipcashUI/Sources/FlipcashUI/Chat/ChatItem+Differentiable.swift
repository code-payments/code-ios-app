//
//  ChatItem+Differentiable.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import DifferenceKit
import FlipcashCore

/// Drives ChatLayout's canonical `reload(using:)` diffing: identity by `id` (stable across a
/// re-group or receipt change), content equality by value (so a changed bubble reconfigures).
extension ChatItem: Differentiable {
    public var differenceIdentifier: String { id }
    public func isContentEqual(to source: ChatItem) -> Bool { self == source }
}
