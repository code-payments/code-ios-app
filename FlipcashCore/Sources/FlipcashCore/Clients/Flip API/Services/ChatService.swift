//
//  ChatService.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI
import GRPCCore

private let logger = Logger(label: "flipcash.chat-service")

final class ChatService: Sendable {

    private let service: Flipcash_Chat_V1_Chat.Client<AppTransport>

    init(client: GRPCClient<AppTransport>) {
        self.service = Flipcash_Chat_V1_Chat.Client(wrapping: client)
    }

    struct DmFeedPage: Sendable {
        let conversations: [Conversation]
        let pagingToken: Data
        let hasMore: Bool
    }

    func getDmChatFeed(owner: KeyPair, type: ConversationType, pageSize: Int = 50, pagingToken: Data?, completion: @Sendable @escaping (Result<DmFeedPage, ErrorGetDmChatFeed>) -> Void) {
        let request = Flipcash_Chat_V1_GetDmChatFeedRequest.with {
            $0.queryOptions = .with {
                $0.pageSize = Int32(pageSize)
                if let pagingToken {
                    $0.pagingToken = .with { $0.value = pagingToken }
                }
            }
            $0.dmChatType = type.proto
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.getDmChatFeed(request, options: .unaryDefault)
                let error = ErrorGetDmChatFeed(rawValue: response.result.rawValue) ?? .unknown
                guard error == .ok else {
                    logger.error("Failed to fetch DM chat feed")
                    await MainActor.run { completion(.failure(error)) }
                    return
                }
                let page = DmFeedPage(
                    conversations: response.chats.map(Conversation.init),
                    pagingToken: response.pagingToken.value,
                    hasMore: response.hasMore_p
                )
                await MainActor.run { completion(.success(page)) }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    func getChat(owner: KeyPair, conversationID: ConversationID, viewMode: ConversationViewMode = .full, completion: @Sendable @escaping (Result<Conversation, ErrorGetChat>) -> Void) {
        let request = Flipcash_Chat_V1_GetChatRequest.with {
            $0.chatID = conversationID.proto
            $0.viewMode = viewMode.proto
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.getChat(request, options: .unaryDefault)
                let error = ErrorGetChat(rawValue: response.result.rawValue) ?? .unknown
                guard error == .ok, response.hasMetadata else {
                    logger.error("Failed to fetch chat")
                    await MainActor.run { completion(.failure(error == .ok ? .notFound : error)) }
                    return
                }
                await MainActor.run { completion(.success(Conversation(response.metadata))) }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }
    struct GroupFeedPage: Sendable {
        let conversations: [Conversation]
        let pagingToken: Data
        let hasMore: Bool
    }

    func getGroupChatFeed(owner: KeyPair, pageSize: Int = 50, pagingToken: Data?, completion: @Sendable @escaping (Result<GroupFeedPage, ErrorGetGroupChatFeed>) -> Void) {
        let request = Flipcash_Chat_V1_GetGroupChatFeedRequest.with {
            $0.queryOptions = .with {
                $0.pageSize = Int32(pageSize)
                if let pagingToken {
                    $0.pagingToken = .with { $0.value = pagingToken }
                }
            }
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.getGroupChatFeed(request, options: .unaryDefault)
                let error = ErrorGetGroupChatFeed(rawValue: response.result.rawValue) ?? .unknown
                guard error == .ok else {
                    logger.error("Failed to fetch group chat feed")
                    await MainActor.run { completion(.failure(error)) }
                    return
                }
                let page = GroupFeedPage(
                    conversations: response.chats.map(Conversation.init),
                    pagingToken: response.pagingToken.value,
                    hasMore: response.hasMore_p
                )
                await MainActor.run { completion(.success(page)) }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    /// Starts a new group chat. `pictureBlobID` must already be `READY` (uploaded via
    /// `BlobService`); `rules` gate who may read/join and who may send — `nil` means no
    /// restrictions. On `.titleModerated` the server also reports which category flagged the
    /// title; `ErrorStartChat.titleModerated` carries it through so callers can say why, not just
    /// that the title was rejected. `description`, when non-empty, is moderated the same way and
    /// reports `.descriptionModerated`; `nil` or empty sets none.
    ///
    /// `idempotencyKey` is required by the server: caller and key together identify the chat being
    /// created, so a retry with the same key returns the original chat (result `.ok`) rather than
    /// creating a duplicate, even if `title`/`pictureBlobID`/`rules` differ on the retry. Mint it once
    /// where the user's intent to create the chat originates and reuse it for every retry of that same
    /// attempt — never generate a fresh key per call, or retries lose their idempotency.
    func startChat(owner: KeyPair, title: String, description: String? = nil, pictureBlobID: BlobID?, rules: ConversationRules?, idempotencyKey: UUID, completion: @Sendable @escaping (Result<Conversation, ErrorStartChat>) -> Void) {
        let request = Flipcash_Chat_V1_StartChatRequest.with {
            $0.publicGroup = .with {
                $0.title = title
                if let description, !description.isEmpty {
                    $0.description_p = description
                }
                if let pictureBlobID {
                    $0.profilePicture = .with { $0.value = pictureBlobID.data }
                }
                if let rules {
                    $0.rules = rules.proto
                }
            }
            $0.idempotencyKey = .with { $0.value = idempotencyKey.data }
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.startChat(request, options: .unaryDefault)
                guard response.result == .ok else {
                    logger.error("Failed to start chat")
                    await MainActor.run { completion(.failure(ErrorStartChat(response.result, flaggedCategory: response.flaggedCategory))) }
                    return
                }
                guard response.hasChat else {
                    logger.error("Failed to start chat")
                    await MainActor.run { completion(.failure(.unknown)) }
                    return
                }
                await MainActor.run { completion(.success(Conversation(response.chat))) }
            } catch let error as RPCError {
                // The six StartChat results all arrive as `.ok`-shaped responses, so a transport
                // status is the one failure whose cause isn't in the result — name its code.
                logger.error("Failed to start chat at the transport", metadata: ["code": "\(error.code)"])
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    func joinChat(owner: KeyPair, conversationID: ConversationID, completion: @Sendable @escaping (Result<Conversation, ErrorJoinChat>) -> Void) {
        let request = Flipcash_Chat_V1_JoinChatRequest.with {
            $0.chatID = conversationID.proto
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.joinChat(request, options: .unaryDefault)
                let error = ErrorJoinChat(rawValue: response.result.rawValue) ?? .unknown
                guard error == .ok, response.hasChat else {
                    logger.error("Failed to join chat")
                    await MainActor.run { completion(.failure(error == .ok ? .unknown : error)) }
                    return
                }
                await MainActor.run { completion(.success(Conversation(response.chat))) }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    func leaveChat(owner: KeyPair, conversationID: ConversationID, completion: @Sendable @escaping (Result<Void, ErrorLeaveChat>) -> Void) {
        let request = Flipcash_Chat_V1_LeaveChatRequest.with {
            $0.chatID = conversationID.proto
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.leaveChat(request, options: .unaryDefault)
                let error = ErrorLeaveChat(rawValue: response.result.rawValue) ?? .unknown
                guard error == .ok else {
                    logger.error("Failed to leave chat")
                    await MainActor.run { completion(.failure(error)) }
                    return
                }
                await MainActor.run { completion(.success(())) }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    func muteChat(owner: KeyPair, conversationID: ConversationID, mute: ConversationMuteState, completion: @Sendable @escaping (Result<ConversationViewerState, ErrorMuteChat>) -> Void) {
        let request = Flipcash_Chat_V1_MuteChatRequest.with {
            $0.chatID = conversationID.proto
            $0.mute = mute.proto
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.muteChat(request, options: .unaryDefault)
                let error = ErrorMuteChat(rawValue: response.result.rawValue) ?? .unknown
                guard error == .ok, response.hasViewerState else {
                    logger.error("Failed to mute chat")
                    await MainActor.run { completion(.failure(error == .ok ? .unknown : error)) }
                    return
                }
                await MainActor.run { completion(.success(ConversationViewerState(response.viewerState))) }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    func unmuteChat(owner: KeyPair, conversationID: ConversationID, completion: @Sendable @escaping (Result<ConversationViewerState, ErrorUnmuteChat>) -> Void) {
        let request = Flipcash_Chat_V1_UnmuteChatRequest.with {
            $0.chatID = conversationID.proto
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.unmuteChat(request, options: .unaryDefault)
                let error = ErrorUnmuteChat(rawValue: response.result.rawValue) ?? .unknown
                guard error == .ok, response.hasViewerState else {
                    logger.error("Failed to unmute chat")
                    await MainActor.run { completion(.failure(error == .ok ? .unknown : error)) }
                    return
                }
                await MainActor.run { completion(.success(ConversationViewerState(response.viewerState))) }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    struct RosterFeedPage: Sendable {
        let members: [ConversationMember]
        let rosterSummary: ConversationRosterSummary
        let pagingToken: Data
        let hasMore: Bool
    }

    /// Pages a chat's roster, most recently joined first. Leave `pagingToken` `nil` on the first
    /// call; on every later call pass back the previous page's `pagingToken` — it is opaque,
    /// server-generated, and bound to `conversationID`. `pageSize` is capped at 100 server-side.
    ///
    /// A page may lag the returned `rosterSummary` for a large group (see `chat.v1.GetRoster`'s
    /// staleness contract) — callers must merge each page against what the event stream has already
    /// told them, by ``ConversationMember/version``, greater winning, rather than trusting a page to
    /// be a complete, current snapshot.
    func getRoster(owner: KeyPair, conversationID: ConversationID, pageSize: Int = 50, pagingToken: Data?, completion: @Sendable @escaping (Result<RosterFeedPage, ErrorGetRoster>) -> Void) {
        let request = Flipcash_Chat_V1_GetRosterRequest.with {
            $0.chatID = conversationID.proto
            $0.queryOptions = .with {
                $0.pageSize = Int32(pageSize)
                if let pagingToken {
                    $0.pagingToken = .with { $0.value = pagingToken }
                }
            }
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.getRoster(request, options: .unaryDefault)
                guard response.result == .ok else {
                    logger.error("Failed to fetch roster")
                    await MainActor.run { completion(.failure(ErrorGetRoster(response.result))) }
                    return
                }
                guard response.hasRosterSummary else {
                    logger.error("Failed to fetch roster")
                    await MainActor.run { completion(.failure(.unknown)) }
                    return
                }
                let page = RosterFeedPage(
                    members: response.members.map(ConversationMember.init),
                    rosterSummary: ConversationRosterSummary(response.rosterSummary),
                    pagingToken: response.pagingToken.value,
                    hasMore: response.hasMore_p
                )
                await MainActor.run { completion(.success(page)) }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    /// Fetches the people to suggest after an `@` in a group chat, most relevant first. The pool is
    /// neither paged nor complete: the caller filters it locally as the user types. A DM is `.denied`.
    func getMentionSuggestions(owner: KeyPair, conversationID: ConversationID, completion: @Sendable @escaping (Result<[MentionSuggestion], ErrorGetMentionSuggestions>) -> Void) {
        let request = Flipcash_Chat_V1_GetMentionSuggestionsRequest.with {
            $0.chatID = conversationID.proto
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.getMentionSuggestions(request, options: .unaryDefault)
                guard response.result == .ok else {
                    logger.error("Failed to fetch mention suggestions", metadata: ["result": "\(response.result)"])
                    await MainActor.run { completion(.failure(ErrorGetMentionSuggestions(response.result))) }
                    return
                }
                let suggestions = response.suggestions.compactMap(MentionSuggestion.init)
                await MainActor.run { completion(.success(suggestions)) }
            } catch let error as RPCError {
                logger.error("Failed to fetch mention suggestions at the transport", metadata: [
                    "code": "\(error.code)",
                    "message": "\(error.message)",
                ])
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    /// Edits a group chat's title, description, picture, and/or cover picture. Every field is optional — only fields set on the
    /// request change, atomically; a request that sets nothing is a no-op returning `.ok`. Only a
    /// member the server permits to edit (``ConversationViewerState/canEdit``) may call this; anyone
    /// else is `.denied`.
    ///
    /// `pictureBlobID` and `coverPictureBlobID`, when supplied, must already be `READY` (uploaded via
    /// `BlobService`) — this call does not upload them, mirroring `startChat`'s `pictureBlobID` contract. On `.titleModerated`
    /// the server also reports which category flagged the title, carried the same way
    /// `ErrorStartChat.titleModerated` carries it; `.descriptionModerated` works the same way.
    ///
    /// `description` is ``ConversationDescriptionEdit/unchanged`` by default; use `.clear` to remove
    /// an existing description.
    func editChat(owner: KeyPair, conversationID: ConversationID, title: String?, description: ConversationDescriptionEdit = .unchanged, pictureBlobID: BlobID?, coverPictureBlobID: BlobID? = nil, completion: @Sendable @escaping (Result<Conversation, ErrorEditChat>) -> Void) {
        let request = Self.editChatRequest(
            owner: owner,
            conversationID: conversationID,
            title: title,
            description: description,
            pictureBlobID: pictureBlobID,
            coverPictureBlobID: coverPictureBlobID
        )

        Task {
            do {
                let response = try await service.editChat(request, options: .unaryDefault)
                guard response.result == .ok else {
                    logger.error("Failed to edit chat")
                    await MainActor.run { completion(.failure(ErrorEditChat(response.result, flaggedCategory: response.flaggedCategory))) }
                    return
                }
                guard response.hasChat else {
                    logger.error("Failed to edit chat")
                    await MainActor.run { completion(.failure(.unknown)) }
                    return
                }
                await MainActor.run { completion(.success(Conversation(response.chat))) }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    /// The signed `EditChat` request; a nil title or blob and an `.unchanged` description leave that
    /// field unset, so the server keeps its current value.
    static func editChatRequest(owner: KeyPair, conversationID: ConversationID, title: String?, description: ConversationDescriptionEdit, pictureBlobID: BlobID?, coverPictureBlobID: BlobID?) -> Flipcash_Chat_V1_EditChatRequest {
        Flipcash_Chat_V1_EditChatRequest.with {
            $0.chatID = conversationID.proto
            if let title {
                $0.title = .with { $0.value = title }
            }
            if let description = description.proto {
                $0.description_p = description
            }
            if let pictureBlobID {
                $0.profilePicture = .with { $0.blobID = .with { $0.value = pictureBlobID.data } }
            }
            if let coverPictureBlobID {
                $0.coverPicture = .with { $0.blobID = .with { $0.value = coverPictureBlobID.data } }
            }
            $0.auth = owner.authFor(message: $0)
        }
    }

    struct SampledChattersPage: Sendable {
        let chatters: [SampledChatter]
        let hasMore: Bool
    }

    /// Samples up to 100 recent chatters of a public group, the roster alternative for a viewer who
    /// is not a member. A private group or a DM is `.denied`. A public group needs no auth, so
    /// `owner` is optional.
    func sampleChatters(owner: KeyPair?, conversationID: ConversationID, completion: @Sendable @escaping (Result<SampledChattersPage, ErrorSampleChatters>) -> Void) {
        let request = Flipcash_Chat_V1_SampleChattersRequest.with {
            $0.chatID = conversationID.proto
            if let owner {
                $0.auth = owner.authFor(message: $0)
            }
        }

        Task {
            do {
                let response = try await service.sampleChatters(request, options: .unaryDefault)
                guard response.result == .ok else {
                    logger.error("Failed to sample chatters", metadata: ["result": "\(response.result)"])
                    await MainActor.run { completion(.failure(ErrorSampleChatters(response.result))) }
                    return
                }
                let page = SampledChattersPage(
                    chatters: response.chatters.compactMap(SampledChatter.init),
                    hasMore: response.hasMore_p
                )
                await MainActor.run { completion(.success(page)) }
            } catch let error as RPCError {
                logger.error("Failed to sample chatters at the transport", metadata: ["code": "\(error.code)"])
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    /// Replaces the signed-in user's featured groups with `conversationIDs` (at most 10, in order)
    /// and returns the resulting list. A private group is `.denied`.
    func setFeaturedGroups(owner: KeyPair, conversationIDs: [ConversationID], completion: @Sendable @escaping (Result<[Conversation], ErrorSetFeaturedGroups>) -> Void) {
        let request = Flipcash_Chat_V1_SetFeaturedGroupsRequest.with {
            $0.chatIds = conversationIDs.map(\.proto)
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.setFeaturedGroups(request, options: .unaryDefault)
                guard response.result == .ok else {
                    logger.error("Failed to set featured groups", metadata: ["result": "\(response.result)"])
                    await MainActor.run { completion(.failure(ErrorSetFeaturedGroups(response.result))) }
                    return
                }
                let groups = response.featuredGroups.map(Conversation.init)
                await MainActor.run { completion(.success(groups)) }
            } catch let error as RPCError {
                logger.error("Failed to set featured groups at the transport", metadata: ["code": "\(error.code)"])
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    /// Fetches the groups `username` features. The groups are list-view shaped: no members, viewer
    /// state, last message or cover picture. Auth is optional, so `owner` may be `nil`.
    func getFeaturedGroups(owner: KeyPair?, username: Username, completion: @Sendable @escaping (Result<[Conversation], ErrorGetFeaturedGroups>) -> Void) {
        let request = Flipcash_Chat_V1_GetFeaturedGroupsRequest.with {
            $0.username = username.proto
            if let owner {
                $0.auth = owner.authFor(message: $0)
            }
        }

        Task {
            do {
                let response = try await service.getFeaturedGroups(request, options: .unaryDefault)
                guard response.result == .ok else {
                    logger.error("Failed to fetch featured groups", metadata: ["result": "\(response.result)"])
                    await MainActor.run { completion(.failure(ErrorGetFeaturedGroups(response.result))) }
                    return
                }
                let groups = response.featuredGroups.map(Conversation.init)
                await MainActor.run { completion(.success(groups)) }
            } catch let error as RPCError {
                logger.error("Failed to fetch featured groups at the transport", metadata: ["code": "\(error.code)"])
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    // MARK: - Private chats -
    // The lobby and key-envelope RPCs of a private group. The envelope is passed through as opaque
    // bytes; this layer never wraps or unwraps a chat key.

    /// Enters the lobby of the private chat `conversationID`, to wait for an admin to admit the
    /// signed-in user. Returns the lobby entry on success.
    func enterLobby(owner: KeyPair, conversationID: ConversationID, completion: @Sendable @escaping (Result<Lobby, ErrorEnterLobby>) -> Void) {
        let request = Flipcash_Chat_V1_EnterLobbyRequest.with {
            $0.chatID = conversationID.proto
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.enterLobby(request, options: .unaryDefault)
                let error = ErrorEnterLobby(rawValue: response.result.rawValue) ?? .unknown
                guard error == .ok, let lobby = Lobby(response.lobby) else {
                    logger.error("Failed to enter lobby")
                    await MainActor.run { completion(.failure(error == .ok ? .unknown : error)) }
                    return
                }
                await MainActor.run { completion(.success(lobby)) }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    /// Leaves the lobby of `conversationID`, withdrawing the request to join.
    func leaveLobby(owner: KeyPair, conversationID: ConversationID, completion: @Sendable @escaping (Result<Void, ErrorLeaveLobby>) -> Void) {
        let request = Flipcash_Chat_V1_LeaveLobbyRequest.with {
            $0.chatID = conversationID.proto
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.leaveLobby(request, options: .unaryDefault)
                let error = ErrorLeaveLobby(rawValue: response.result.rawValue) ?? .unknown
                guard error == .ok else {
                    logger.error("Failed to leave lobby")
                    await MainActor.run { completion(.failure(error)) }
                    return
                }
                await MainActor.run { completion(.success(())) }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    struct LobbyMembersPage: Sendable {
        let members: [LobbyMember]
        let pagingToken: Data
        let hasMore: Bool
    }

    /// Pages the users waiting in `conversationID`'s lobby. Leave `pagingToken` `nil` on the first
    /// call; on every later call pass back the previous page's `pagingToken`. `pageSize` is capped
    /// at 100 server-side. A member whose public key does not parse is dropped from the page.
    func getLobbyMembers(owner: KeyPair, conversationID: ConversationID, pageSize: Int = 50, pagingToken: Data?, completion: @Sendable @escaping (Result<LobbyMembersPage, ErrorGetLobbyMembers>) -> Void) {
        let request = Flipcash_Chat_V1_GetLobbyMembersRequest.with {
            $0.chatID = conversationID.proto
            $0.queryOptions = .with {
                $0.pageSize = Int32(pageSize)
                if let pagingToken {
                    $0.pagingToken = .with { $0.value = pagingToken }
                }
            }
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.getLobbyMembers(request, options: .unaryDefault)
                let error = ErrorGetLobbyMembers(rawValue: response.result.rawValue) ?? .unknown
                guard error == .ok else {
                    logger.error("Failed to fetch lobby members")
                    await MainActor.run { completion(.failure(error)) }
                    return
                }
                let page = LobbyMembersPage(
                    members: response.members.compactMap(LobbyMember.init),
                    pagingToken: response.pagingToken.value,
                    hasMore: response.hasMore_p
                )
                await MainActor.run { completion(.success(page)) }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    /// Admits `userID` from `conversationID`'s lobby, handing them the chat key wrapped in
    /// `keyEnvelope`.
    func admitLobbyMember(owner: KeyPair, conversationID: ConversationID, userID: UserID, keyEnvelope: ConversationKeyEnvelope, completion: @Sendable @escaping (Result<Void, ErrorAdmitLobbyMember>) -> Void) {
        let request = Flipcash_Chat_V1_AdmitLobbyMemberRequest.with {
            $0.chatID = conversationID.proto
            $0.userID = .with { $0.value = userID.data }
            $0.keyEnvelope = keyEnvelope.proto
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.admitLobbyMember(request, options: .unaryDefault)
                let error = ErrorAdmitLobbyMember(rawValue: response.result.rawValue) ?? .unknown
                guard error == .ok else {
                    logger.error("Failed to admit lobby member")
                    await MainActor.run { completion(.failure(error)) }
                    return
                }
                await MainActor.run { completion(.success(())) }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    /// Turns `userID` away from `conversationID`'s lobby.
    func denyLobbyMember(owner: KeyPair, conversationID: ConversationID, userID: UserID, completion: @Sendable @escaping (Result<Void, ErrorDenyLobbyMember>) -> Void) {
        let request = Flipcash_Chat_V1_DenyLobbyMemberRequest.with {
            $0.chatID = conversationID.proto
            $0.userID = .with { $0.value = userID.data }
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.denyLobbyMember(request, options: .unaryDefault)
                let error = ErrorDenyLobbyMember(rawValue: response.result.rawValue) ?? .unknown
                guard error == .ok else {
                    logger.error("Failed to deny lobby member")
                    await MainActor.run { completion(.failure(error)) }
                    return
                }
                await MainActor.run { completion(.success(())) }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    /// Stores the signed-in user's wrapped copy of `conversationID`'s chat key. Rejected with
    /// `.alreadySet` once one is stored.
    func setKeyEnvelope(owner: KeyPair, conversationID: ConversationID, keyEnvelope: ConversationKeyEnvelope, completion: @Sendable @escaping (Result<Void, ErrorSetKeyEnvelope>) -> Void) {
        let request = Flipcash_Chat_V1_SetKeyEnvelopeRequest.with {
            $0.chatID = conversationID.proto
            $0.keyEnvelope = keyEnvelope.proto
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.setKeyEnvelope(request, options: .unaryDefault)
                let error = ErrorSetKeyEnvelope(rawValue: response.result.rawValue) ?? .unknown
                guard error == .ok else {
                    logger.error("Failed to set key envelope")
                    await MainActor.run { completion(.failure(error)) }
                    return
                }
                await MainActor.run { completion(.success(())) }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    struct KeyEnvelopeResult: Sendable {
        let envelope: ConversationKeyEnvelope
        /// The member who wrapped the chat key for the signed-in user.
        let wrappedBy: UserID?
    }

    /// Fetches the chat key `conversationID` wrapped for the signed-in user, along with who
    /// wrapped it.
    func getKeyEnvelope(owner: KeyPair, conversationID: ConversationID, completion: @Sendable @escaping (Result<KeyEnvelopeResult, ErrorGetKeyEnvelope>) -> Void) {
        let request = Flipcash_Chat_V1_GetKeyEnvelopeRequest.with {
            $0.chatID = conversationID.proto
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.getKeyEnvelope(request, options: .unaryDefault)
                let error = ErrorGetKeyEnvelope(rawValue: response.result.rawValue) ?? .unknown
                guard error == .ok, response.hasKeyEnvelope else {
                    logger.error("Failed to fetch key envelope")
                    await MainActor.run { completion(.failure(error == .ok ? .unknown : error)) }
                    return
                }
                let result = KeyEnvelopeResult(
                    envelope: ConversationKeyEnvelope(response.keyEnvelope),
                    wrappedBy: response.hasWrappedBy ? try? UUID(data: response.wrappedBy.value) : nil
                )
                await MainActor.run { completion(.success(result)) }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }
}

// MARK: - Errors -

public enum ErrorGetDmChatFeed: Int, Error {
    case ok
    case denied
    case notFound
    case unknown          = -1
    case transportFailure = -2
    case cancelled = -3
    case rejected = -4
}

public enum ErrorGetChat: Int, Error {
    case ok
    case denied
    case notFound
    case unknown          = -1
    case transportFailure = -2
    case cancelled = -3
    case rejected = -4
}

public enum ErrorGetGroupChatFeed: Int, Error {
    case ok
    case denied
    case notFound
    case unknown          = -1
    case transportFailure = -2
    case cancelled = -3
    case rejected = -4
}

/// Associated-value error, modelled on `ErrorProfile`, so `.titleModerated` can carry the
/// `flaggedCategory` the server reports for it — the moderation category the plain-Int pattern
/// used by this file's other error enums has no room for. No `.ok` case: a success response
/// resolves to `Conversation` in `startChat`'s `Result`, it never reaches this type.
public enum ErrorStartChat: Error, Sendable, Equatable {
    case denied
    case titleModerated(Flipcash_Moderation_V1_FlaggedCategory)
    case pictureBlobNotAccepted
    case invalidRules
    case rulesNotSatisfied
    case descriptionModerated(Flipcash_Moderation_V1_FlaggedCategory)
    case coverPictureBlobNotAccepted
    case unknown
    case transportFailure
    case cancelled
    case rejected
}

public enum ErrorJoinChat: Int, Error {
    case ok
    case denied
    case notFound
    case rulesNotSatisfied
    case unknown          = -1
    case transportFailure = -2
    case cancelled = -3
    case rejected = -4
}

public enum ErrorLeaveChat: Int, Error {
    case ok
    case denied
    case notFound
    case unknown          = -1
    case transportFailure = -2
    case cancelled = -3
    case rejected = -4
}

public enum ErrorMuteChat: Int, Error {
    case ok
    case denied
    case notFound
    case unknown          = -1
    case transportFailure = -2
    case cancelled = -3
    case rejected = -4
}

public enum ErrorUnmuteChat: Int, Error {
    case ok
    case denied
    case notFound
    case unknown          = -1
    case transportFailure = -2
    case cancelled = -3
    case rejected = -4
}

/// No `.ok` case: a success response resolves to `RosterFeedPage` in `ChatService.getRoster`'s `Result`,
/// it never reaches this type. Mapped explicitly from `GetRosterResponse.Result` — see
/// `ErrorGetRoster.init(_:)` — rather than via positional `rawValue:`, per this repo's convention for
/// a new result enum (`ErrorStartChat`, `ErrorEditChat`).
public enum ErrorGetRoster: Error, Sendable, Equatable {
    case denied
    case notFound
    case unknown
    case transportFailure
    case cancelled
    case rejected
}

/// Mapped explicitly from `GetMentionSuggestionsResponse.Result` — see
/// `ErrorGetMentionSuggestions.init(_:)` — like ``ErrorGetRoster``.
public enum ErrorGetMentionSuggestions: Error, Sendable, Equatable {
    case denied
    case notFound
    case unknown
    case transportFailure
    case cancelled
    case rejected
}

/// No `.ok` case, and modelled on `ErrorStartChat` for the same reason: `.titleModerated` carries the
/// `flaggedCategory` the server reports for it. Mapped explicitly from `EditChatResponse.Result` — see
/// `ErrorEditChat.init(_:flaggedCategory:)` — never via positional `rawValue:`, since
/// `EditChatResponse.Result` has six cases against this file's usual three and a coincidental
/// positional match would silently break the day a case is inserted upstream.
public enum ErrorEditChat: Error, Sendable, Equatable {
    case denied
    case notFound
    case titleModerated(Flipcash_Moderation_V1_FlaggedCategory)
    case pictureBlobNotAccepted
    case coverPictureBlobNotAccepted
    case descriptionModerated(Flipcash_Moderation_V1_FlaggedCategory)
    case unknown
    case transportFailure
    case cancelled
    case rejected
}

/// Mapped explicitly from `SampleChattersResponse.Result`; no `.ok` case, like ``ErrorGetRoster``.
public enum ErrorSampleChatters: Error, Sendable, Equatable {
    case denied
    case notFound
    case unknown
    case transportFailure
    case cancelled
    case rejected
}

/// Mapped explicitly from `SetFeaturedGroupsResponse.Result`; no `.ok` case, like ``ErrorGetRoster``.
public enum ErrorSetFeaturedGroups: Error, Sendable, Equatable {
    case denied
    case notFound
    case unknown
    case transportFailure
    case cancelled
    case rejected
}

/// Mapped explicitly from `GetFeaturedGroupsResponse.Result`; no `.ok` case, like ``ErrorGetRoster``.
public enum ErrorGetFeaturedGroups: Error, Sendable, Equatable {
    case notFound
    case unknown
    case transportFailure
    case cancelled
    case rejected
}

public enum ErrorEnterLobby: Int, Error {
    case ok
    case denied
    case notFound
    case alreadyMember
    case lobbyFull
    case tooManyLobbies
    case unknown          = -1
    case transportFailure = -2
    case cancelled = -3
    case rejected = -4
}

public enum ErrorLeaveLobby: Int, Error {
    case ok
    case denied
    case notFound
    case unknown          = -1
    case transportFailure = -2
    case cancelled = -3
    case rejected = -4
}

public enum ErrorGetLobbyMembers: Int, Error {
    case ok
    case denied
    case notFound
    case unknown          = -1
    case transportFailure = -2
    case cancelled = -3
    case rejected = -4
}

public enum ErrorAdmitLobbyMember: Int, Error {
    case ok
    case denied
    case notFound
    case notInLobby
    case unknown          = -1
    case transportFailure = -2
    case cancelled = -3
    case rejected = -4
}

public enum ErrorDenyLobbyMember: Int, Error {
    case ok
    case denied
    case notFound
    case unknown          = -1
    case transportFailure = -2
    case cancelled = -3
    case rejected = -4
}

public enum ErrorSetKeyEnvelope: Int, Error {
    case ok
    case denied
    case notFound
    case alreadySet
    case unknown          = -1
    case transportFailure = -2
    case cancelled = -3
    case rejected = -4
}

public enum ErrorGetKeyEnvelope: Int, Error {
    case ok
    case denied
    case notFound
    case noEnvelope
    case unknown          = -1
    case transportFailure = -2
    case cancelled = -3
    case rejected = -4
}

extension ErrorGetDmChatFeed: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .cancelled: .info
        case .denied, .notFound: .info
        case .unknown, .rejected: .error
        }
    }
}

extension ErrorGetChat: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .cancelled: .info
        case .denied, .notFound: .info
        case .unknown, .rejected: .error
        }
    }
}

extension ErrorGetGroupChatFeed: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .cancelled: .info
        case .denied, .notFound: .info
        case .unknown, .rejected: .error
        }
    }
}

extension ErrorStartChat: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .transportFailure: .suppressed
        case .cancelled: .info
        case .denied, .titleModerated, .pictureBlobNotAccepted, .coverPictureBlobNotAccepted, .invalidRules, .rulesNotSatisfied, .descriptionModerated: .info
        case .unknown, .rejected: .error
        }
    }
}

extension ErrorStartChat {
    /// Maps a non-`.ok` `StartChatResponse.Result` to its domain error, carrying `flaggedCategory`
    /// through on `.titleModerated` rather than flattening it. Pure and synchronous so the mapping is
    /// unit-testable without a live RPC. Callers only reach this once they've confirmed `result != .ok`;
    /// `.ok` itself resolves to `Conversation` in `ChatService.startChat`, not this type, but is handled
    /// here too (as `.unknown`) so the mapping is total over every case of the proto enum.
    init(_ result: Flipcash_Chat_V1_StartChatResponse.Result, flaggedCategory: Flipcash_Moderation_V1_FlaggedCategory) {
        switch result {
        case .ok:
            self = .unknown
        case .denied:
            self = .denied
        case .titleModerated:
            self = .titleModerated(flaggedCategory)
        case .profilePictureBlobNotAccepted:
            self = .pictureBlobNotAccepted
        case .invalidRules:
            self = .invalidRules
        case .rulesNotSatisfied:
            self = .rulesNotSatisfied
        case .descriptionModerated:
            self = .descriptionModerated(flaggedCategory)
        case .coverPictureBlobNotAccepted:
            self = .coverPictureBlobNotAccepted
        case .UNRECOGNIZED:
            self = .unknown
        }
    }
}

extension ErrorJoinChat: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .cancelled: .info
        case .denied, .notFound, .rulesNotSatisfied: .info
        case .unknown, .rejected: .error
        }
    }
}

extension ErrorLeaveChat: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .cancelled: .info
        case .denied, .notFound: .info
        case .unknown, .rejected: .error
        }
    }
}

extension ErrorMuteChat: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .cancelled: .info
        case .denied, .notFound: .info
        case .unknown, .rejected: .error
        }
    }
}

extension ErrorUnmuteChat: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .cancelled: .info
        case .denied, .notFound: .info
        case .unknown, .rejected: .error
        }
    }
}

extension ErrorEnterLobby: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .cancelled: .info
        case .denied, .notFound, .alreadyMember, .lobbyFull, .tooManyLobbies: .info
        case .unknown, .rejected: .error
        }
    }
}

extension ErrorLeaveLobby: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .cancelled: .info
        case .denied, .notFound: .info
        case .unknown, .rejected: .error
        }
    }
}

extension ErrorGetLobbyMembers: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .cancelled: .info
        case .denied, .notFound: .info
        case .unknown, .rejected: .error
        }
    }
}

extension ErrorAdmitLobbyMember: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .cancelled: .info
        case .denied, .notFound, .notInLobby: .info
        case .unknown, .rejected: .error
        }
    }
}

extension ErrorDenyLobbyMember: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .cancelled: .info
        case .denied, .notFound: .info
        case .unknown, .rejected: .error
        }
    }
}

extension ErrorSetKeyEnvelope: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .cancelled: .info
        case .denied, .notFound, .alreadySet: .info
        case .unknown, .rejected: .error
        }
    }
}

extension ErrorGetKeyEnvelope: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .cancelled: .info
        case .denied, .notFound, .noEnvelope: .info
        case .unknown, .rejected: .error
        }
    }
}

