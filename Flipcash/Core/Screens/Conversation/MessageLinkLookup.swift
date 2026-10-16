//
//  MessageLinkLookup.swift
//  Flipcash
//

import Foundation
import FlipcashCore

/// The one message read a message card needs, under a view mode. Decrypts a sealed message, so a
/// member of a private group or a DM sees the same text the transcript does.
nonisolated protocol MessageLinkReading: Sendable {
    func getMessage(owner: KeyPair, conversationID: ConversationID, messageID: MessageID, viewMode: ConversationViewMode) async throws -> ConversationMessage?
}

extension EncryptedChatClient: MessageLinkReading {}

/// What a message card needs to know about the viewer's own standing, read on the main actor from
/// the conversation feed.
nonisolated struct MessageLinkViewer: Sendable {
    /// The chat as the feed holds it, or nil when the viewer's feed does not.
    let conversation: @Sendable (ConversationID) async -> Conversation?
    /// Whether the viewer has joined `conversation`.
    let isMember: @Sendable (Conversation) async -> Bool
    /// How the viewer's own transcript names `conversation`.
    let title: @Sendable (Conversation) async -> String
    /// A sender the chat's own roster leaves unnamed, as the rest of the app knows them.
    let knownMember: @Sendable (UserID) async -> ConversationMember?
    /// The viewer, so their own messages are authored "You".
    let userID: UserID

    /// The app's viewer, answered by the conversation feed.
    @MainActor
    init(controller: ConversationController, knownAuthors: KnownAuthorDirectory, userID: UserID) {
        self.conversation = { [weak controller] in await controller?.conversation(withID: $0) }
        self.isMember = { [weak controller] in await controller?.isMember(of: $0) ?? false }
        self.title = { [weak controller] in await controller?.displayName(for: $0) ?? "Group Chat" }
        self.knownMember = { [weak knownAuthors] userID in
            guard let knownAuthors else { return nil }
            if let member = await knownAuthors.snapshot.membersByUserID[userID] { return member }
            await knownAuthors.resolve([userID])
            return await knownAuthors.snapshot.membersByUserID[userID]
        }
        self.userID = userID
    }

    init(
        conversation: @escaping @Sendable (ConversationID) async -> Conversation?,
        isMember: @escaping @Sendable (Conversation) async -> Bool,
        title: @escaping @Sendable (Conversation) async -> String,
        knownMember: @escaping @Sendable (UserID) async -> ConversationMember? = { _ in nil },
        userID: UserID
    ) {
        self.conversation = conversation
        self.isMember = isMember
        self.title = title
        self.knownMember = knownMember
        self.userID = userID
    }
}

extension LinkCardResolver {

