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
        case sending(step: Int, of: Int)
        case failed(message: String, canRetry: Bool)
    }

    private(set) var phase: Phase = .loading
    private(set) var chats: [Conversation] = []
    private(set) var thumbnails: [ShareThumbnail] = []
    private(set) var input = ShareInput()
    private(set) var sendState: SendState = .idle

    /// The chat the share was aimed at by an intent, or nil.
    private(set) var preselectedID: ConversationID?

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

    // Per-send progress that survives a retry: what already went out is never sent twice.
    private var clientMessageIDs: [Int: UUID] = [:]
    private var uploaded: [Int: UploadedPhoto] = [:]
    private var completedSteps: Set<Int> = []
    private var session: Session?

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
        let outcome = ExtensionStore.perform(owner: account.keyAccount.ownerPublicKey) { database in
            conversations = try database.getConversations()
        }
        guard outcome == .wrote, let conversations else {
            ExtensionReporting.breadcrumb("chat list unavailable: \(outcome)")
            phase = .chatsUnavailable
            return
        }
        chats = ShareChatSelection.candidates(from: conversations)
        preselectedID = ShareChatSelection.preselected(conversationIdentifier: intentConversationIdentifier, in: chats)

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

    func displayName(for chat: Conversation) -> String {
        // The extension has no contacts access, so the feed's name stands in for the address-book name.
        chat.displayName(selfUserID: account?.userID, contactName: { _ in nil })
    }

    // MARK: - Sending -

    func send(to chat: Conversation) {
        guard sendTask == nil, !isSending else { return }
        sendTask = Task {
            await performSend(to: chat)
            sendTask = nil
        }
    }

    func cancel() {
        sendTask?.cancel()
        input.removeFiles()
        cancelRequest()
    }

    private func performSend(to chat: Conversation) async {
        guard let account else { return }
        let owner = account.keyAccount.owner
        let steps = ShareSendPlan.steps(imageCount: input.imageURLs.count, text: text)
        guard !steps.isEmpty else { return }

        do {
            let session = try await resolveSession(for: chat, account: account)
            for (position, step) in steps.enumerated() where !completedSteps.contains(position) {
                try Task.checkCancellation()
                sendState = .sending(step: position + 1, of: steps.count)
                let clientMessageID = clientMessageIDs[position] ?? UUID()
                clientMessageIDs[position] = clientMessageID

                let message: ConversationMessage
                switch step {
                case .text(let body):
                    message = try await session.flipClient.sendMessage(owner: owner, conversationID: chat.id, text: body, repliedTo: nil, seal: session.seal, clientMessageID: clientMessageID)
                case .photo(let index, let caption):
                    let photo = try await uploadedPhoto(at: index, session: session)
                    message = try await session.flipClient.sendMediaMessage(owner: owner, conversationID: chat.id, photo: photo, caption: caption, repliedTo: nil, seal: session.seal, clientMessageID: clientMessageID)
                }
                completedSteps.insert(position)
                persist(message, in: chat.id, account: account)
            }
            input.removeFiles()
            finish()
        } catch is CancellationError {
            sendState = .idle
        } catch {
            ExtensionReporting.capture(error, reason: "Share send failed")
            sendState = .failed(message: Self.message(for: error), canRetry: Self.canRetry(error))
        }
    }

    /// The client, the chat's seal and the uploader, built once per send and kept across retries so a
    /// retry doesn't repeat the chat fetch. Only a fully built session is kept.
    private func resolveSession(for chat: Conversation, account: UserAccount) async throws -> Session {
        if let session { return session }
        let owner = account.keyAccount.owner
        let flipClient = try FlipClient(network: .mainNet)
        let keyring = ChatKeyring(owner: owner, selfUserID: account.userID) { userID in
            try await flipClient.resolveUserID(userID, owner: owner)
        }
        let conversation = try await flipClient.getChat(owner: owner, conversationID: chat.id)
        let seal = try await keyring.sealForSending(in: conversation)
        let uploader = ChatMediaUploader(
            blob: FlipClientChatMediaBlobStore(flipClient: flipClient, owner: owner),
            seal: { seal }
        )
        let session = Session(flipClient: flipClient, seal: seal, uploader: uploader)
        self.session = session
        return session
    }

    /// Decodes, uploads and releases one image. The decoded bitmap lives only inside this call, and a
    /// retry after a failed send reuses the stored upload instead of decoding again.
    private func uploadedPhoto(at index: Int, session: Session) async throws -> UploadedPhoto {
        if let photo = uploaded[index] { return photo }
        guard let image = await ChatPhotoDecoder.decode(contentsOf: input.imageURLs[index], maxPixelSize: Self.maxUploadEdge) else {
            throw ShareError.unreadableImage
        }
        let photo = try await session.uploader.upload(image, orientation: .up, onStored: { uploaded[index] = $0 }, onPrepared: { _, _ in })
        uploaded[index] = photo
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
