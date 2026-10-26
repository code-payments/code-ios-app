extension DialogItem {

    /// Red banner error dialog. Reports an analytics event when displayed.
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

    /// Red banner dialog without analytics tracking.
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

    /// Grey banner informational dialog.
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

    /// Green banner success dialog. Defaults to `dismissable: false`.
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

extension DialogItem {

    /// Grey sheet of actions with no banner text, or with an optional heading, for an overflow menu.
    public static func options(
        title: String? = nil,
        subtitle: String? = nil,
        @ActionBuilder actions: () -> [DialogAction]
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
