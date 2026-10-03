//
//  FloatingToast.swift
//  FlipcashUI
//

import SwiftUI

/// The undo-toast design shared with Android: a pill on the tab bar's glass with an optional leading icon and an
/// optional trailing action. A longer message wraps. The caller owns placement, lifetime and transitions.
public struct FloatingToast: View {

    /// How wide the pill is drawn. Either way it is never wider than the floating tab bar.
    public enum Width {
        /// As wide as the floating tab bar, or 12pt from each screen edge when no bar shows.
        case fill
        /// Hugs its content.
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

    @Environment(\.floatingTabBar) private var tabBar

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
        // The floating tab bar's surface, so a toast growing out of the bar reads as part of it.
        .capsuleGlassBackground()
        .padding(.horizontal, tabBar?.horizontalInset ?? 12)
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

// MARK: - Tab bar -

/// The floating tab bar a toast sits above, published by the screen that draws the bar.
public struct FloatingTabBar: Equatable, Sendable {
    /// The bar's inset from each screen edge.
    public let horizontalInset: CGFloat

    /// A bar inset `horizontalInset` from each screen edge.
    public init(horizontalInset: CGFloat) {
        self.horizontalInset = horizontalInset
    }
}

extension EnvironmentValues {
    /// The floating tab bar below this view, or `nil` when none is showing.
    @Entry public var floatingTabBar: FloatingTabBar? = nil
}

extension View {
    /// Brings a bottom-anchored toast in out of the floating tab bar when one is showing, and up
    /// from the bottom edge of the screen when not.
    public func floatingToastTransition() -> some View {
        modifier(FloatingToastTransition())
    }
}

private struct FloatingToastTransition: ViewModifier {
    @Environment(\.floatingTabBar) private var tabBar

    func body(content: Content) -> some View {
        content.transition(tabBar == nil ? Self.fromScreenEdge : Self.fromTabBar)
    }

    private static let fromScreenEdge: AnyTransition = .move(edge: .bottom).combined(with: .opacity)

    /// Starts tucked behind the bar, which draws over the screen's content, and swells up out of it.
    private static let fromTabBar: AnyTransition = .modifier(
        active: TabBarEmergence(progress: 0),
        identity: TabBarEmergence(progress: 1)
    )
}

private struct TabBarEmergence: ViewModifier {
    let progress: CGFloat

    func body(content: Content) -> some View {
        content
            .scaleEffect(x: 0.92 + 0.08 * progress, y: 0.5 + 0.5 * progress, anchor: .bottom)
            .offset(y: 56 * (1 - progress))
            .blur(radius: 6 * (1 - progress))
            .opacity(progress)
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
