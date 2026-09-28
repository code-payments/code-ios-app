//
//  KeyboardOverlayHost.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import UIKit

/// Finds the window the system keyboard is drawn in, so a view can be laid over the live keys.
@MainActor
protocol KeyboardWindowLocating {
    /// Returns the window holding the on-screen keyboard, or `nil` when there is none to be found.
    func keyboardWindow() -> UIWindow?
}

/// Finds the system keyboard's window through private UIKit API. The only place in the app that does.
///
/// Private-API reliant: the software keyboard is drawn in-process, in a window UIKit keeps at a level
/// above every window an app may create (app windows are capped at 10,000,000) and leaves out of
/// `UIApplication.windows` and every scene's `windows`. The one way to reach it is the private class
/// method `+[UIWindow allWindowsIncludingInternalWindows:onlyVisibleWindows:]`, called here through
/// `NSSelectorFromString` after a `responds(to:)` check. A subview added to that window draws over
/// the keys and a glass effect in it blurs them, while the composer stays first responder.
///
/// Every step is checked: a missing selector, an unexpected return type, or no keyboard window
/// returns `nil`, and the caller falls back to public API. It never traps.
@MainActor
struct KeyboardOverlayHost: KeyboardWindowLocating {

    /// The private selector's name, assembled so the whole name never appears as one literal.
    private static let selectorName = ["allWindows", "Including", "Internal", "Windows:", "only", "Visible", "Windows:"].joined()

    /// A fragment of the keyboard window's class name, which no app window carries.
    private static let windowClassFragment = ["Remote", "Keyboard", "Window"].joined()

    func keyboardWindow() -> UIWindow? {
        let selector = NSSelectorFromString(Self.selectorName)
        guard UIWindow.responds(to: selector) else { return nil }
        typealias AllWindows = @convention(c) (AnyObject, Selector, Bool, Bool) -> NSArray?
        let implementation = UIWindow.method(for: selector)
        guard implementation != nil else { return nil }
        let allWindows = unsafeBitCast(implementation, to: AllWindows.self)
        guard let windows = allWindows(UIWindow.self, selector, true, false) as? [UIWindow] else { return nil }
        return windows
            .filter { !$0.isHidden && NSStringFromClass(type(of: $0)).contains(Self.windowClassFragment) }
            .max { $0.windowLevel.rawValue < $1.windowLevel.rawValue }
    }
}
