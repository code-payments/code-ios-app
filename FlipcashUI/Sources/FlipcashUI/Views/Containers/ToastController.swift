//
//  ToastController.swift
//  FlipcashUI
//

import SwiftUI
import UIKit
import Observation

/// The app-wide toast: any screen dispatches one, and a single host draws it above the floating tab bar,
/// or at the bottom edge of the screen when no bar shows. One toast shows at a time; a new one replaces it.
@MainActor
@Observable
public final class ToastController {

    /// A toast to show. A toast with an action takes touches and dismisses on a swipe down; one without
    /// lets touches through to the screen beneath it.
    public struct Toast: Identifiable {
        public let id = UUID()
        // Shared by toasts swapped in place, so the host keeps the view rather than replaying the entrance.
        fileprivate(set) var slot = UUID()
        let message: String
        let systemImage: String?
        let messageIdentifier: String?
        let action: FloatingToast.Action?
        let width: FloatingToast.Width
        let duration: Duration

        /// A toast showing `message` for `duration`, then dismissing itself.
        ///
        /// `messageIdentifier` lands on the message text alone, so UI tests can match it as static text.
        public init(
            _ message: String,
            systemImage: String? = nil,
            messageIdentifier: String? = nil,
            action: FloatingToast.Action? = nil,
            width: FloatingToast.Width = .fill,
            duration: Duration = .seconds(4)
        ) {
            self.message = message
            self.systemImage = systemImage
            self.messageIdentifier = messageIdentifier
            self.action = action
            self.width = width
            self.duration = duration
        }
    }

    /// The toast on screen, or `nil` when none is.
    public private(set) var current: Toast?

    /// Whether a sheet or other modal layer is drawn over the host. Covering dismisses the toast on screen,
    /// and a toast shown while covered is dropped: hidden beneath the layer it would time out unseen, with
    /// its action out of reach.
    public var isCovered = false {
        didSet { if isCovered { current = nil } }
    }

    /// Extra room the toast keeps above the host's bottom edge, for a bar a screen pins there. Set
    /// through ``View/toastClearance(_:)``.
    public var bottomClearance: CGFloat = 0

    /// A controller with no toast showing.
    public init() {}

    /// Shows `toast` in place of any toast already up, and announces it to VoiceOver. Drops it while the
    /// host is covered.
    ///
    /// With `inPlace`, a toast already up swaps its content without replaying the entrance, for a message
    /// that updates as the user acts (a countdown). Its timer still restarts.
    public func show(_ toast: Toast, inPlace: Bool = false) {
        guard !isCovered, !Self.isPresentingOverApp else { return }
        var toast = toast
        if inPlace, let current { toast.slot = current.slot }
        current = toast
        AccessibilityNotification.Announcement(toast.message).post()
    }

    /// Dismisses the toast identified by `id`, if it is still the one showing.
    public func dismiss(_ id: Toast.ID) {
        guard current?.id == id else { return }
        current = nil
    }

    // Catches sheets and dialogs presented outside the router, which never set `isCovered`.
    private static var isPresentingOverApp: Bool {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController?
            .presentedViewController != nil
    }
}

extension View {
    /// Draws `controller`'s toast at the bottom of this view, `bottomPadding` above its safe area, while
    /// `isEnabled`.
    ///
    /// Place it where the safe area already ends at the floating tab bar, and where `\.floatingTabBar`
    /// says whether that bar is showing.
    public func toastHost(
        _ controller: ToastController,
        bottomPadding: CGFloat = 12,
        isEnabled: Bool = true
    ) -> some View {
        overlay(alignment: .bottom) {
            if isEnabled {
                ToastHost(controller: controller, bottomPadding: bottomPadding)
            }
        }
    }
}

extension View {
    /// Raises `controller`'s toast above this view, measured, for as long as it is on screen. Put it on
    /// a bar a screen pins to the bottom edge, so a toast doesn't draw over it.
    public func toastClearance(_ controller: ToastController) -> some View {
        modifier(ToastClearance(controller: controller))
    }
}

private struct ToastClearance: ViewModifier {
    let controller: ToastController
    @State private var height: CGFloat = 0
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { newValue in
                height = newValue
                if isVisible { controller.bottomClearance = newValue }
            }
            .onAppear {
                isVisible = true
                controller.bottomClearance = height
            }
            .onDisappear {
                isVisible = false
                controller.bottomClearance = 0
            }
    }
}

private struct ToastHost: View {
    let controller: ToastController
    let bottomPadding: CGFloat

    var body: some View {
        ZStack {
            if let toast = controller.current {
                FloatingToast(
                    toast.message,
                    systemImage: toast.systemImage,
                    messageIdentifier: toast.messageIdentifier,
                    action: toast.action.map { action in
                        .init(action.title, accessibilityIdentifier: action.accessibilityIdentifier) {
                            action.handler()
                            controller.dismiss(toast.id)
                        }
                    },
                    width: toast.width,
                    onDismiss: toast.action == nil ? nil : { controller.dismiss(toast.id) }
                )
                .allowsHitTesting(toast.action != nil)
                .padding(.bottom, bottomPadding + controller.bottomClearance)
                .floatingToastTransition()
                .id(toast.slot)
                .task(id: toast.id) {
                    try? await Task.sleep(for: toast.duration)
                    if !Task.isCancelled { controller.dismiss(toast.id) }
                }
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.2), value: controller.current?.slot)
    }
}
