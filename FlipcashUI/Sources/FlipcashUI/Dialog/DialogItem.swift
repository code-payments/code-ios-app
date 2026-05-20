import Foundation

public struct DialogItem: Identifiable {

    public let id: UUID
    public let style: Dialog.Style
    public let title: String?
    public let subtitle: String?
    public let dismissable: Bool
    public let actions: [DialogAction]
    public let tracked: Bool

    init(
        style: Dialog.Style,
        title: String?,
        subtitle: String?,
        dismissable: Bool,
        tracked: Bool,
        @ActionBuilder actions: () -> [DialogAction]
    ) {
        self.id          = UUID()
        self.style       = style
        self.title       = title
        self.subtitle    = subtitle
        self.dismissable = dismissable
        self.tracked     = tracked
        self.actions     = actions()
    }
}
