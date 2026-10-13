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

    /// A checkbox drawn between the subtitle and the actions, or `nil` for none.
    public let checkbox: DialogCheckbox?

    init(
        style: Dialog.Style,
        title: String?,
        subtitle: String?,
        dismissable: Bool,
        tracked: Bool,
        onDismiss: (() -> Void)? = nil,
        checkbox: DialogCheckbox? = nil,
        @ActionBuilder actions: () -> [DialogAction]
    ) {
        self.id          = UUID()
        self.style       = style
        self.title       = title
        self.subtitle    = subtitle
        self.dismissable = dismissable
        self.tracked     = tracked
        self.onDismiss   = onDismiss
        self.checkbox    = checkbox
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
            checkbox: checkbox,
            actions: { actions }
        )
    }

    /// Returns a copy with an unchecked checkbox labelled `label`; each action is told whether it
    /// was ticked when tapped.
    public func checkbox(_ label: String) -> DialogItem {
        DialogItem(
            style: style,
            title: title,
            subtitle: subtitle,
            dismissable: dismissable,
            tracked: tracked,
            onDismiss: onDismiss,
            checkbox: DialogCheckbox(label: label),
            actions: { actions }
        )
    }
}

/// A checkbox row inside a dialog. It starts unchecked each time the dialog is shown.
public struct DialogCheckbox: Equatable {

    /// The text beside the box.
    public let label: String

    public init(label: String) {
        self.label = label
    }
}
