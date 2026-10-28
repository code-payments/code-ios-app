//
//  FlipClient+Chat.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

extension FlipClient {

    /// Page the DM chat feed to exhaustion against a single pinned snapshot.
    /// The caller must already be consuming its `subscribeConversationStream` events so updates
    /// that land mid-pagination aren't lost.
    public func getDmChatFeed(owner: KeyPair, type: ConversationType) async throws -> [Conversation] {
        var all: [Conversation] = []
        var pagingToken: Data?

        while true {
            let page = try await withCheckedThrowingContinuation { c in
                chatService.getDmChatFeed(owner: owner, type: type, pagingToken: pagingToken) { c.resume(with: $0) }
            }
            all.append(contentsOf: page.conversations)
            if !page.hasMore { break }
            pagingToken = page.pagingToken
        }

        return all
    }

    public func getChat(owner: KeyPair, conversationID: ConversationID, viewMode: ConversationViewMode = .full) async throws -> Conversation {
        try await withCheckedThrowingContinuation { c in
            chatService.getChat(owner: owner, conversationID: conversationID, viewMode: viewMode) { c.resume(with: $0) }
        }
    }

    /// Mutes `conversationID` for `owner` until `mute` lapses (or forever). Returns the resulting
    /// viewer state, including the version stamp so a caller applying it locally can compare against
    /// the same greater-value-wins rule as a stream-delivered `ConversationStreamEvent.viewerStateChanged`.
    public func muteChat(owner: KeyPair, conversationID: ConversationID, mute: ConversationMuteState) async throws -> ConversationViewerState {
        try await withCheckedThrowingContinuation { c in
            chatService.muteChat(owner: owner, conversationID: conversationID, mute: mute) { c.resume(with: $0) }
        }
    }

    /// Unmutes `conversationID` for `owner`. Returns the resulting viewer state.
    public func unmuteChat(owner: KeyPair, conversationID: ConversationID) async throws -> ConversationViewerState {
        try await withCheckedThrowingContinuation { c in
            chatService.unmuteChat(owner: owner, conversationID: conversationID) { c.resume(with: $0) }
        }
    }

    // MARK: - Moderation -

    /// Silences `userID` in `conversationID` until `silence` lapses (or forever). Creator only.
    public func silenceUser(owner: KeyPair, conversationID: ConversationID, userID: UserID, silence: ConversationSilenceState) async throws {
        try await withCheckedThrowingContinuation { c in
            chatService.silenceUser(owner: owner, conversationID: conversationID, userID: userID, silence: silence) { c.resume(with: $0) }
        }
    }

    /// Lifts a silence on `userID` in `conversationID`. Creator only.
    public func unsilenceUser(owner: KeyPair, conversationID: ConversationID, userID: UserID) async throws {
        try await withCheckedThrowingContinuation { c in
            chatService.unsilenceUser(owner: owner, conversationID: conversationID, userID: userID) { c.resume(with: $0) }
        }
    }

    /// Bans `userID` from `conversationID`. Creator only.
    public func banUser(owner: KeyPair, conversationID: ConversationID, userID: UserID) async throws {
        try await withCheckedThrowingContinuation { c in
            chatService.banUser(owner: owner, conversationID: conversationID, userID: userID) { c.resume(with: $0) }
        }
    }

    /// Lifts a ban on `userID` in `conversationID`. Creator only.
    public func unbanUser(owner: KeyPair, conversationID: ConversationID, userID: UserID) async throws {
        try await withCheckedThrowingContinuation { c in
            chatService.unbanUser(owner: owner, conversationID: conversationID, userID: userID) { c.resume(with: $0) }
        }
    }