    /// What a message card shows this viewer. Public groups read the message under
    /// `.fullOrRedacted`, so the server applies the group's listener rules; a private group or a DM
    /// is only readable by a member, and a non-member gets the chat's public preview or its kind.
    ///
    /// Redacted text never enters the model: a redacted message keeps only the chat's title and
    /// requirement, and the view draws a fixed filler under the blur. A card never joins, requests
    /// or buys; its buttons only hand the tap to the app.
    static func messageLookup(
        chats: any GroupChatReading,
        messages: any MessageLinkReading,
        mints: any MintMetadataReading,
        owner: KeyPair,
        viewer context: MessageLinkViewer,
        cashLinks: @escaping @Sendable (String) async throws -> LinkCard.Cash.Resolved = { _ in throw CancellationError() }
    ) -> @Sendable (LinkCard.Message) async throws -> LinkCard.Message.State {
        { card in
            let chatID = card.chatID

            let conversation: Conversation
            if let held = await context.conversation(chatID) {
                conversation = held
            } else {
                do {
                    conversation = try await chats.getChat(owner: owner, conversationID: chatID, viewMode: .redacted)
                } catch ErrorGetChat.notFound {
                    return .unavailable
                } catch ErrorGetChat.denied {
                    // The chat exists and is not the viewer's: all a stranger learns is its kind.
                    return .lockedDirect
                }
            }

            func read(_ mode: ConversationViewMode) async throws -> ConversationMessage? {
                try await messages.getMessage(owner: owner, conversationID: chatID, messageID: card.messageID, viewMode: mode)
            }

            switch conversation.type {
            case .contactDm, .tipDm:
                let message: ConversationMessage?
                do { message = try await read(.full) } catch ErrorGetMessage.denied { return .lockedDirect }
                guard let message else { return await deleted(conversation, context: context) }
                return await memberState(message, in: conversation, context: context, cashLinks: cashLinks) { .resolved($0) }

            case .group where conversation.isPrivate:
                guard await context.isMember(conversation) else { return await lockedGroup(conversation) }
                let message: ConversationMessage?
                do { message = try await read(.full) } catch ErrorGetMessage.denied { return await lockedGroup(conversation) }
                guard let message else { return await deleted(conversation, context: context) }
                return await memberState(message, in: conversation, context: context, cashLinks: cashLinks) { .resolved($0) }

            case .group:
                let isMember = await context.isMember(conversation)
                let message: ConversationMessage?
                do { message = try await read(.fullOrRedacted) } catch ErrorGetMessage.denied { return .unavailable }
                guard let message else { return await deleted(conversation, context: context) }

                if isMember, !message.redacted {
                    return await memberState(message, in: conversation, context: context, cashLinks: cashLinks) { .resolved($0) }
                }
                // Cash is never redacted, so a non-member reads it whatever their balance.
                if case .cash = message.content {
                    return await memberState(message, in: conversation, context: context, cashLinks: cashLinks) { .resolved($0) }
                }
                if message.redacted {
                    let mint = await headlineMint(of: conversation)
                    var mintName: String?
                    if let mint { mintName = try? await mints.fetchMint(mint: mint).name }
                    return await redactedState(message, conversation, mintName: mintName, context: context)
                }
                return await memberState(message, in: conversation, context: context, cashLinks: cashLinks) { .gatedReadable($0) }
            }
        }
    }

    @MainActor
    private static func headlineMint(of conversation: Conversation) -> PublicKey? {
        guard let mint = headline(for: conversation.rules?.listener ?? [])?.mint, mint != .usdf else { return nil }
        return mint
    }

    @MainActor
    private static func redactedState(_ message: ConversationMessage, _ conversation: Conversation, mintName: String?, context: MessageLinkViewer) async -> LinkCard.Message.State {
        var photoBlurHash: String?
        if case .media(let attachments, _) = message.content { photoBlurHash = attachments.first?.blurhash }
        return .gatedRedacted(.init(
            chatTitle: conversation.groupLinkTitle,
            authorName: await author(of: message, in: conversation, context: context),
            time: time(of: message),
            requirement: groupRequirementLine(headline(for: conversation.rules?.listener ?? []), mintName: mintName),
            photoBlurHash: photoBlurHash
        ))
    }

    @MainActor
    private static func lockedGroup(_ conversation: Conversation) -> LinkCard.Message.State {
        let host = conversation.creator.flatMap { creator in
            conversation.members.first { $0.userID == creator }?.displayName
        }
        return .lockedGroup(.init(
            title: conversation.groupLinkTitle,
            memberCount: conversation.rosterSummary.peopleCount,
            hostName: (host?.isEmpty ?? true) ? nil : host,
            avatarID: conversation.id.description,
            imageData: nil,
            blurHash: conversation.picture?.thumbnailBlurhash
        ))
    }

    private static func kind(of conversation: Conversation) -> LinkCard.Message.Kind {
        switch conversation.type {
        case .contactDm, .tipDm: .directMessage
        case .group: conversation.isPrivate ? .privateGroup : .publicGroup
        }
    }

    /// The chat header over a message that is gone: a tombstone, or a chat that no longer has it.
    private static func deleted(_ conversation: Conversation, context: MessageLinkViewer) async -> LinkCard.Message.State {
        .deleted(.init(chatTitle: await context.title(conversation), kind: kind(of: conversation), avatarID: conversation.id.description))
    }