extension ErrorGetRoster: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .transportFailure: .suppressed
        case .cancelled: .info
        case .denied, .notFound: .info
        case .unknown, .rejected: .error
        }
    }
}

extension ErrorGetRoster {
    /// Maps a non-`.ok` `GetRosterResponse.Result` to its domain error. Pure and synchronous so the
    /// mapping is unit-testable without a live RPC, and total over the proto enum (`.ok` and
    /// `.UNRECOGNIZED` both fold to `.unknown`) even though callers only reach this once they've
    /// confirmed `result != .ok`.
    init(_ result: Flipcash_Chat_V1_GetRosterResponse.Result) {
        switch result {
        case .ok:
            self = .unknown
        case .denied:
            self = .denied
        case .notFound:
            self = .notFound
        case .UNRECOGNIZED:
            self = .unknown
        }
    }
}

extension ErrorGetMentionSuggestions: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .transportFailure: .suppressed
        case .cancelled: .info
        case .denied, .notFound: .info
        case .unknown, .rejected: .error
        }
    }
}

extension ErrorGetMentionSuggestions {
    /// Maps a non-`.ok` `GetMentionSuggestionsResponse.Result` to its domain error; total over the
    /// proto enum, with `.ok` and `.UNRECOGNIZED` folding to `.unknown`.
    init(_ result: Flipcash_Chat_V1_GetMentionSuggestionsResponse.Result) {
        switch result {
        case .ok:
            self = .unknown
        case .denied:
            self = .denied
        case .notFound:
            self = .notFound
        case .UNRECOGNIZED:
            self = .unknown
        }
    }
}

