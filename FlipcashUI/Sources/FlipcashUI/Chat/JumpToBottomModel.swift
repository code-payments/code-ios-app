//
//  JumpToBottomModel.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import Observation
import SwiftUI
import UIKit

/// What the jump-to-bottom button shows, set by ``ChatScreenViewController`` from the transcript and
/// read by the column the owner hosts beside the bar. The button is drawn in SwiftUI so it can move
/// on the same spring as the bar's `$` button.
@MainActor @Observable
public final class JumpToBottomModel {
    /// Whether the reader is off the bottom of a transcript whose opening scroll has landed.
    public var isVisible = false
    /// Inbound messages the reader hasn't seen; the badge hides at zero.
    public var unreadCount = 0
    /// Scrolls the transcript to its newest message.
    public var onTap: () -> Void = {}

    public init() {}
}

/// The jump-to-bottom button: ``JumpToBottomButton`` in a SwiftUI view, so its frost, badge and
/// hairline are the ones the UIKit control draws.
public struct JumpToBottomButtonView: UIViewRepresentable {

    public static let diameter: CGFloat = JumpToBottomButton.diameter

    public let unreadCount: Int
    public let action: () -> Void

    public init(unreadCount: Int, action: @escaping () -> Void) {
        self.unreadCount = unreadCount
        self.action = action
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public func makeUIView(context: Context) -> UIView {
        let button = JumpToBottomButton()
        let coordinator = context.coordinator
        button.addAction(UIAction { _ in coordinator.action() }, for: .touchUpInside)
        return button
    }

    public func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.action = action
        (view as? JumpToBottomButton)?.setUnreadCount(unreadCount)
    }

    public func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIView, context: Context) -> CGSize? {
        CGSize(width: Self.diameter, height: Self.diameter)
    }

    @MainActor public final class Coordinator {
        var action: () -> Void = {}
    }
}
#endif
