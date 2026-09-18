//
//  GroupInviteShareItem.swift
//  Flipcash
//

import UIKit
import LinkPresentation
import FlipcashCore

/// Shares a group's invite link with a one-line invitation ahead of it.
///
/// The sentence is payload rather than decoration. A group is not discoverable, so a link arriving
/// on its own gives the recipient nothing to judge it by; naming the group says what they are being
/// invited to before they tap.
///
/// AirDrop and Slack get the bare URL. Both render a link themselves and would otherwise show the
/// sentence as literal text beside it — the same split ``ShareCashLinkItem`` makes.
final class GroupInviteShareItem: NSObject, UIActivityItemSource {

    let url: URL

    private let content: String
    private let invitation: String?
    private let name: String?
    private let icon: UIImage?

    // MARK: - Init -

    /// - Parameters:
    ///   - url: the group's invite link.
    ///   - title: the group's name, or nil while it has none. Without one there is nothing to name,
    ///     so the share falls back to the bare link rather than a sentence with a hole in it —
    ///     the rule Android's invite follows.
    ///   - icon: the group's picture, for the share sheet's own preview card. Nil when the group
    ///     has none or its avatar hasn't loaded; the card then carries the name alone.
    init(url: URL, title: String?, icon: UIImage? = nil) {
        self.url  = url
        self.icon = icon

        let name: String?
        if let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
            name = trimmed
        } else {
            name = nil
        }

        let invitation = name.map { "Join \($0) on Flipcash and let's chat" }

        self.name       = name
        self.invitation = invitation
        self.content    = invitation.map { "\($0)\n\n\(url.absoluteString)" } ?? url.absoluteString

        super.init()
    }

    // MARK: - UIActivityItemSource -

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return ""
    }

    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        return invitation ?? ""
    }

    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        guard let activityType else {
            return content
        }

        switch activityType.rawValue {
        case "com.tinyspeck.chatlyio.share": // Slack
            return url
        default:
            break
        }

        switch activityType {
        case .airDrop:
            return url
        default:
            return content
        }
    }

    /// The card at the top of the share sheet, which the sender sees and the recipient never does.
    ///
    /// It names the group rather than repeating the invitation: the sentence already sits in the
    /// message below, and the card's job is to confirm *which* group is about to be handed out.
    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.originalURL = url
        metadata.url = url
        metadata.title = name ?? "Invite to Join Group"
        metadata.iconProvider = icon.map { NSItemProvider(object: $0) }
        return metadata
    }
}
