//
//  UnreadBadgeText.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// The text on the jump-to-bottom button's unread badge. Android caps at the same value.
public enum UnreadBadgeText {
    /// The largest count shown as a number; anything above reads "99+".
    public static let cap = 99

    /// The badge text for `count`, or nil when the badge is hidden (nothing unread).
    public static func text(for count: Int) -> String? {
        guard count > 0 else { return nil }
        return count > cap ? "\(cap)+" : "\(count)"
    }
}
