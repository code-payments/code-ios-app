//
//  NotificationService.swift
//  NotificationService
//

import Foundation
import UserNotifications
import Contacts
import Intents
import FlipcashCore
import FlipcashAPI

/// Rewrites contact pushes to use the user's local contact name, and renders
/// "Sent You Cash" pushes as communication notifications carrying the sender's
/// avatar.
///
/// Phone-to-contact resolution happens on-device. The server sends only E.164s
/// and substitution placeholders; the extension queries `CNContactStore`
/// directly with each phone and applies positional substitutions.
final class NotificationService: UNNotificationServiceExtension {

    /// A contact matched from a push's phone number, carrying the data needed to
    /// substitute its name and render its avatar.
    private struct ResolvedContact {
        let name: String
        let nameComponents: PersonNameComponents
        let thumbnailImageData: Data?
        let phone: String
        let contactIdentifier: String
    }

    /// Serializes the notification hand-off across the three threads that race for it: the system
    /// calls `didReceive` on one thread and `serviceExtensionTimeWillExpire` on a *separate* thread,
    /// and the prefetch `Task` resumes on yet another. `contentHandler` must fire exactly once.
    ///
    /// `contentHandler` and the `UNNotificationContent` are non-`Sendable`, system-vended objects that
    /// are *task-isolated* to `didReceive` (a method on this non-`Sendable` class), so the region
    /// checker won't let them cross into a `Task` or a `Mutex`. The thread-agnostic answer is to own
    /// the serialization manually: an `NSLock` guards every field, and `@unchecked Sendable` is the
    /// *accurate* assertion that the lock is the single ordering point. The `Task` captures this
    /// `Sendable` box — never `self`, never a bare content — so correctness doesn't depend on which
    /// thread the system uses for any callback.
    private final class DeliveryBox: @unchecked Sendable {
        private let lock = NSLock()
        private var contentHandler: ((UNNotificationContent) -> Void)?
        private var content: UNNotificationContent?
        private var prefetchTask: Task<Void, Never>?

        /// Arms the box with the handler and the content to deliver — the communication-styled copy
        /// when a sender resolved, else the substituted content. Called once, from `didReceive`,
        /// before the prefetch task or the expiry deadline can run.
        func arm(handler: @escaping (UNNotificationContent) -> Void, content: UNNotificationContent) {
            lock.withLock {
                contentHandler = handler
                self.content = content
            }
        }

        func setPrefetchTask(_ task: Task<Void, Never>) {
            lock.withLock { prefetchTask = task }
        }

        /// Cancels the in-flight prefetch, if any. Called from the expiry thread. Best-effort: the
        /// gRPC bridge isn't cancellation-aware, so this stops work *after* the current RPC rather
        /// than aborting it — the extension's budget (process suspension) is the real stop. A cache
        /// write that lands after delivery is harmless; the content extension reads it on the next expand.
        func cancelPrefetch() {
            let task = lock.withLock { prefetchTask }
            task?.cancel()
        }

        /// Delivers the content to the system exactly once. The first caller — prefetch completion or
        /// expiry deadline — wins; the handler is captured and cleared under the lock (so the loser is a
        /// no-op), then invoked *outside* the lock so a slow or re-entrant system callback can't stall
        /// the other thread.
        func deliver() {
            let captured = lock.withLock { () -> ((UNNotificationContent) -> Void, UNNotificationContent)? in
                guard let handler = contentHandler, let content else { return nil }
                contentHandler = nil
                return (handler, content)
            }
            if let (handler, content) = captured {
                handler(content)
            }
        }
    }

    private let delivery = DeliveryBox()

    private let contactStore = CNContactStore()

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        guard let bestAttemptContent = request.content.mutableCopy() as? UNMutableNotificationContent else {
            contentHandler(request.content)
            return
        }

        guard let payload = NotificationPayload.decode(request.content.userInfo) else {
            contentHandler(bestAttemptContent)
            return
        }