    /// Every user silenced or banned in `conversationID`, paged to exhaustion. Creator only.
    public func getRestrictedUsers(owner: KeyPair, conversationID: ConversationID) async throws -> [ConversationRestrictedUser] {
        var all: [ConversationRestrictedUser] = []
        var pagingToken: Data?

        while true {
            let page: ChatService.RestrictedUsersPage = try await withCheckedThrowingContinuation { c in
                chatService.getRestrictedUsers(owner: owner, conversationID: conversationID, pagingToken: pagingToken) { c.resume(with: $0) }
            }
            all.append(contentsOf: page.users)
            guard page.hasMore else { break }
            pagingToken = page.pagingToken
        }
        return all
    }

    /// Page the group chat feed to exhaustion against a single pinned snapshot. Unlike a DM feed, the
    /// caller's own membership can change mid-read (a join or a leave lands as a `rosterChanged`
    /// stream event, not a feed mutation) — the same live-stream caveat as `getDmChatFeed` applies.
    public func getGroupChatFeed(owner: KeyPair) async throws -> [Conversation] {
        var all: [Conversation] = []
        var pagingToken: Data?

        while true {
            let page = try await withCheckedThrowingContinuation { c in
                chatService.getGroupChatFeed(owner: owner, pagingToken: pagingToken) { c.resume(with: $0) }
            }
            all.append(contentsOf: page.conversations)
            if !page.hasMore { break }
            pagingToken = page.pagingToken
        }

        return all
    }

    /// Starts a new group chat and returns its metadata on success. `rules` gates who may read/join
    /// and who may send; `nil` leaves the chat unrestricted. A `nil` or empty `description` sets none.
    ///
    /// `idempotencyKey` must be minted by the caller where the user's intent to create the chat
    /// originates (not here) and reused for every retry of that same attempt — see
    /// `ChatService.startChat`. A retry with the same key returns the original chat.
    public func startChat(owner: KeyPair, title: String, description: String? = nil, pictureBlobID: BlobID?, rules: ConversationRules?, idempotencyKey: UUID) async throws -> Conversation {
        try await withCheckedThrowingContinuation { c in
            chatService.startChat(owner: owner, title: title, description: description, pictureBlobID: pictureBlobID, rules: rules, idempotencyKey: idempotencyKey) { c.resume(with: $0) }
        }
    }

    /// Starts a private group, end-to-end encrypted and admitted by its creator. The creator must
    /// store its own key envelope next (see `GroupKeyEnvelopes.storeNewKey`); until then the
    /// server refuses lobby entry and messages. `idempotencyKey` follows `startChat`'s rules.
    public func startPrivateChat(owner: KeyPair, title: String, description: String? = nil, pictureBlobID: BlobID?, idempotencyKey: UUID) async throws -> Conversation {
        try await withCheckedThrowingContinuation { c in
            chatService.startPrivateChat(owner: owner, title: title, description: description, pictureBlobID: pictureBlobID, idempotencyKey: idempotencyKey) { c.resume(with: $0) }
        }
    }

    /// Joins an existing group chat. Fails with `.rulesNotSatisfied` when the caller doesn't meet the
    /// chat's `ConversationRules`.
    public func joinChat(owner: KeyPair, conversationID: ConversationID) async throws -> Conversation {
        try await withCheckedThrowingContinuation { c in
            chatService.joinChat(owner: owner, conversationID: conversationID) { c.resume(with: $0) }
        }
    }

    /// Joins a private group through an invite link. The failures include `.inviteNotFound`,
    /// `.inviteExhausted`, `.inviteExpired` and `.inviteRevoked`.
    public func joinChat(owner: KeyPair, conversationID: ConversationID, invite: InviteJoinParameters) async throws -> Conversation {
        try await withCheckedThrowingContinuation { c in
            chatService.joinChat(owner: owner, conversationID: conversationID, invite: invite) { c.resume(with: $0) }
        }
    }

    /// Leaves a group chat. The caller's own `rosterChanged` event (naming itself) is what actually
    /// drops the chat from the local feed and database — this call just tells the server to emit it.
    public func leaveChat(owner: KeyPair, conversationID: ConversationID) async throws {
        try await withCheckedThrowingContinuation { c in
            chatService.leaveChat(owner: owner, conversationID: conversationID) { c.resume(with: $0) }
        }
    }

