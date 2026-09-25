//
//  ChatMessagingService.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI
import GRPCCore

private let logger = Logger(label: "flipcash.chat-messaging-service")

/// The outcome of an edit or delete: the message state the server now holds, and whether that state
/// came back as a conflict — meaning another client's change won and this one did not apply.
public struct MessageMutation: Sendable, Equatable {
    public let message: ConversationMessage
    public let isConflict: Bool

    public init(message: ConversationMessage, isConflict: Bool) {
        self.message = message
        self.isConflict = isConflict
    }
}

/// Wraps the Core `messaging.v1` service (chat messages). Named distinctly from
/// the Payments-domain `MessagingService`, which handles bill rendezvous.
final class ChatMessagingService: Sendable {

    private let service: Flipcash_Messaging_V1_Messaging.Client<AppTransport>

    init(client: GRPCClient<AppTransport>) {
        self.service = Flipcash_Messaging_V1_Messaging.Client(wrapping: client)
    }

    /// Fetches one message by id, or nil when the server has no such message in the chat.
    func getMessage(owner: KeyPair, conversationID: ConversationID, messageID: MessageID, viewMode: ConversationViewMode = .full, completion: @Sendable @escaping (Result<ConversationMessage?, ErrorGetMessage>) -> Void) {
        let request = Flipcash_Messaging_V1_GetMessageRequest.with {
            $0.chatID = conversationID.proto
            $0.messageID = messageID.proto
            $0.viewMode = viewMode.proto
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.getMessage(request, options: .unaryDefault)
                let error = ErrorGetMessage(rawValue: response.result.rawValue) ?? .unknown
                switch error {
                case .ok:
                    await MainActor.run { completion(.success(ConversationMessage(response.message))) }
                case .notFound:
                    await MainActor.run { completion(.success(nil)) }
                case .denied, .unknown, .transportFailure, .cancelled, .rejected:
                    logger.error("Failed to fetch message")
                    await MainActor.run { completion(.failure(error)) }
                }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    /// Fetches the newest `pageSize` messages (descending on the wire — without
    /// an explicit order the server defaults to ascending and a long chat's
    /// first page would be its OLDEST messages), returned oldest-first.
    func getMessages(owner: KeyPair, conversationID: ConversationID, pageSize: Int = 50, pagingToken: Data?, viewMode: ConversationViewMode = .full, completion: @Sendable @escaping (Result<[ConversationMessage], ErrorGetMessages>) -> Void) {
        let request = Flipcash_Messaging_V1_GetMessagesRequest.with {
            $0.chatID = conversationID.proto
            $0.options = .with {
                $0.pageSize = Int32(pageSize)
                $0.order = .desc
                if let pagingToken {
                    $0.pagingToken = .with { $0.value = pagingToken }
                }
            }
            $0.viewMode = viewMode.proto
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.getMessages(request, options: .unaryDefault)
                let error = ErrorGetMessages(rawValue: response.result.rawValue) ?? .unknown
                switch error {
                case .ok:
                    await MainActor.run { completion(.success(Array(response.messages.messages.compactMap(ConversationMessage.init).reversed()))) }
                case .notFound:
                    // An empty page is reported as NOT_FOUND, not empty OK.
                    await MainActor.run { completion(.success([])) }
                case .denied, .unknown, .transportFailure, .cancelled, .rejected:
                    logger.error("Failed to fetch messages")
                    await MainActor.run { completion(.failure(error)) }
                }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    /// Reconnect/cold-boot catch-up: a BOUNDED server stream of the messages changed since
    /// `afterSequence`, up to the chat's head. Each data batch is delivered to `onBatch` with its
    /// `checkpointSequence` (the resume point through that batch) so the caller applies-and-persists
    /// incrementally — a mid-stream drop resumes from the last checkpoint. `completion` fires once with
    /// the chat's head (`latestSequence`) on clean completion, `.resetRequired` when the cursor is too
    /// far behind (caller re-syncs via `getMessages`), or a transport/denied failure. No deadline: a
    /// bounded stream must not be truncated by one.
    func getDelta(
        owner: KeyPair,
        conversationID: ConversationID,
        afterSequence: UInt64,
        viewMode: ConversationViewMode = .full,
        onBatch: @MainActor @Sendable @escaping (_ messages: [ConversationMessage], _ checkpoint: UInt64?) -> Void,
        completion: @Sendable @escaping (Result<UInt64, ErrorGetDelta>) -> Void
    ) {
        let request = Flipcash_Messaging_V1_GetDeltaRequest.with {
            $0.chatID = conversationID.proto
            $0.afterSequence = afterSequence
            $0.viewMode = viewMode.proto
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                try await service.getDelta(request: .init(message: request), options: .defaults) { response in
                    var head: UInt64 = 0
                    var terminal: ErrorGetDelta?
                    for try await message in response.messages {
                        head = max(head, message.latestSequence)
                        let result = ErrorGetDelta(rawValue: message.result.rawValue) ?? .unknown
                        switch result {
                        case .ok:
                            guard message.hasMessages else { continue }
                            let messages = message.messages.messages.compactMap(ConversationMessage.init)
                            let checkpoint = message.checkpointSequence == 0 ? nil : message.checkpointSequence
                            await MainActor.run { onBatch(messages, checkpoint) }
                        case .denied, .resetRequired:
                            terminal = result
                        case .unknown, .transportFailure, .cancelled, .rejected:
                            // Server results are only ok/denied/resetRequired; a transport case here is
                            // defensive — treat as an unknown terminal.
                            terminal = .unknown
                        }
                    }
                    let outcome: Result<UInt64, ErrorGetDelta> = terminal.map { .failure($0) } ?? .success(head)
                    await MainActor.run { completion(outcome) }
                }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    func sendMessage(owner: KeyPair, conversationID: ConversationID, text: String, repliedTo: MessageID?, clientMessageID: UUID, completion: @Sendable @escaping (Result<ConversationMessage, ErrorSendMessage>) -> Void) {
        let request = Flipcash_Messaging_V1_SendMessageRequest.with {
            $0.chatID = conversationID.proto
            // A reply wraps the same text one level deeper on the wire. The domain model keeps it
            // flat — see `ConversationMessage.init?(_:)`, which unwraps it back.
            if let repliedTo {
                $0.content = [.with {
                    $0.reply = .with {
                        $0.repliedMessageID = repliedTo.proto
                        $0.content = [.with { $0.text = .with { $0.text = text } }]
                    }
                }]
            } else {
                $0.content = [.with { $0.text = .with { $0.text = text } }]
            }
            $0.clientMessageID = .with { $0.value = clientMessageID.data }
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.sendMessage(request, options: .unaryDefault)
                let error = ErrorSendMessage(rawValue: response.result.rawValue) ?? .unknown
                if error == .ok, response.hasMessage, let message = ConversationMessage(response.message) {
                    await MainActor.run { completion(.success(message)) }
                } else {
                    logger.error("Failed to send message")
                    await MainActor.run { completion(.failure(error == .ok ? .unknown : error)) }
                }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    func editMessage(
        owner: KeyPair,
        conversationID: ConversationID,
        messageID: MessageID,
        text: String,
        expectedEventSequence: UInt64,
        completion: @Sendable @escaping (Result<MessageMutation, ErrorEditMessage>) -> Void
    ) {
        let request = Flipcash_Messaging_V1_EditMessageRequest.with {
            $0.chatID = conversationID.proto
            $0.messageID = messageID.proto
            $0.content = [.with { $0.text = .with { $0.text = text } }]
            $0.expectedEventSequence = expectedEventSequence
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.editMessage(request, options: .unaryDefault)
                let error = ErrorEditMessage(rawValue: response.result.rawValue) ?? .unknown
                switch error {
                case .ok, .conflict:
                    guard response.hasMessage, let message = ConversationMessage(response.message) else {
                        logger.error("Edit message response carried no message")
                        await MainActor.run { completion(.failure(error == .ok ? .unknown : error)) }
                        return
                    }
                    await MainActor.run {
                        completion(.success(MessageMutation(message: message, isConflict: error == .conflict)))
                    }
                case .denied, .messageNotFound, .cannotEdit, .unknown, .transportFailure, .cancelled, .rejected:
                    logger.error("Failed to edit message")
                    await MainActor.run { completion(.failure(error)) }
                }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    func deleteMessage(
        owner: KeyPair,
        conversationID: ConversationID,
        messageID: MessageID,
        expectedEventSequence: UInt64,
        completion: @Sendable @escaping (Result<MessageMutation, ErrorDeleteMessage>) -> Void
    ) {
        let request = Flipcash_Messaging_V1_DeleteMessageRequest.with {
            $0.chatID = conversationID.proto
            $0.messageID = messageID.proto
            $0.expectedEventSequence = expectedEventSequence
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.deleteMessage(request, options: .unaryDefault)
                let error = ErrorDeleteMessage(rawValue: response.result.rawValue) ?? .unknown
                switch error {
                case .ok, .conflict:
                    guard response.hasMessage, let message = ConversationMessage(response.message) else {
                        logger.error("Delete message response carried no message")
                        await MainActor.run { completion(.failure(error == .ok ? .unknown : error)) }
                        return
                    }
                    await MainActor.run {
                        completion(.success(MessageMutation(message: message, isConflict: error == .conflict)))
                    }
                case .denied, .messageNotFound, .cannotDelete, .unknown, .transportFailure, .cancelled, .rejected:
                    logger.error("Failed to delete message")
                    await MainActor.run { completion(.failure(error)) }
                }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    func advancePointer(owner: KeyPair, conversationID: ConversationID, messageID: MessageID, completion: @Sendable @escaping (Result<Void, ErrorAdvancePointer>) -> Void) {
        let request = Flipcash_Messaging_V1_AdvancePointerRequest.with {
            $0.chatID = conversationID.proto
            $0.pointerType = .read
            $0.newValue = messageID.proto
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.advancePointer(request, options: .unaryDefault)
                let error = ErrorAdvancePointer(rawValue: response.result.rawValue) ?? .unknown
                await MainActor.run { completion(error == .ok ? .success(()) : .failure(error)) }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    func notifyIsTyping(owner: KeyPair, conversationID: ConversationID, state: TypingState, completion: @Sendable @escaping (Result<Void, ErrorNotifyIsTyping>) -> Void) {
        let request = Flipcash_Messaging_V1_NotifyIsTypingRequest.with {
            $0.chatID = conversationID.proto
            $0.state = state.proto
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.notifyIsTyping(request, options: .unaryDefault)
                let error = ErrorNotifyIsTyping(rawValue: response.result.rawValue) ?? .unknown
                await MainActor.run { completion(error == .ok ? .success(()) : .failure(error)) }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    func addReaction(owner: KeyPair, conversationID: ConversationID, messageID: MessageID, emoji: String, completion: @Sendable @escaping (Result<EmojiReaction, ErrorAddReaction>) -> Void) {
        let request = Flipcash_Messaging_V1_AddReactionRequest.with {
            $0.chatID = conversationID.proto
            $0.messageID = messageID.proto
            $0.emoji = .with { $0.value = emoji }
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.addReaction(request, options: .unaryDefault)
                let result = Self.addReactionResult(response)
                if case .failure = result {
                    logger.error("Failed to add reaction")
                }
                await MainActor.run { completion(result) }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    func removeReaction(owner: KeyPair, conversationID: ConversationID, messageID: MessageID, emoji: String, completion: @Sendable @escaping (Result<EmojiReaction, ErrorRemoveReaction>) -> Void) {
        let request = Flipcash_Messaging_V1_RemoveReactionRequest.with {
            $0.chatID = conversationID.proto
            $0.messageID = messageID.proto
            $0.emoji = .with { $0.value = emoji }
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.removeReaction(request, options: .unaryDefault)
                let result = Self.removeReactionResult(response)
                if case .failure = result {
                    logger.error("Failed to remove reaction")
                }
                await MainActor.run { completion(result) }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    func getReactors(owner: KeyPair, conversationID: ConversationID, messageID: MessageID, emoji: String, pageSize: Int, pagingToken: Data?, completion: @Sendable @escaping (Result<ReactorPage, ErrorGetReactors>) -> Void) {
        let request = Flipcash_Messaging_V1_GetReactorsRequest.with {
            $0.chatID = conversationID.proto
            $0.messageID = messageID.proto
            $0.emoji = .with { $0.value = emoji }
            $0.options = .with {
                $0.pageSize = Int32(pageSize)
                if let pagingToken {
                    $0.pagingToken = .with { $0.value = pagingToken }
                }
            }
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.getReactors(request, options: .unaryDefault)
                let result = Self.reactorsResult(response)
                if case .failure = result {
                    logger.error("Failed to get reactors")
                }
                await MainActor.run { completion(result) }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    /// The current reactions on up to 100 messages, keyed by message; a message with none is absent.
    func getReactionSummaries(owner: KeyPair, conversationID: ConversationID, messageIDs: [MessageID], completion: @Sendable @escaping (Result<[MessageID: ReactionState], ErrorGetReactionSummaries>) -> Void) {
        let request = Flipcash_Messaging_V1_GetReactionSummariesRequest.with {
            $0.chatID = conversationID.proto
            $0.messageIds = .with { $0.messageIds = messageIDs.map(\.proto) }
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.getReactionSummaries(request, options: .unaryDefault)
                let result = Self.reactionSummariesResult(response)
                if case .failure = result {
                    logger.error("Failed to get reaction summaries")
                }
                await MainActor.run { completion(result) }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    // MARK: - Reaction response mapping

    /// The reaction an add answered with, or the failure it reported; an OK without a reaction is
    /// malformed and fails as unknown.
    static func addReactionResult(_ response: Flipcash_Messaging_V1_AddReactionResponse) -> Result<EmojiReaction, ErrorAddReaction> {
        let error = ErrorAddReaction(rawValue: response.result.rawValue) ?? .unknown
        switch error {
        case .ok:
            return response.hasReaction ? .success(EmojiReaction(response.reaction)) : .failure(.unknown)
        case .denied, .messageNotFound, .cannotReact, .tooManyReactionTypes, .unknown, .transportFailure, .cancelled, .rejected:
            return .failure(error)
        }
    }

    /// The reaction a remove answered with, or the failure it reported.
    static func removeReactionResult(_ response: Flipcash_Messaging_V1_RemoveReactionResponse) -> Result<EmojiReaction, ErrorRemoveReaction> {
        let error = ErrorRemoveReaction(rawValue: response.result.rawValue) ?? .unknown
        switch error {
        case .ok:
            return response.hasReaction ? .success(EmojiReaction(response.reaction)) : .failure(.unknown)
        case .denied, .messageNotFound, .unknown, .transportFailure, .cancelled, .rejected:
            return .failure(error)
        }
    }

    /// Each message's reactions, or the failure reported.
    static func reactionSummariesResult(_ response: Flipcash_Messaging_V1_GetReactionSummariesResponse) -> Result<[MessageID: ReactionState], ErrorGetReactionSummaries> {
        let error = ErrorGetReactionSummaries(rawValue: response.result.rawValue) ?? .unknown
        switch error {
        case .ok:
            return .success(Dictionary(
                response.summaries.map { (MessageID($0.messageID), ReactionState($0)) },
                uniquingKeysWith: { _, last in last }
            ))
        case .denied, .unknown, .transportFailure, .cancelled, .rejected:
            return .failure(error)
        }
    }

    /// The page of reactors, or the failure reported.
    static func reactorsResult(_ response: Flipcash_Messaging_V1_GetReactorsResponse) -> Result<ReactorPage, ErrorGetReactors> {
        let error = ErrorGetReactors(rawValue: response.result.rawValue) ?? .unknown
        switch error {
        case .ok:
            return .success(ReactorPage(
                reactors: response.reactors.compactMap(Reactor.init),
                nextPageToken: response.hasMore_p && response.hasPagingToken ? response.pagingToken.value : nil,
                version: response.version
            ))
        case .denied, .messageNotFound, .unknown, .transportFailure, .cancelled, .rejected:
            return .failure(error)
        }
    }
}

// MARK: - Errors -

public enum ErrorGetMessage: Int, Error {
    case ok
    case denied
    case notFound
    case unknown          = -1
    case transportFailure = -2
    case cancelled = -3
    case rejected = -4
}

public enum ErrorGetMessages: Int, Error {
    case ok
    case denied
    case notFound
    case unknown          = -1
    case transportFailure = -2
    case cancelled = -3
    case rejected = -4
}

public enum ErrorGetDelta: Int, Error {
    case ok
    case denied
    case resetRequired
    case unknown          = -1
    case transportFailure = -2
    case cancelled        = -3
    case rejected         = -4
}

public enum ErrorSendMessage: Int, Error {
    case ok
    case denied
    case unknown          = -1
    case transportFailure = -2
    case cancelled = -3
    case rejected = -4
}

public enum ErrorEditMessage: Int, Error {
    case ok
    case denied
    case messageNotFound
    case cannotEdit
    case conflict
    case unknown          = -1
    case transportFailure = -2
    case cancelled = -3
    case rejected = -4
}

public enum ErrorDeleteMessage: Int, Error {
    case ok
    case denied
    case messageNotFound
    case cannotDelete
    case conflict
    case unknown          = -1
    case transportFailure = -2
    case cancelled = -3
    case rejected = -4
}

public enum ErrorAdvancePointer: Int, Error {
    case ok
    case denied
    case messageNotFound
    case unknown          = -1
    case transportFailure = -2
    case cancelled = -3
    case rejected = -4
}

public enum ErrorNotifyIsTyping: Int, Error {
    case ok
    case denied
    case unknown          = -1
    case transportFailure = -2
    case cancelled = -3
    case rejected = -4
}

extension ErrorGetMessage: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .cancelled: .info
        case .denied, .notFound: .info
        case .unknown, .rejected: .error
        }
    }
}

extension ErrorGetMessages: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .cancelled: .info
        case .denied, .notFound: .info
        case .unknown, .rejected: .error
        }
    }
}

extension ErrorGetDelta: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        // `resetRequired` is a routine "cursor too old, re-sync" outcome, `denied` an expected
        // membership/business result, and `.cancelled` app-initiated teardown — none is a client defect.
        case .denied, .resetRequired, .cancelled: .info
        case .unknown, .rejected: .error
        }
    }
}

extension ErrorSendMessage: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .cancelled: .info
        case .denied: .info
        case .unknown, .rejected: .error
        }
    }
}

extension ErrorEditMessage: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .cancelled: .info
        // `conflict` is the concurrency guard doing its job, and the rest are expected
        // membership/business outcomes — none is a client defect.
        case .denied, .messageNotFound, .cannotEdit, .conflict: .info
        case .unknown, .rejected: .error
        }
    }
}

extension ErrorDeleteMessage: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .cancelled: .info
        case .denied, .messageNotFound, .cannotDelete, .conflict: .info
        case .unknown, .rejected: .error
        }
    }
}

extension ErrorAdvancePointer: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .cancelled: .info
        case .denied, .messageNotFound: .info
        case .unknown, .rejected: .error
        }
    }
}

extension ErrorNotifyIsTyping: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .cancelled: .info
        case .denied: .info
        case .unknown, .rejected: .error
        }
    }
}