        // Only the `.contact` substitution kind ships today, resolved to a local
        // name, or to the number itself (national format) when no contact
        // matches — the sender is never anonymous. The server's per-substitution
        // `fallback` is reserved for future kinds this client doesn't yet recognize.
        let titleContacts = payload.titleSubstitutions.map { resolve($0.contact) }

        bestAttemptContent.title = SubstitutionApplier.apply(
            template: bestAttemptContent.title,
            resolutions: zip(titleContacts, payload.titleSubstitutions).map { contact, substitution in
                displayText(contact: contact, phone: substitution.contact)
            }
        )
        bestAttemptContent.body = SubstitutionApplier.apply(
            template: bestAttemptContent.body,
            resolutions: payload.bodySubstitutions.map { substitution in
                displayText(contact: resolve(substitution.contact), phone: substitution.contact)
            }
        )
        bestAttemptContent.threadIdentifier = payload.groupKey

        // Tag chat pushes with the category so the Reply and Send Cash actions
        // (registered in the app) attach to the notification.
        if payload.category == .chat {
            bestAttemptContent.categoryIdentifier = ChatNotificationCategory.id
        }

        // Non-chat pushes need no prefetch and no communication styling: deliver the substituted
        // content directly. `bestAttemptContent` is transferred into the handler as its last use.
        guard payload.category == .chat, let conversationID = NotificationPayload.chatID(request.content.userInfo) else {
            contentHandler(bestAttemptContent)
            return
        }

        // "Sent You Cash" (CHAT) renders as a communication notification so the sender's avatar — or
        // the system monogram fallback — shows like a chat app. This styled copy (when a sender
        // resolves; otherwise the substituted content) is what's delivered, from both the prefetch
        // completion and the expiry deadline.
        let finalContent: UNNotificationContent =
            titleContacts.compactMap { $0 }.first.map { sender in
                communicationContent(
                    from: bestAttemptContent,
                    sender: sender,
                    conversationIdentifier: payload.groupKey
                )
            } ?? bestAttemptContent.copy() as! UNNotificationContent