    /// Represents one paged read of a chat's roster: the members returned, most recently joined
    /// first, and the roster summary as of that page's read.
    ///
    /// This is a single pinned read, not a merged view — a large group's roster can page from an
    /// index that trails the event stream (see `chat.v1.GetRoster`'s staleness contract), so the
    /// caller must reconcile `members` against whatever it already holds from the stream, by
    /// ``ConversationMember/version``, greater winning, rather than trusting this to be current or
    /// complete on its own.
    public struct RosterPage: Sendable {
        public let members: [ConversationMember]
        public let rosterSummary: ConversationRosterSummary
    }

    /// Pages a chat's roster to exhaustion against a single pinned read. The caller must already be
    /// consuming its `subscribeConversationStream` events — as with `getDmChatFeed`/
    /// `getGroupChatFeed` — and must merge the result against them by ``ConversationMember/version``
    /// rather than treating it as an authoritative snapshot; see ``RosterPage``.
    ///
    /// `owner` may be `nil` when `inviteToken` is given: the token stands in for auth.
    public func getRoster(owner: KeyPair?, conversationID: ConversationID, inviteToken: InviteToken? = nil) async throws -> RosterPage {
        var members: [ConversationMember] = []
        var rosterSummary = ConversationRosterSummary(memberCount: 0, version: 0)
        var pagingToken: Data?

        while true {
            let page = try await withCheckedThrowingContinuation { c in
                chatService.getRoster(owner: owner, conversationID: conversationID, inviteToken: inviteToken, pagingToken: pagingToken) { c.resume(with: $0) }
            }
            members.append(contentsOf: page.members)
            rosterSummary = page.rosterSummary
            if !page.hasMore { break }
            pagingToken = page.pagingToken
        }

        return RosterPage(members: members, rosterSummary: rosterSummary)
    }

    /// A sample of up to 100 recent chatters in a public group, with whether more exist. Unlike
    /// ``getRoster(owner:conversationID:)`` it needs no membership, so it is the call for a preview or
    /// lobby view. `owner` is optional because a public group needs no auth; a private group or a DM
    /// is `.denied`.
    public func sampleChatters(owner: KeyPair?, conversationID: ConversationID) async throws -> (chatters: [SampledChatter], hasMore: Bool) {
        let page = try await withCheckedThrowingContinuation { c in
            chatService.sampleChatters(owner: owner, conversationID: conversationID) { c.resume(with: $0) }
        }
        return (page.chatters, page.hasMore)
    }

    /// Replaces the signed-in user's featured groups (at most 10, in order) and returns the
    /// resulting list. A private group is `.denied`.
    public func setFeaturedGroups(owner: KeyPair, conversationIDs: [ConversationID]) async throws -> [Conversation] {
        try await withCheckedThrowingContinuation { c in
            chatService.setFeaturedGroups(owner: owner, conversationIDs: conversationIDs) { c.resume(with: $0) }
        }
    }

    /// The groups `username` features, list-view shaped: no members, viewer state, last message or
    /// cover picture. `owner` is optional.
    public func getFeaturedGroups(owner: KeyPair?, username: Username) async throws -> [Conversation] {
        try await withCheckedThrowingContinuation { c in
            chatService.getFeaturedGroups(owner: owner, username: username) { c.resume(with: $0) }
        }
    }

    /// The people to suggest after an `@` in a group chat, most relevant first; see
    /// ``MentionSuggestion``. Fetch it once per composing session and filter it locally.
    public func getMentionSuggestions(owner: KeyPair, conversationID: ConversationID) async throws -> [MentionSuggestion] {
        try await withCheckedThrowingContinuation { c in
            chatService.getMentionSuggestions(owner: owner, conversationID: conversationID) { c.resume(with: $0) }
        }
    }

