//
//  ShareModel.swift
//  ShareExtension
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import CoreGraphics
import Foundation
import ImageIO
import Observation
import FlipcashCore
import FlipcashStore

/// A small, already-downsampled preview of one shared image.
struct ShareThumbnail: Identifiable {
    let id: Int
    let image: CGImage
}

/// State and send logic for the share extension.
///
/// The extension is killed at roughly 120MB, so images stay on disk as files and are decoded one at
/// a time, capped at ``maxUploadEdge``, only while they upload. What the view holds are thumbnails.
@MainActor
@Observable
final class ShareModel {

    enum Phase {
        case loading
        /// No owner key in the shared keychain; the user has to sign in from the app.
        case signedOut
        /// The shared store is missing, busy or from another schema. The app rebuilds it on launch.
        case chatsUnavailable
        case ready
    }

    enum SendState: Equatable {
        case idle
        /// Sending to the chat at `chat` of `total`, one message at a time.
        case sending(chat: Int, of: Int)
        /// At least one chat didn't get the share; `progress` says which.
        case failed
    }

    private(set) var phase: Phase = .loading
    private(set) var chats: [Conversation] = []
    private(set) var thumbnails: [ShareThumbnail] = []
    private(set) var input = ShareInput()
    private(set) var sendState: SendState = .idle

    /// The chat the share was aimed at by an intent, or nil.
    private(set) var preselectedID: ConversationID?

    /// The chats the share will go to, in pick order.
    private(set) var recipients = ShareRecipientSelection()

    /// The search field's text.
    var query = ""

    /// Where each chosen chat stands once a send has started; nil before the first send.
    private(set) var progress: ShareSendProgress?

    /// The message text, prefilled from the shared text or link.
    var text = ""

    /// The longest edge an image is decoded at for upload. A 12MP decode is about 48MB, and the encoder
    /// holds more than one copy while it works; 2560 keeps the peak well under the extension's limit.
    nonisolated static let maxUploadEdge = 2560
    nonisolated static let thumbnailEdge = 240

    private let providers: [NSItemProvider]
    private let intentConversationIdentifier: String?
    private let finish: () -> Void
    private let cancelRequest: () -> Void

    private var account: UserAccount?
    private var loadTask: Task<Void, Never>?
    private var sendTask: Task<Void, Never>?

    // Per-chat progress that survives a retry: what already went out is never sent twice.
    private var clientMessageIDs: [StepKey: UUID] = [:]
    private var completedSteps: Set<StepKey> = []
    private var sessions: [ConversationID: Session] = [:]
    private var flipClient: FlipClient?
    /// Uploads by image. A photo sealed for one chat is that chat's alone, so `chat` is nil only for
    /// plaintext uploads, which every chat can reference.
    private var uploaded: [UploadKey: UploadedPhoto] = [:]

    private struct StepKey: Hashable {
        let chat: ConversationID
        let step: Int
    }

    private struct UploadKey: Hashable {
        let chat: ConversationID?
        let index: Int
    }

    private struct Session {
        let flipClient: FlipClient
        let seal: ChatSeal?
        let uploader: ChatMediaUploader
    }

    init(
        providers: [NSItemProvider],
        intentConversationIdentifier: String?,
        finish: @escaping () -> Void,
        cancel: @escaping () -> Void
    ) {
        self.providers = providers
        self.intentConversationIdentifier = intentConversationIdentifier
        self.finish = finish
        self.cancelRequest = cancel
    }

    var isSending: Bool {
        if case .sending = sendState { true } else { false }
    }

    // MARK: - Loading -

    func load() {
        guard loadTask == nil else { return }
        loadTask = Task { await performLoad() }
    }

    private func performLoad() async {
        guard let account = OwnerKeyStore.loadOwnerAccount() else {
            phase = .signedOut
            return
        }
        self.account = account

        var conversations: [Conversation]?
        var joinedGroupIDs: Set<ConversationID> = []
        let outcome = ExtensionStore.perform(owner: account.keyAccount.ownerPublicKey) { database in
            conversations = try database.getConversations()
            joinedGroupIDs = try database.getGroupMemberships()
        }
        guard outcome == .wrote, let conversations else {
            ExtensionReporting.breadcrumb("chat list unavailable: \(outcome)")
            phase = .chatsUnavailable
            return
        }
        let archivedIDs = ChatArchiveReader.load(owner: account.keyAccount.ownerPublicKey)?.archivedIDs ?? []
        chats = ShareChatSelection.candidates(from: conversations, joinedGroupIDs: joinedGroupIDs, archivedIDs: archivedIDs)
        preselectedID = ShareChatSelection.preselected(conversationIdentifier: intentConversationIdentifier, in: chats)
        if let preselectedID { recipients.select(preselectedID) }

        input = await ShareInput.parse(providers)
        text = input.text ?? ""
        // One decode at a time, each at thumbnail size.
        var loaded: [ShareThumbnail] = []
        for (index, url) in input.imageURLs.enumerated() {
            if let image = await ChatPhotoDecoder.decode(contentsOf: url, maxPixelSize: Self.thumbnailEdge) {
                loaded.append(ShareThumbnail(id: index, image: image))
            }
        }
        thumbnails = loaded
        phase = .ready
    }