public enum ErrorAddReaction: Int, Error {
    case ok
    case denied
    case messageNotFound
    case cannotReact
    case tooManyReactionTypes
    case unknown          = -1
    case transportFailure = -2
    case cancelled = -3
    case rejected = -4
}

public enum ErrorRemoveReaction: Int, Error {
    case ok
    case denied
    case messageNotFound
    case unknown          = -1
    case transportFailure = -2
    case cancelled = -3
    case rejected = -4
}

public enum ErrorGetReactors: Int, Error {
    case ok
    case denied
    case messageNotFound
    case unknown          = -1
    case transportFailure = -2
    case cancelled = -3
    case rejected = -4
}

extension ErrorAddReaction: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .cancelled: .info
        case .denied, .messageNotFound, .cannotReact, .tooManyReactionTypes: .info
        case .unknown, .rejected: .error
        }
    }

    /// The failure `ReactionState` settles the call with.
    public var reactionFailure: ReactionFailure {
        switch self {
        case .messageNotFound: .messageNotFound
        case .cannotReact: .cannotReact
        case .tooManyReactionTypes: .tooManyReactionTypes
        case .denied: .denied
        case .ok, .unknown, .transportFailure, .cancelled, .rejected: .network
        }
    }
}

extension ErrorRemoveReaction: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .cancelled: .info
        case .denied, .messageNotFound: .info
        case .unknown, .rejected: .error
        }
    }

    /// The failure `ReactionState` settles the call with.
    public var reactionFailure: ReactionFailure {
        switch self {
        case .messageNotFound: .messageNotFound
        case .denied: .denied
        case .ok, .unknown, .transportFailure, .cancelled, .rejected: .network
        }
    }
}

public enum ErrorGetReactionSummaries: Int, Error {
    case ok
    case denied
    case unknown          = -1
    case transportFailure = -2
    case cancelled = -3
    case rejected = -4
}

extension ErrorGetReactionSummaries: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .cancelled, .denied: .info
        case .unknown, .rejected: .error
        }
    }
}

extension ErrorGetReactors: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .cancelled: .info
        case .denied, .messageNotFound: .info
        case .unknown, .rejected: .error
        }
    }
}