    /// Edits a group chat's title, description, picture, and/or cover picture; a `nil` title, picture
    /// or cover picture and an `.unchanged` description leave that field as it is, and changing
    /// nothing is a no-op that still returns the current metadata. Pass `.clear` to remove the
    /// description. Only a member with ``ConversationViewerState/canEdit`` may call this.
    ///
    /// `pictureBlobID` and `coverPictureBlobID` must already be `READY` (uploaded via `BlobService`) —
    /// this call does not upload them. Real changes also arrive on the event stream as
    /// `MetadataUpdate.titleChanged`/`.descriptionChanged`/`.pictureChanged`/`.coverPictureChanged`
    /// for the chat's other members (and the caller's other devices); this call's return value is
    /// only this device's confirmation.
    public func editChat(owner: KeyPair, conversationID: ConversationID, title: String?, description: ConversationDescriptionEdit = .unchanged, pictureBlobID: BlobID?, coverPictureBlobID: BlobID? = nil) async throws -> Conversation {
        try await withCheckedThrowingContinuation { c in
            chatService.editChat(owner: owner, conversationID: conversationID, title: title, description: description, pictureBlobID: pictureBlobID, coverPictureBlobID: coverPictureBlobID) { c.resume(with: $0) }
        }
    }

    /// Fetches one message by id, or nil when the chat has no such message.
    public func getMessage(owner: KeyPair, conversationID: ConversationID, messageID: MessageID, viewMode: ConversationViewMode = .full) async throws -> ConversationMessage? {
        try await withCheckedThrowingContinuation { c in
            chatMessagingService.getMessage(owner: owner, conversationID: conversationID, messageID: messageID, viewMode: viewMode) { c.resume(with: $0) }
        }
    }

    public func getMessages(owner: KeyPair, conversationID: ConversationID, before: MessageID?, viewMode: ConversationViewMode = .full) async throws -> [ConversationMessage] {
        try await withCheckedThrowingContinuation { c in
            chatMessagingService.getMessages(owner: owner, conversationID: conversationID, pagingToken: before?.pagingToken, viewMode: viewMode) { c.resume(with: $0) }
        }
    }

    /// Streams the delta since `afterSequence` to `onBatch` (each with its resume checkpoint) and
    /// returns the chat's head on clean completion. Throws `ErrorGetDelta` on `.resetRequired`/denied/
    /// transport failure.
    public func getDelta(
        owner: KeyPair,
        conversationID: ConversationID,
        afterSequence: UInt64,
        viewMode: ConversationViewMode = .full,
        onBatch: @MainActor @Sendable @escaping (_ messages: [ConversationMessage], _ checkpoint: UInt64?) -> Void
    ) async throws -> UInt64 {
        try await withCheckedThrowingContinuation { c in
            chatMessagingService.getDelta(owner: owner, conversationID: conversationID, afterSequence: afterSequence, viewMode: viewMode, onBatch: onBatch) { c.resume(with: $0) }
        }
    }

    /// Sends `text` carrying `linkPreview`, encrypted with `seal` when set, and returns the server's
    /// copy (decrypted).
    @discardableResult
    public func sendMessage(owner: KeyPair, conversationID: ConversationID, text: String, repliedTo: MessageID?, linkPreview: MessageLinkPreview? = nil, seal: ChatSeal?, clientMessageID: UUID) async throws -> ConversationMessage {
        try await withCheckedThrowingContinuation { c in
            chatMessagingService.sendMessage(owner: owner, conversationID: conversationID, text: text, repliedTo: repliedTo, linkPreview: linkPreview, seal: seal, clientMessageID: clientMessageID) { c.resume(with: $0) }
        }
    }

    /// Sends the finalized photo `blobID` as one media message, with `caption` under it.
    @discardableResult
    public func sendMediaMessage(owner: KeyPair, conversationID: ConversationID, blobID: BlobID, caption: String?, repliedTo: MessageID?, clientMessageID: UUID) async throws -> ConversationMessage {
        try await withCheckedThrowingContinuation { c in
            chatMessagingService.sendMediaMessage(owner: owner, conversationID: conversationID, blobID: blobID, caption: caption, repliedTo: repliedTo, clientMessageID: clientMessageID) { c.resume(with: $0) }
        }
    }

