extension DialogItem {

    /// Tracked error display. Fires `Error Modal Displayed` analytics when
    /// presented (via the app target's `.trackedDialog` modifier). Red banner.
    /// Maps to Android's `BottomBarManager.showError(...)`.
    public static func error(
        title: String,
        subtitle: String,
        dismissable: Bool = true,
        @ActionBuilder actions: () -> [DialogAction] = { [.okay(kind: .destructive)] }
    ) -> DialogItem {
        DialogItem(
            style: .destructive,
            title: title,
            subtitle: subtitle,
            dismissable: dismissable,
            tracked: true,
            actions: actions
        )
    }

    /// Untracked alert. Same red banner as `.error`, deliberately excluded from
    /// analytics. Use for user-cancelled flows, confirmations, and validation
    /// feedback. Maps to Android's `BottomBarManager.showAlert(...)`.
    public static func alert(
        title: String,
        subtitle: String,
        dismissable: Bool = true,
        @ActionBuilder actions: () -> [DialogAction] = { [.okay(kind: .destructive)] }
    ) -> DialogItem {
        DialogItem(
            style: .destructive,
            title: title,
            subtitle: subtitle,
            dismissable: dismissable,
            tracked: false,
            actions: actions
        )
    }

    /// Untracked informational dialog. Grey banner. Use for onboarding nudges
    /// and non-error informational messages.
    public static func info(
        title: String,
        subtitle: String,
        dismissable: Bool = true,
        @ActionBuilder actions: () -> [DialogAction] = { [.okay(kind: .standard)] }
    ) -> DialogItem {
        DialogItem(
            style: .standard,
            title: title,
            subtitle: subtitle,
            dismissable: dismissable,
            tracked: false,
            actions: actions
        )
    }

    /// Untracked success dialog. Green banner. Defaults to `dismissable: false`
    /// — success modals typically require explicit acknowledgement.
    public static func success(
        title: String,
        subtitle: String,
        dismissable: Bool = false,
        @ActionBuilder actions: () -> [DialogAction] = { [.okay(kind: .standard)] }
    ) -> DialogItem {
        DialogItem(
            style: .success,
            title: title,
            subtitle: subtitle,
            dismissable: dismissable,
            tracked: false,
            actions: actions
        )
    }
}
