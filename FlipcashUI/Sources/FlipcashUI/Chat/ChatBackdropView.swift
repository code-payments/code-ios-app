//
//  ChatBackdropView.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import SwiftUI
import UIKit

/// ``ChatBackdrop``'s frosting and dim as a SwiftUI view, for chat surfaces drawn in SwiftUI that
/// sit over the transcript the way a long-pressed message's menu does. Fade it with `opacity`.
public struct ChatBackdropView: UIViewRepresentable {

    public init() {}

    public func makeUIView(context: Context) -> UIVisualEffectView {
        let effectView = UIVisualEffectView(effect: nil)
        effectView.isUserInteractionEnabled = false

        let dim = UIView()
        dim.backgroundColor = .black
        dim.alpha = ChatBackdrop.dimAlpha
        dim.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dim.frame = effectView.contentView.bounds
        effectView.contentView.addSubview(dim)

        context.coordinator.strength = ChatBackdrop.frost(effectView)
        return effectView
    }

    public func updateUIView(_ view: UIVisualEffectView, context: Context) {}

    public static func dismantleUIView(_ view: UIVisualEffectView, coordinator: Coordinator) {
        coordinator.strength?.stopAnimation(true)
        coordinator.strength = nil
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    /// Holds the blur at ``ChatBackdrop/blurFraction`` until the view is dismantled — see
    /// ``ChatBackdrop/frost(_:fraction:)``.
    @MainActor
    public final class Coordinator {
        var strength: UIViewPropertyAnimator?
    }
}
#endif