    /// Sends the finalized encrypted `photo` sealed with `seal`, with `caption` under it, and returns
    /// the server's copy (decrypted).
    @discardableResult
    public func sendSealedMediaMessage(owner: KeyPair, conversationID: ConversationID, photo: SealedPhoto, caption: String?, repliedTo: MessageID?, seal: ChatSeal, clientMessageID: UUID) async throws -> ConversationMessage {
        try await withCheckedThrowingContinuation { c in
            chatMessagingService.sendSealedMediaMessage(owner: owner, conversationID: conversationID, photo: photo, caption: caption, repliedTo: repliedTo, seal: seal, clientMessageID: clientMessageID) { c.resume(with: $0) }
        }
    }

    /// Sends a widget naming the payment request `id`, sealed with `seal`, and returns the server's
    /// copy (decrypted).
    @discardableResult
    public func sendPaymentRequestMessage(owner: KeyPair, conversationID: ConversationID, paymentRequestID id: PaymentRequestID, seal: ChatSeal, clientMessageID: UUID) async throws -> ConversationMessage {
        try await withCheckedThrowingContinuation { c in
            chatMessagingService.sendPaymentRequestMessage(owner: owner, conversationID: conversationID, paymentRequestID: id, seal: seal, clientMessageID: clientMessageID) { c.resume(with: $0) }
        }
    }

    public func editMessage(
        owner: KeyPair,
        conversationID: ConversationID,
        messageID: MessageID,
        text: String,
        repliedTo: MessageID?,
        linkPreview: MessageLinkPreview? = nil,
        seal: ChatSeal?,
        expectedEventSequence: UInt64
    ) async throws -> MessageMutation {
        try await withCheckedThrowingContinuation { c in
            chatMessagingService.editMessage(
                owner: owner,
                conversationID: conversationID,
                messageID: messageID,
                text: text,
                repliedTo: repliedTo,
                linkPreview: linkPreview,
                seal: seal,
                expectedEventSequence: expectedEventSequence
            ) { c.resume(with: $0) }
        }
    }

    /// Adds the owner's reaction with `emoji` to a message and returns the emoji's new aggregate.
    public func addReaction(owner: KeyPair, conversationID: ConversationID, messageID: MessageID, emoji: String) async throws -> EmojiReaction {
        try await withCheckedThrowingContinuation { c in
            chatMessagingService.addReaction(owner: owner, conversationID: conversationID, messageID: messageID, emoji: emoji) { c.resume(with: $0) }
        }
    }

    /// Removes the owner's reaction with `emoji` from a message and returns the emoji's new aggregate.
    public func removeReaction(owner: KeyPair, conversationID: ConversationID, messageID: MessageID, emoji: String) async throws -> EmojiReaction {
        try await withCheckedThrowingContinuation { c in
            chatMessagingService.removeReaction(owner: owner, conversationID: conversationID, messageID: messageID, emoji: emoji) { c.resume(with: $0) }
        }
    }

    /// One page of the users who reacted to a message with `emoji`, newest first.
    public func getReactors(owner: KeyPair, conversationID: ConversationID, messageID: MessageID, emoji: String, pageSize: Int = 50, pagingToken: Data? = nil) async throws -> ReactorPage {
        try await withCheckedThrowingContinuation { c in
            chatMessagingService.getReactors(owner: owner, conversationID: conversationID, messageID: messageID, emoji: emoji, pageSize: pageSize, pagingToken: pagingToken) { c.resume(with: $0) }
        }
    }