        // Prefetch the recent transcript into the shared cache so the content extension renders from
        // the cache on expand with no resident gRPC connection. The banner is held until the transcript
        // is cached (the prefetch calls `deliver` after the read, before the slower branding round-trip)
        // so the extension stays alive long enough to populate it; serviceExtensionTimeWillExpire
        // delivers it if the read runs past the budget.
        //
        // Arm the box, then spawn the prefetch. Spawning runs in `startPrefetch`, which sees only the
        // `Sendable` `delivery` box + the `Sendable` `ConversationID` — never `self` and never a bare
        // `UNNotificationContent`. Keeping the `Task` out of this `self`-isolated method is what lets
        // the region checker prove the closure crosses no isolation boundary with a non-`Sendable`.
        delivery.arm(handler: contentHandler, content: finalContent)
        Self.startPrefetch(into: delivery, for: conversationID)
    }

    /// Spawns the transcript prefetch and registers it on `delivery`. `nonisolated static` and taking
    /// only `Sendable` arguments, so the spawned `Task` captures nothing isolated to a `self` — which
    /// is what keeps the region checker satisfied and the hand-off thread-agnostic.
    private nonisolated static func startPrefetch(into delivery: DeliveryBox, for conversationID: ConversationID) {
        let task = Task {
            await cachePreview(for: conversationID, deliver: { delivery.deliver() })
        }
        delivery.setPrefetchTask(task)
    }

    override func serviceExtensionTimeWillExpire() {
        // Runs on a *different* thread than `didReceive`. Cancel the prefetch and deliver; `deliver`
        // clears the handler under the lock, so if the prefetch already won this is a no-op — the
        // handler fires exactly once whichever thread arrives first.
        delivery.cancelPrefetch()
        delivery.deliver()
    }

    /// The substitution display: the matched contact's name, else the number
    /// itself in national format (e.g. "(747) 217-6923"), falling back to the
    /// raw E.164.
    private func displayText(contact: ResolvedContact?, phone: Flipcash_Phone_V1_PhoneNumber) -> String {
        contact?.name ?? Phone(phone.value)?.national ?? phone.value
    }

    /// Returns the contact matching `phone`, or `nil` if no contact matches, the
    /// contact has no usable name, or Contacts permission is unavailable.
    private func resolve(_ phone: Flipcash_Phone_V1_PhoneNumber) -> ResolvedContact? {
        let predicate = CNContact.predicateForContacts(
            matching: CNPhoneNumber(stringValue: phone.value)
        )
        let keys: [CNKeyDescriptor] = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactThumbnailImageDataKey as CNKeyDescriptor,
        ]
        guard
            let contact = try? contactStore.unifiedContacts(matching: predicate, keysToFetch: keys).first,
            let name = CNContactFormatter.string(from: contact, style: .fullName),
            !name.isEmpty
        else {
            return nil
        }

        var nameComponents = PersonNameComponents()
        nameComponents.givenName = contact.givenName
        nameComponents.familyName = contact.familyName

        return ResolvedContact(
            name: name,
            nameComponents: nameComponents,
            thumbnailImageData: contact.thumbnailImageData,
            phone: phone.value,
            contactIdentifier: contact.identifier
        )
    }

    /// Augments `content` with an `INSendMessageIntent` so the system renders it
    /// as a communication notification showing `sender`'s avatar. Returns the
    /// unmodified content if the intent can't be applied.
    private func communicationContent(
        from content: UNMutableNotificationContent,
        sender: ResolvedContact,
        conversationIdentifier: String
    ) -> UNNotificationContent {
        let handle = INPersonHandle(value: sender.phone, type: .phoneNumber)
        let image = sender.thumbnailImageData.map { INImage(imageData: $0) }
        let person = INPerson(
            personHandle: handle,
            nameComponents: sender.nameComponents,
            displayName: sender.name,
            image: image,
            contactIdentifier: sender.contactIdentifier,
            customIdentifier: nil
        )
        let intent = INSendMessageIntent(
            recipients: nil,
            outgoingMessageType: .outgoingMessageText,
            content: nil,
            speakableGroupName: nil,
            conversationIdentifier: conversationIdentifier,
            serviceName: nil,
            sender: person,
            attachments: nil
        )
        if let image {
            intent.setImage(image, forParameterNamed: \.sender)
        }

        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .incoming
        interaction.donate(completion: nil)

        return (try? content.updating(from: intent)) ?? content
    }

    // MARK: - Transcript prefetch -

    /// Fetches the recent transcript over a transient gRPC connection and writes the rendered preview
    /// to the shared cache, so the content extension renders it on expand without opening its own
    /// connection. Calls `deliver` once the transcript is cached (or the fetch can't proceed) so the
    /// banner isn't gated on the slower branding round-trip. Best-effort: any failure just leaves the
    /// content extension to fetch live.
    private static func cachePreview(for conversationID: ConversationID, deliver: @Sendable () -> Void) async {
        guard let account = OwnerKeyStore.loadOwnerAccount() else { return deliver() }
        do {
            let client = try ChatNotificationClient()
            let messages = try await client.getMessages(
                owner: account.keyAccount.owner,
                conversationID: conversationID,
                limit: NotificationPreviewCache.previewLimit,
                retryingEmpty: true
            )
            guard !messages.isEmpty else { return deliver() }
            func items(_ branding: [PublicKey: MintBrandingInfo]) -> [ChatItem] {
                ChatItem.preview(
                    from: messages,
                    selfUserID: account.userID,
                    limit: NotificationPreviewCache.previewLimit,
                    mintBranding: branding
                )
            }
            // Cache the messages (currency-code fallback) and release the banner before the branding
            // round-trip, then enrich the cache with token names + icons best-effort — the bubble
            // renders fine without branding if it's slow or the extension is suspended first.
            NotificationPreviewCache.write(items([:]), for: conversationID)
            deliver()
            let branding = (try? await client.resolveMintBranding(in: messages)) ?? [:]
            if !branding.isEmpty {
                NotificationPreviewCache.write(items(branding), for: conversationID)
            }
        } catch {
            // Best-effort prefetch — a transport failure: the content extension falls back to a live
            // fetch on open.
            deliver()
        }
    }
}
