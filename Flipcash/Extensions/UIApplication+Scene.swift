//
//  UIApplication+Scene.swift
//  Flipcash
//

import UIKit

/// Resolves a single "current" window/scene from `UIApplication`.
///
/// Unambiguous only while the app is single-scene
/// (`UIApplicationSupportsMultipleScenes` is `false`, iPhone-only). Under true
/// multi-window (iPad/visionOS/Stage Manager) `connectedScenes` is an unordered
/// `Set` with possibly several `.foregroundActive` scenes, so each accessor
/// returns an arbitrary one — derive the scene from view/interaction context
/// instead.
extension UIApplication {
    /// The first connected `UIWindowScene`, regardless of activation state.
    ///
    /// Prefer this during early lifecycle (e.g. `onAppear` on cold launch),
    /// when a scene may have connected but not yet reached `.foregroundActive`.
    var firstWindowScene: UIWindowScene? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
    }


    /// The key window across all connected scenes.
    var currentKeyWindow: UIWindow? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }
}
