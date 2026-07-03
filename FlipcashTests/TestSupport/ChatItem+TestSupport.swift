//
//  ChatItem+TestSupport.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import FlipcashCore
@testable import FlipcashUI

extension ChatItem {

    /// A text-message row for transcript fixtures — the one `ChatMessage` factory shared by the
    /// chat suites, so an init change lands in a single place. Grouping and receipt knobs
    /// default off; the text derives from the id.
    static func text(
        _ id: String,
        sender: ChatMessage.Sender = .me,
        continuationFromPrevious: Bool = false,
        continuedByNext: Bool = false,
        receipt: String? = nil,
        linkPreview: LinkPreview? = nil
    ) -> ChatItem {
        .message(ChatMessage(
            id: id,
            text: "text-\(id)",
            sender: sender,
            isContinuationFromPrevious: continuationFromPrevious,
            isContinuedByNext: continuedByNext,
            receipt: receipt,
            linkPreview: linkPreview
        ))
    }
}
