//
//  ChatMediaSendPlan.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import FlipcashCore

/// The messages one composer send fans out to, pinned by `chat_media.json`'s `fanOut` section.
///
/// Generic over the chip so the fixture can name chips with strings while the send path hands in
/// `ComposerChip`s.
enum ChatMediaSendPlan {

    /// One photo's message.
    struct MediaMessage<Chip> {
        let chip: Chip
        let caption: String?
        let replyTo: MessageID?
    }

    /// One message a send becomes.
    enum Message<Chip> {
        case text(String, replyTo: MessageID?)
        case media(MediaMessage<Chip>)
    }

    /// Returns a text message when there are no chips, otherwise one media message per chip.
    static func messages<Chip>(chips: [Chip], text: String?, replyTo: MessageID?) -> [Message<Chip>] {
        guard chips.isEmpty else {
            return mediaMessages(chips: chips, caption: text, replyTo: replyTo).map(Message.media)
        }
        guard let text = nonEmpty(text) else { return [] }
        return [.text(text, replyTo: replyTo)]
    }

    /// Returns one message per chip in chip order, with `caption` on the last and `replyTo` on the first.
    static func mediaMessages<Chip>(chips: [Chip], caption: String?, replyTo: MessageID?) -> [MediaMessage<Chip>] {
        let caption = nonEmpty(caption)
        return chips.enumerated().map { index, chip in
            MediaMessage(
                chip: chip,
                caption: index == chips.count - 1 ? caption : nil,
                replyTo: index == 0 ? replyTo : nil
            )
        }
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        return text
    }
}