    /// The current reactions on up to 100 messages, keyed by message; a message with none is absent.
    public func getReactionSummaries(owner: KeyPair, conversationID: ConversationID, messageIDs: [MessageID]) async throws -> [MessageID: ReactionState] {
        try await withCheckedThrowingContinuation { c in
            chatMessagingService.getReactionSummaries(owner: owner, conversationID: conversationID, messageIDs: messageIDs) { c.resume(with: $0) }
        }
    }

    public func deleteMessage(
        owner: KeyPair,
        conversationID: ConversationID,
        messageID: MessageID,
        expectedEventSequence: UInt64
    ) async throws -> MessageMutation {
        try await withCheckedThrowingContinuation { c in
            chatMessagingService.deleteMessage(
                owner: owner,
                conversationID: conversationID,
                messageID: messageID,
                expectedEventSequence: expectedEventSequence
            ) { c.resume(with: $0) }
        }
    }

    public func markRead(owner: KeyPair, conversationID: ConversationID, messageID: MessageID) async throws {
        try await withCheckedThrowingContinuation { c in
            chatMessagingService.advancePointer(owner: owner, conversationID: conversationID, messageID: messageID) { c.resume(with: $0) }
        }
    }

    public func notifyIsTyping(owner: KeyPair, conversationID: ConversationID, state: TypingState) async throws {
        try await withCheckedThrowingContinuation { c in
            chatMessagingService.notifyIsTyping(owner: owner, conversationID: conversationID, state: state) { c.resume(with: $0) }
        }
    }

    // MARK: - Event stream

    /// Attach this session's consumer to the single per-user event stream, returning fresh decoded-event
    /// and connection-state streams and opening the stream for `owner`. Each session gets its own pair —
    /// see `EventStreamer.subscribe` for why reusing one across sessions strands a switched-to account.
    public nonisolated func subscribeConversationStream(owner: KeyPair) async -> (events: AsyncStream<ConversationStreamEvent>, connectionState: AsyncStream<EventStreamConnectionState>) {
        await eventStreamer.subscribe(owner: owner)
    }

    public nonisolated func ensureConversationStreamConnected() {
        Task { await eventStreamer.ensureConnected() }
    }

    public nonisolated func closeConversationStream() {
        Task { await eventStreamer.stop() }
    }

    // MARK: - Private chats -

    /// Enters the lobby of the private chat `conversationID` to wait for an admin to admit the
    /// signed-in user.
    public func enterLobby(owner: KeyPair, conversationID: ConversationID) async throws -> Lobby {
        try await withCheckedThrowingContinuation { c in
            chatService.enterLobby(owner: owner, conversationID: conversationID) { c.resume(with: $0) }
        }
    }

    /// Leaves the lobby of `conversationID`, withdrawing the request to join.
    public func leaveLobby(owner: KeyPair, conversationID: ConversationID) async throws {
        try await withCheckedThrowingContinuation { c in
            chatService.leaveLobby(owner: owner, conversationID: conversationID) { c.resume(with: $0) }
        }
    }

    /// Pages `conversationID`'s lobby to exhaustion. Members entering or leaving mid-read arrive
    /// as `ConversationStreamEvent.lobbyChanged`, so the caller should already be consuming the
    /// event stream.
    public func getLobbyMembers(owner: KeyPair, conversationID: ConversationID) async throws -> [LobbyMember] {
        var all: [LobbyMember] = []
        var pagingToken: Data?

        while true {
            let page = try await withCheckedThrowingContinuation { c in
                chatService.getLobbyMembers(owner: owner, conversationID: conversationID, pagingToken: pagingToken) { c.resume(with: $0) }
            }
            all.append(contentsOf: page.members)
            if !page.hasMore { break }
            pagingToken = page.pagingToken
        }

        return all
    }

    /// Admits `userID` from `conversationID`'s lobby, handing them the chat key wrapped in
    /// `keyEnvelope`. The envelope is opaque to this layer.
    public func admitLobbyMember(owner: KeyPair, conversationID: ConversationID, userID: UserID, keyEnvelope: ConversationKeyEnvelope) async throws {
        try await withCheckedThrowingContinuation { c in
            chatService.admitLobbyMember(owner: owner, conversationID: conversationID, userID: userID, keyEnvelope: keyEnvelope) { c.resume(with: $0) }
        }
    }

