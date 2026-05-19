extension DialogItem {

    /// Tracked error display. Fires `Error Modal Displayed` analytics when
    /// presented (via the app target's `.trackedDialog` modifier). Red banner.
    /// Maps to Android's `BottomBarManager.showError(...)`.
    public static func error(
        title: String,
        subtitle: String,
        @ActionBuilder actions: () -> [DialogAction] = { [.okay(kind: .destructive)] }
    ) -> DialogItem {
        DialogItem(
            style: .destructive,
            title: title,
            subtitle: subtitle,
            dismissable: true,
            tracked: true,
            actions: actions
        )
    }

    /// Untracked alert. Same red banner as `.error`, deliberately excluded from
    /// analytics. Use for user-cancelled flows and validation feedback. Maps
    /// to Android's `BottomBarManager.showAlert(...)`.
    public static func alert(
        title: String,
        subtitle: String,
        @ActionBuilder actions: () -> [DialogAction] = { [.okay(kind: .destructive)] }
    ) -> DialogItem {
        DialogItem(
            style: .destructive,
            title: title,
            subtitle: subtitle,
            dismissable: true,
            tracked: false,
            actions: actions
        )
    }

    /// Untracked informational dialog. Grey banner. Use for onboarding nudges
    /// and non-error confirmations.
    public static func info(
        title: String,
        subtitle: String,
        @ActionBuilder actions: () -> [DialogAction] = { [.okay(kind: .standard)] }
    ) -> DialogItem {
        DialogItem(
            style: .standard,
            title: title,
            subtitle: subtitle,
            dismissable: true,
            tracked: false,
            actions: actions
        )
    }
}
