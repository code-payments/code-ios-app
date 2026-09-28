//
//  UnreadCountLabel.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// The text every unread count shows — chat row pill, tab badge, unread divider — capped at "99+"
/// as Android shows it.
public enum UnreadCountLabel {

    /// The largest count drawn as a number; anything above it reads "99+".
    public static let cap = 99

    /// `count` as a number up to `cap`, and "99+" above it.
    public static func text(for count: Int) -> String {
        count > cap ? "\(cap)+" : "\(count)"
    }
}
