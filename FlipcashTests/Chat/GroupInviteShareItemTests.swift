//
//  GroupInviteShareItemTests.swift
//  FlipcashTests
//

import Testing
import UIKit
import LinkPresentation
import Foundation
@testable import Flipcash

/// What a group invite carries into each destination: the invitation and the link, or the bare link
/// where the invitation would read as stray text.
@MainActor
@Suite("GroupInviteShareItem")
struct GroupInviteShareItemTests {

    private let url = URL(string: "https://app.flipcash.com/chat/6f9619ff-8b86-d011-b42d-00c04fc964ff")!

    private func item(title: String?, icon: UIImage? = nil) -> GroupInviteShareItem {
        GroupInviteShareItem(url: url, title: title, icon: icon)
    }

    private func metadata(_ item: GroupInviteShareItem) -> LPLinkMetadata? {
        item.activityViewControllerLinkMetadata(UIActivityViewController(activityItems: [item], applicationActivities: nil))
    }

    private func sharedText(_ item: GroupInviteShareItem, to activityType: UIActivity.ActivityType? = nil) -> Any? {
        item.activityViewController(UIActivityViewController(activityItems: [item], applicationActivities: nil), itemForActivityType: activityType)
    }

    @Test("A named group is invited to by name, above the link")
    func namedGroupCarriesTheInvitation() {
        let shared = sharedText(item(title: "Pizza Club")) as? String

        #expect(shared == "Join Pizza Club on Flipcash and let's chat\n\n\(url.absoluteString)")
    }

    @Test("A group with no name shares the bare link")
    func unnamedGroupSharesTheLinkAlone() {
        // Naming nothing reads worse than naming nothing explicitly: "Join  on Flipcash" is a
        // sentence with a hole in it, so the invitation is dropped whole. Android's rule too.
        #expect(sharedText(item(title: nil)) as? String == url.absoluteString)
        #expect(sharedText(item(title: "")) as? String == url.absoluteString)
        #expect(sharedText(item(title: "   ")) as? String == url.absoluteString)
    }

    @Test("Surrounding whitespace doesn't reach the message")
    func titleIsTrimmed() {
        let shared = sharedText(item(title: "  Pizza Club\n")) as? String

        #expect(shared == "Join Pizza Club on Flipcash and let's chat\n\n\(url.absoluteString)")
    }

    @Test("AirDrop and Slack receive the URL itself, not the sentence")
    func linkRenderingDestinationsGetTheBareURL() {
        // Both draw the link themselves; handed text they would print the sentence beside it.
        let item = item(title: "Pizza Club")

        #expect(sharedText(item, to: .airDrop) as? URL == url)
        #expect(sharedText(item, to: .init(rawValue: "com.tinyspeck.chatlyio.share")) as? URL == url)
    }

    @Test("The invitation is the mail subject, and empty without a name")
    func subjectMatchesTheInvitation() {
        let controller = UIActivityViewController(activityItems: [], applicationActivities: nil)

        #expect(item(title: "Pizza Club").activityViewController(controller, subjectForActivityType: nil)
            == "Join Pizza Club on Flipcash and let's chat")
        #expect(item(title: nil).activityViewController(controller, subjectForActivityType: nil) == "")
    }

    @Test("The share sheet's own card names the group, without the sentence")
    func metadataTitleIsTheGroupName() {
        // The invitation already sits in the message below; the card's job is to say which group
        // is about to be handed out.
        #expect(metadata(item(title: "  Pizza Club\n"))?.title == "Pizza Club")
        #expect(metadata(item(title: nil))?.title == "Invite to Join Group")
    }

    @Test("The group's picture becomes the card's icon, and nothing stands in when there is none")
    func metadataCarriesTheGroupIcon() {
        let icon = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { _ in }

        #expect(metadata(item(title: "Pizza Club", icon: icon))?.iconProvider != nil)
        #expect(metadata(item(title: "Pizza Club"))?.iconProvider == nil)
    }
}