    /// What a row's avatar draws, from the same picture the Chats tab uses: the chat's own for a
    /// group, the counterpart's for a DM. Bytes come from the App Group cache the app fills, so a
    /// picture the app has not fetched yet falls back to its blurhash.
    func avatar(for chat: Conversation) -> ShareAvatar {
        let picture = chat.type == .group
            ? chat.picture
            : chat.counterpart(excluding: account?.userID)?.profilePicture
        let id = chat.type == .group
            ? chat.id.description
            : (chat.counterpart(excluding: account?.userID)?.userID?.uuidString ?? chat.id.description)
        return ShareAvatar(
            id: id,
            imageData: picture.flatMap { BlobCache.profilePictures.data(for: $0.thumbnailBlobID) },
            blurhash: picture?.thumbnailBlurhash
        )
    }

    func displayName(for chat: Conversation) -> String {
        // The extension has no contacts access, so the feed's name stands in for the address-book name.
        chat.displayName(selfUserID: account?.userID, contactName: { _ in nil })
    }

    // MARK: - Selection -

    var sections: ShareChatList.Sections {
        ShareChatList.sections(chats, query: query, suggested: preselectedID, name: displayName(for:))
    }

    func chat(_ id: ConversationID) -> Conversation? {
        chats.first { $0.id == id }
    }

    /// The chosen chats' names, comma-joined, in pick order.
    var recipientSummary: String {
        recipients.ids.compactMap { chat($0) }.map(displayName(for:)).joined(separator: ", ")
    }

    @discardableResult
    func toggle(_ id: ConversationID) -> ShareRecipientSelection.ToggleResult {
        guard !isSending else { return .deselected }
        let result = recipients.toggle(id)
        if result != .limitReached, case .failed = sendState {
            // The set changed under a failed send; start the next send from the new set.
            progress = nil
            sendState = .idle
        }
        return result
    }

