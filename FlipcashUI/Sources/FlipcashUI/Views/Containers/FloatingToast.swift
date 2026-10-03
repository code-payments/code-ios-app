//
//  FloatingToast.swift
//  FlipcashUI
//

import SwiftUI

/// The undo-toast design shared with Android: a frosted pill with an optional leading icon and an
/// optional trailing action. A longer message wraps. The caller owns placement, lifetime and transitions.
public struct FloatingToast: View {

    /// How wide the pill is drawn.
    public enum Width {
        /// Spans the screen, inset 12pt from each edge, as the shared design specifies.
        case fill
        /// Hugs its content, never wider than the floating tab bar.
        case fit
    }

    /// A trailing button drawn in its own pill.
    public struct Action {
        let title: String
        let accessibilityIdentifier: String?
        let handler: () -> Void

        /// An action titled `title` that runs `handler` when tapped.
        public init(_ title: String, accessibilityIdentifier: String? = nil, handler: @escaping () -> Void) {
            self.title = title
            self.accessibilityIdentifier = accessibilityIdentifier
            self.handler = handler
        }
    }

    private let message: String
    private let systemImage: String?
    private let messageIdentifier: String?
    private let action: Action?
    private let width: Width
    private let onDismiss: (() -> Void)?

    @State private var dragOffset: CGFloat = 0

    /// The native floating tab bar's inset from each screen edge, measured on iOS 26; keeping the
    /// same inset caps a `.fit` toast at the bar's width.
    private static let tabBarInset: CGFloat = 21

    /// A toast showing `message`; a swipe down calls `onDismiss` when one is given.
    ///
    /// `messageIdentifier` lands on the message text alone, so UI tests can match it as static text.
    public init(
        _ message: String,
        systemImage: String? = nil,
        messageIdentifier: String? = nil,
        action: Action? = nil,
        width: Width = .fill,
        onDismiss: (() -> Void)? = nil
    ) {
        self.message = message
        self.systemImage = systemImage
        self.messageIdentifier = messageIdentifier
        self.action = action
        self.width = width
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(spacing: 10) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 18))
                    .foregroundStyle(Color.textSecondary)
                    .accessibilityHidden(true)
            }
            Text(message)
                .font(.default(size: 14, weight: .medium))
                .foregroundStyle(Color.textMain)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(messageIdentifier ?? "")
            if width == .fill {
                Spacer(minLength: 0)
            }
            if let action {
                Button(action: action.handler) {
                    Text(action.title)
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textMain)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.12), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(action.accessibilityIdentifier ?? "")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, action == nil ? 16 : 8)
        .padding(.vertical, 8)
        // The height a one-line toast has with an action, so toasts without one match it.
        .frame(minHeight: 44)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        .padding(.horizontal, width == .fill ? 12 : Self.tabBarInset)
        .offset(y: dragOffset)
        .gesture(dismissGesture, isEnabled: onDismiss != nil)
    }

    private var dismissGesture: some Gesture {
        DragGesture()
            .onChanged { dragOffset = max(0, $0.translation.height) }
            .onEnded { value in
                if value.translation.height > 24 || value.predictedEndTranslation.height > 60 {
                    onDismiss?()
                } else {
                    withAnimation(.spring) { dragOffset = 0 }
                }
            }
    }
}

// MARK: - Previews -

#Preview {
    VStack(spacing: 16) {
        FloatingToast("Chat archived", systemImage: "archivebox", action: .init("Undo") {})
        FloatingToast("You are now 3 steps away from being a developer", width: .fit)
    }
    .frame(maxHeight: .infinity)
    .background(Color.backgroundMain)
}