    // Names a sender the way the chat's own rows do: the chat roster first, then the rest of the
    // app's known authors, and for either a display name before a username.
    private static func author(of message: ConversationMessage, in conversation: Conversation, context: MessageLinkViewer) async -> String {
        guard let sender = message.senderID else { return "Someone" }
        if sender == context.userID { return "You" }
        if let member = conversation.members.first(where: { $0.userID == sender }), let name = name(of: member) {
            return name
        }
        if let member = await context.knownMember(sender), let name = name(of: member) {
            return name
        }
        return "Someone"
    }

    private static func name(of member: ConversationMember) -> String? {
        member.displayName.isEmpty ? member.username?.handle : member.displayName
    }

    private static func time(of message: ConversationMessage) -> String {
        Calendar.current.isDateInToday(message.date)
            ? message.date.formatted(date: .omitted, time: .shortened)
            : message.date.formatted(date: .abbreviated, time: .omitted)
    }

    /// The card for a message the viewer may read in full: cash, and a text that is only a cash
    /// link, as an amount; text and photo captions as an excerpt, a photo with its thumbnail; and anything else (a tombstone, a widget, ciphertext that would not
    /// open) as unavailable.
    private static func memberState(
        _ message: ConversationMessage,
        in conversation: Conversation,
        context: MessageLinkViewer,
        cashLinks: @Sendable (String) async throws -> LinkCard.Cash.Resolved,
        wrapping: (LinkCard.Message.Resolved) -> LinkCard.Message.State
    ) async -> LinkCard.Message.State {
        let title = await context.title(conversation)
        let author = await author(of: message, in: conversation, context: context)

        switch message.content {
        case .cash(let amount):
            let verb: LinkCard.Message.Cash.Verb = message.cashAction == .tipped ? .tipped : .sent
            return .cash(.init(chatTitle: title, kind: kind(of: conversation), authorName: author, time: time(of: message), amount: amount.nativeAmount.formatted(), verb: verb))

        case .text(let text):
            if let entropy = soleCashLink(in: text), let link = try? await cashLinks(entropy) {
                return .cash(.init(chatTitle: title, kind: kind(of: conversation), authorName: author, time: time(of: message), amount: link.amount, verb: .cashLink, claim: link.claim))
            }
            return wrapping(resolved(message, kind: kind(of: conversation), title: title, author: author, excerpt: text))

        case .media(let attachments, let caption):
            let excerpt = (caption?.isEmpty ?? true) ? "Photo" : caption!
            let photo = attachments.first.map {
                LinkCard.Message.Photo(blobID: message.redacted ? nil : $0.blobID, sealed: $0.sealed, blurHash: $0.blurhash)
            }
            return wrapping(resolved(message, kind: kind(of: conversation), title: title, author: author, excerpt: excerpt, photo: photo))

        case .deleted:
            return await deleted(conversation, context: context)

        case .encrypted, .widget, .system:
            return .unavailable
        }
    }

    /// The entropy of the cash link `text` consists of, or nil when it is anything more than that link.
    private static func soleCashLink(in text: String) -> String? {
        let links = LinkDetector().webLinks(in: text)
        guard links.count == 1, let link = links.first,
              case .cash(let cash) = LinkCardClassifier().firstCard(in: links) else { return nil }
        let rest = (text as NSString).replacingCharacters(in: link.range, with: "")
        guard rest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return cash.entropy
    }

    private static func resolved(_ message: ConversationMessage, kind: LinkCard.Message.Kind, title: String, author: String, excerpt: String, photo: LinkCard.Message.Photo? = nil) -> LinkCard.Message.Resolved {
        let reactions = message.reactionState?.confirmed.values.reduce(0) { $0 + Int($1.count) } ?? 0
        return .init(
            chatTitle: title,
            kind: kind,
            authorName: author,
            time: time(of: message),
            excerpt: excerpt,
            reactionCount: reactions,
            avatarID: message.senderID?.uuidString ?? title,
            photo: photo
        )
    }
}
