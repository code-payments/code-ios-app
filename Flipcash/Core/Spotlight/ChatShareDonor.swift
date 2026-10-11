//
//  ChatShareDonor.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Intents
import FlipcashCore

/// Donates an outgoing `INSendMessageIntent` after the user sends into a chat, which is what makes
/// that chat a suggestion in the system Share sheet. The identifier is the chat's link form, the
/// shape `ShareChatSelection.preselected` parses in the Share Extension.
nonisolated enum ChatShareDonor {

    static func donate(_ conversation: Conversation, displayName: String, selfUserID: UserID?) {
        let intent = makeIntent(for: conversation, displayName: displayName, selfUserID: selfUserID)
        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .outgoing
        interaction.donate(completion: nil)
    }

    static func makeIntent(for conversation: Conversation, displayName: String, selfUserID: UserID?) -> INSendMessageIntent {
        let picture = conversation.type == .group
            ? conversation.picture
            : conversation.counterpart(excluding: selfUserID)?.profilePicture
        let image = picture
            .flatMap { BlobCache.profilePictures.data(for: $0.thumbnailBlobID) }
            .map { INImage(imageData: $0) }

        var recipients: [INPerson]?
        var groupName: INSpeakableString?
        if conversation.type == .group {
            groupName = INSpeakableString(spokenPhrase: displayName)
        } else {
            let customIdentifier = conversation.counterpart(excluding: selfUserID)?.userID?.uuidString
            recipients = [INPerson(
                personHandle: INPersonHandle(value: customIdentifier, type: .unknown),
                nameComponents: nil,
                displayName: displayName,
                image: image,
                contactIdentifier: nil,
                customIdentifier: customIdentifier
            )]
        }

        let intent = INSendMessageIntent(
            recipients: recipients,
            outgoingMessageType: .outgoingMessageText,
            content: nil,
            speakableGroupName: groupName,
            conversationIdentifier: conversation.id.linkPathComponent,
            serviceName: nil,
            sender: nil,
            attachments: nil
        )
        if let image, groupName != nil {
            intent.setImage(image, forParameterNamed: \.speakableGroupName)
        }
        return intent
    }
}