extension ErrorEditChat: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .transportFailure: .suppressed
        case .cancelled: .info
        case .denied, .notFound, .titleModerated, .pictureBlobNotAccepted, .coverPictureBlobNotAccepted, .descriptionModerated: .info
        case .unknown, .rejected: .error
        }
    }
}

extension ErrorEditChat {
    /// Maps a non-`.ok` `EditChatResponse.Result` to its domain error, carrying `flaggedCategory`
    /// through on `.titleModerated` the same way `ErrorStartChat.init(_:flaggedCategory:)` does.
    /// Pure, synchronous, and total over the proto enum; callers only reach this once they've
    /// confirmed `result != .ok`.
    init(_ result: Flipcash_Chat_V1_EditChatResponse.Result, flaggedCategory: Flipcash_Moderation_V1_FlaggedCategory) {
        switch result {
        case .ok:
            self = .unknown
        case .denied:
            self = .denied
        case .notFound:
            self = .notFound
        case .titleModerated:
            self = .titleModerated(flaggedCategory)
        case .profilePictureBlobNotAccepted:
            self = .pictureBlobNotAccepted
        case .coverPictureBlobNotAccepted:
            self = .coverPictureBlobNotAccepted
        case .descriptionModerated:
            self = .descriptionModerated(flaggedCategory)
        case .UNRECOGNIZED:
            self = .unknown
        }
    }
}