    var canSend: Bool {
        if isSending || recipients.isEmpty { return false }
        if let progress, progress.isStuck { return false }
        return !thumbnails.isEmpty || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Sending -

    func send() {
        guard sendTask == nil, !isSending, canSend else { return }
        sendTask = Task {
            await performSend()
            sendTask = nil
        }
    }

    func cancel() {
        sendTask?.cancel()
        input.removeFiles()
        cancelRequest()
    }

    /// Sends to every chat that hasn't received the share yet, one at a time, and finishes the request
    /// once all have. A chat that fails doesn't stop the others.
    private func performSend() async {
        guard let account else { return }
        let steps = ShareSendPlan.steps(imageCount: input.imageURLs.count, text: text)
        guard !steps.isEmpty else { return }

        var progress = self.progress ?? ShareSendProgress(recipients: recipients.ids)
        let targets = progress.remaining
        for (position, id) in targets.enumerated() {
            guard let chat = chat(id) else { continue }
            sendState = .sending(chat: position + 1, of: targets.count)
            do {
                try await send(steps, to: chat, account: account)
                progress.markSent(id)
            } catch is CancellationError {
                self.progress = progress
                sendState = .idle
                return
            } catch {
                ExtensionReporting.capture(error, reason: "Share send failed", metadata: [
                    "chatType": String(describing: chat.type),
                    "isPrivate": String(chat.isPrivate),
                ])
                progress.markFailed(id, message: Self.message(for: error), canRetry: Self.canRetry(error))
            }
            self.progress = progress
        }

        if progress.isComplete {
            input.removeFiles()
            finish()
        } else {
            sendState = .failed
        }
    }

    private func send(_ steps: [ShareSendPlan.Step], to chat: Conversation, account: UserAccount) async throws {
        let owner = account.keyAccount.owner
        let session = try await resolveSession(for: chat, account: account)
        for (position, step) in steps.enumerated() where !completedSteps.contains(StepKey(chat: chat.id, step: position)) {
            try Task.checkCancellation()
            let key = StepKey(chat: chat.id, step: position)
            let clientMessageID = clientMessageIDs[key] ?? UUID()
            clientMessageIDs[key] = clientMessageID

            let message: ConversationMessage
            switch step {
            case .text(let body):
                message = try await session.flipClient.sendMessage(owner: owner, conversationID: chat.id, text: body, repliedTo: nil, seal: session.seal, clientMessageID: clientMessageID)
            case .photo(let index, let caption):
                let photo = try await uploadedPhoto(at: index, chat: chat.id, session: session)
                message = try await session.flipClient.sendMediaMessage(owner: owner, conversationID: chat.id, photo: photo, caption: caption, repliedTo: nil, seal: session.seal, clientMessageID: clientMessageID)
            }
            completedSteps.insert(key)
            persist(message, in: chat.id, account: account)
        }
    }

    /// The client, the chat's seal and the uploader, built once per chat and kept across retries so a
    /// retry doesn't repeat the chat fetch. Only a fully built session is kept.
    private func resolveSession(for chat: Conversation, account: UserAccount) async throws -> Session {
        if let session = sessions[chat.id] { return session }
        let owner = account.keyAccount.owner
        let flipClient = try self.flipClient ?? FlipClient(network: .mainNet)
        self.flipClient = flipClient
        let keyring = ChatKeyring(
            owner: owner,
            selfUserID: account.userID,
            resolveKey: { userID in
                try await flipClient.resolveUserID(userID, owner: owner)
            },
            setEnvelope: { conversationID, envelope in
                try await flipClient.setKeyEnvelope(owner: owner, conversationID: conversationID, keyEnvelope: envelope)
            },
            getEnvelope: { conversationID in
                try await flipClient.getKeyEnvelope(owner: owner, conversationID: conversationID)
            },
            // Like the notification extension, this only opens an invite-joined member's own
            // envelope; the app opens the invite's copy and stores it.
            opensInviteBundles: false
        )
        let conversation = try await flipClient.getChat(owner: owner, conversationID: chat.id)
        let seal = try await keyring.sealForSending(in: conversation)
        let uploader = ChatMediaUploader(
            blob: FlipClientChatMediaBlobStore(flipClient: flipClient, owner: owner),
            seal: { seal }
        )
        let session = Session(flipClient: flipClient, seal: seal, uploader: uploader)
        sessions[chat.id] = session
        return session
    }

    /// Decodes, uploads and releases one image. The decoded bitmap lives only inside this call, and a
    /// retry after a failed send reuses the stored upload instead of decoding again.
    private func uploadedPhoto(at index: Int, chat: ConversationID, session: Session) async throws -> UploadedPhoto {
        let sealedKey = UploadKey(chat: chat, index: index)
        let plainKey = UploadKey(chat: nil, index: index)
        if let photo = uploaded[sealedKey] ?? uploaded[plainKey] { return photo }
        let key = session.seal == nil ? plainKey : sealedKey
        guard let image = await ChatPhotoDecoder.decode(contentsOf: input.imageURLs[index], maxPixelSize: Self.maxUploadEdge) else {
            throw ShareError.unreadableImage
        }
        let photo = try await session.uploader.upload(image, orientation: .up, onStored: { uploaded[key] = $0 }, onPrepared: { _, _ in })
        uploaded[key] = photo
        return photo
    }

    /// Writes the confirmed message into the shared store so the app has it on next launch, and tells a
    /// running app to re-read. Best effort: the app also catches up on sync, so a missing or busy store
    /// loses nothing.
    private func persist(_ message: ConversationMessage, in conversationID: ConversationID, account: UserAccount) {
        let outcome = ExtensionStore.perform(owner: account.keyAccount.ownerPublicKey) { database in
            try database.persistMessages([message], cursor: 0, conversationID: conversationID)
        }
        switch outcome {
        case .wrote:
            ChatStoreWriteNotification.post()
        case .noStore, .busy, .versionMismatch:
            ExtensionReporting.breadcrumb("share store write skipped: \(outcome)")
        case .failed(let description):
            ExtensionReporting.breadcrumb("share store write failed: \(description)")
        }
    }

    // MARK: - Errors -

    enum ShareError: Error {
        case unreadableImage
    }

    private static func canRetry(_ error: Error) -> Bool {
        switch error {
        case let error as ChatMediaUploadError: !error.isTerminal
        case ShareError.unreadableImage:        false
        default:                                true
        }
    }

    private static func message(for error: Error) -> String {
        switch error {
        case ShareError.unreadableImage:
            "One of the images couldn't be read."
        case ChatMediaUploadError.rejected(.moderation):
            "This image can't be sent."
        case ChatMediaUploadError.rejected, ChatMediaUploadError.encodingFailed, ChatMediaUploadError.noMatchingConstraint:
            "This image couldn't be prepared for sending."
        default:
            "Couldn't send. Check your connection and try again."
        }
    }
}

/// The inputs of a `ContactAvatarView` for one picker row.
struct ShareAvatar {
    let id: String
    let imageData: Data?
    let blurhash: String?
}