    /// Turns `userID` away from `conversationID`'s lobby.
    public func denyLobbyMember(owner: KeyPair, conversationID: ConversationID, userID: UserID) async throws {
        try await withCheckedThrowingContinuation { c in
            chatService.denyLobbyMember(owner: owner, conversationID: conversationID, userID: userID) { c.resume(with: $0) }
        }
    }

    /// Stores the signed-in user's wrapped copy of `conversationID`'s chat key. Throws
    /// `ErrorSetKeyEnvelope.alreadySet` once one is stored.
    public func setKeyEnvelope(owner: KeyPair, conversationID: ConversationID, keyEnvelope: ConversationKeyEnvelope) async throws {
        try await withCheckedThrowingContinuation { c in
            chatService.setKeyEnvelope(owner: owner, conversationID: conversationID, keyEnvelope: keyEnvelope) { c.resume(with: $0) }
        }
    }

    /// Fetches the chat key `conversationID` wrapped for the signed-in user and who wrapped it, or
    /// the invite's copy for a member who joined by invite and hasn't stored their own yet.
    public func getKeyEnvelope(owner: KeyPair, conversationID: ConversationID) async throws -> GroupKeyMaterial {
        let result = try await withCheckedThrowingContinuation { c in
            chatService.getKeyEnvelope(owner: owner, conversationID: conversationID) { c.resume(with: $0) }
        }
        return result.material
    }

    // MARK: - Invites -

    /// Creates an invite to a private group the caller may invite to (``ConversationViewerState/canInvite``).
    /// Idempotent on `token`; `maxUses` of `0` means unlimited. The caller supplies the envelopes —
    /// ``InviteSealing/mint(secret:owner:conversationID:groupKey:)`` derives and seals them.
    public func createInvite(owner: KeyPair, conversationID: ConversationID, token: InviteToken, keyEnvelope: InviteKeyEnvelope, secretEnvelope: InviteSecretEnvelope, maxUses: UInt32 = 0, expiresAt: Date? = nil) async throws -> Invite {
        try await withCheckedThrowingContinuation { c in
            chatService.createInvite(owner: owner, conversationID: conversationID, token: token, keyEnvelope: keyEnvelope, secretEnvelope: secretEnvelope, maxUses: maxUses, expiresAt: expiresAt) { c.resume(with: $0) }
        }
    }

    /// Reads the group an invite is for and the invite's status. `owner` is optional: the read is
    /// allowed anonymously.
    public func getInvite(owner: KeyPair?, token: InviteToken) async throws -> (conversation: Conversation, status: Invite.Status) {
        let preview = try await withCheckedThrowingContinuation { c in
            chatService.getInvite(owner: owner, token: token) { c.resume(with: $0) }
        }
        return (preview.conversation, preview.status)
    }

    /// A group's invites, paged to exhaustion.
    public func getChatInvites(owner: KeyPair, conversationID: ConversationID) async throws -> [Invite] {
        var invites: [Invite] = []
        var pagingToken: Data?

        while true {
            let page = try await withCheckedThrowingContinuation { c in
                chatService.getChatInvites(owner: owner, conversationID: conversationID, pagingToken: pagingToken) { c.resume(with: $0) }
            }
            invites.append(contentsOf: page.invites)
            if !page.hasMore { break }
            pagingToken = page.pagingToken
        }

        return invites
    }

    /// Revokes an invite. A ban does not stop a link holder, so revoke the invite too when banning.
    public func revokeInvite(owner: KeyPair, conversationID: ConversationID, inviteID: InviteID) async throws {
        try await withCheckedThrowingContinuation { c in
            chatService.revokeInvite(owner: owner, conversationID: conversationID, inviteID: inviteID) { c.resume(with: $0) }
        }
    }
}