extension ErrorSampleChatters: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .transportFailure: .suppressed
        case .cancelled: .info
        case .denied, .notFound: .info
        case .unknown, .rejected: .error
        }
    }
}

extension ErrorSampleChatters {
    /// Maps a non-`.ok` `SampleChattersResponse.Result` to its domain error; total over the proto
    /// enum, with `.ok` and `.UNRECOGNIZED` folding to `.unknown`.
    init(_ result: Flipcash_Chat_V1_SampleChattersResponse.Result) {
        switch result {
        case .ok: self = .unknown
        case .denied: self = .denied
        case .notFound: self = .notFound
        case .UNRECOGNIZED: self = .unknown
        }
    }
}

extension ErrorSetFeaturedGroups: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .transportFailure: .suppressed
        case .cancelled: .info
        case .denied, .notFound: .info
        case .unknown, .rejected: .error
        }
    }
}

extension ErrorSetFeaturedGroups {
    /// Maps a non-`.ok` `SetFeaturedGroupsResponse.Result` to its domain error; total over the proto
    /// enum, with `.ok` and `.UNRECOGNIZED` folding to `.unknown`.
    init(_ result: Flipcash_Chat_V1_SetFeaturedGroupsResponse.Result) {
        switch result {
        case .ok: self = .unknown
        case .denied: self = .denied
        case .notFound: self = .notFound
        case .UNRECOGNIZED: self = .unknown
        }
    }
}

extension ErrorGetFeaturedGroups: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .transportFailure: .suppressed
        case .cancelled: .info
        case .notFound: .info
        case .unknown, .rejected: .error
        }
    }
}

extension ErrorGetFeaturedGroups {
    /// Maps a non-`.ok` `GetFeaturedGroupsResponse.Result` to its domain error; total over the proto
    /// enum, with `.ok` and `.UNRECOGNIZED` folding to `.unknown`.
    init(_ result: Flipcash_Chat_V1_GetFeaturedGroupsResponse.Result) {
        switch result {
        case .ok: self = .unknown
        case .notFound: self = .notFound
        case .UNRECOGNIZED: self = .unknown
        }
    }
}
