import Foundation

public struct DialogItem: Identifiable {

    public let id: UUID
    public let style: Dialog.Style
    public let title: String?
    public let subtitle: String?
    public let dismissable: Bool
    public let actions: [DialogAction]
    public let tracked: Bool

    /// Runs when the dialog leaves the screen by any means — an action button,
    /// the Cancel button, or a scrim tap — so callers can tear down state the
    /// dialog was fronting regardless of how the user dismissed it.
    public let onDismiss: (() -> Void)?

    init(
        style: Dialog.Style,
        title: String?,
        subtitle: String?,
        dismissable: Bool,
        tracked: Bool,
        onDismiss: (() -> Void)? = nil,
        @ActionBuilder actions: () -> [DialogAction]
    ) {
        self.id          = UUID()
        self.style       = style
        self.title       = title
        self.subtitle    = subtitle
        self.dismissable = dismissable
        self.tracked     = tracked
        self.onDismiss   = onDismiss
        self.actions     = actions()
    }

    /// Returns a copy that runs `handler` on dismissal, in addition to any
    /// existing handler.
    public func onDismiss(perform handler: @escaping () -> Void) -> DialogItem {
        let existing = onDismiss
        return DialogItem(
            style: style,
            title: title,
            subtitle: subtitle,
            dismissable: dismissable,
            tracked: tracked,
            onDismiss: { existing?(); handler() },
            actions: { actions }
        )
    }
}
