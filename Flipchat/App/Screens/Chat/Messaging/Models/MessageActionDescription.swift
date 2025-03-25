//
//  MessageActionDescription.swift
//  Code
//
//  Created by Dima Bart on 2025-03-24.
//

import Foundation
import FlipchatServices

struct MessageActionDescription {
    let messageID: MessageID
    let senderID: UserID
    let messageRow: MessageRow
    
    let senderDisplayName: String
    let messageText: String
    
    let showDeleteAction: Bool
    let showSpeakerAction: Bool
    let showMuteAction: Bool
    let showTipAction: Bool
    let showReportAction: Bool
    let showBlockAction: Bool
    
    let isFromSelf: Bool
    let isMessageDeleted: Bool
    let isSenderBlocked: Bool
    let canSenderSend: Bool
}

extension MessageActionDescription: Identifiable {
    var id: UUID {
        messageID.uuid
    }
}
