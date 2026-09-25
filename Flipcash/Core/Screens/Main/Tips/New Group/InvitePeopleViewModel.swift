//
//  InvitePeopleViewModel.swift
//  Flipcash
//

import Foundation
import FlipcashCore

/// The invite sheet's selection and send (node 10330:19387): the group's invite link, then an
/// optional message, posted into each picked 1:1 chat on its own.
@MainActor
@Observable
final class InvitePeopleViewModel {

    /// Posts `text` into a chat and reports whether the server took it — `ConversationController.send`,
    /// which leaves a failed message in that chat's transcript as `.failed` rather than throwing.
    typealias Send = @MainActor (_ text: String, _ chatID: ConversationID) async -> Bool

    /// The group's invite link: what Share and Copy hand out, and the first message of every send.
    let url: URL

    /// The chats picked, in tap order: the first one is where the sheet lands after sending.
    private(set) var selectedChatIDs: [ConversationID] = []

    /// The optional note sent after the link.
    var message: String = ""

    private(set) var isSending = false

    init(url: URL) {
        self.url = url
    }

    /// Whether the message field and Invite button show: only once a chat is picked.
    var showsComposer: Bool {
        !selectedChatIDs.isEmpty
    }

    func isSelected(_ chatID: ConversationID) -> Bool {
        selectedChatIDs.contains(chatID)
    }

    func toggleSelection(_ chatID: ConversationID) {
        if let index = selectedChatIDs.firstIndex(of: chatID) {
            selectedChatIDs.remove(at: index)
        } else {
            selectedChatIDs.append(chatID)
        }
    }

    /// Sends the link to every picked chat, then the message after it when there is one.
    ///
    /// A chat whose send fails doesn't stop the rest; its failed message stays in that chat with the
    /// transcript's retry. The message follows only a link that went through, so it never lands in a
    /// chat ahead of the invite it is about.
    ///
    /// - Returns: The chat picked first, or nil when nothing was picked.
    func sendInvites(via send: Send) async -> ConversationID? {
        guard !isSending else { return nil }
        isSending = true
        defer { isSending = false }

        let targets = selectedChatIDs
        // Canonicalised as the chat composer's `ComposerModel.submission` does, so a note sent from
        // here is the message the composer would have sent.
        let note = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let link = url.absoluteString

        for chatID in targets {
            let sentLink = await send(link, chatID)
            if sentLink, !note.isEmpty {
                _ = await send(note, chatID)
            }
        }
        return targets.first
    }
}
