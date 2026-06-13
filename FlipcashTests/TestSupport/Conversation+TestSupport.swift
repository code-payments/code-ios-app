//
//  Conversation+TestSupport.swift
//  FlipcashTests
//

import Foundation
import FlipcashCore

extension ConversationID {
    /// A deterministic 32-byte ChatId filled with `byte`.
    static func test(_ byte: UInt8) -> ConversationID {
        ConversationID(data: Data(repeating: byte, count: 32))
    }
}
