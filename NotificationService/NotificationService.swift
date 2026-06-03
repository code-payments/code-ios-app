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

    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?

    private let contactStore = CNContactStore()

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)

        guard let bestAttemptContent else {
            contentHandler(request.content)
            return
        }

        guard let payload = NotificationPayload.decode(request.content.userInfo) else {
            contentHandler(bestAttemptContent)
            return
        }

        // Only the `.contact` substitution kind ships today, resolved to a local
        // name (or "Someone you know" when unresolved — never the raw phone). The
        // server's per-substitution `fallback` is reserved for future kinds this
        // client doesn't yet recognize.
        let titleResolutions = payload.titleSubstitutions.map { resolve($0.contact) }
        let bodyResolutions = payload.bodySubstitutions.map { resolve($0.contact) }

        bestAttemptContent.title = SubstitutionApplier.apply(
            template: bestAttemptContent.title,
            resolutions: titleResolutions.map { $0?.name }
        )
        bestAttemptContent.body = SubstitutionApplier.apply(
            template: bestAttemptContent.body,
            resolutions: bodyResolutions.map { $0?.name }
        )
        bestAttemptContent.threadIdentifier = payload.groupKey

        // "Sent You Cash" (CHAT) renders as a communication notification so the
        // sender's avatar — or the system monogram fallback — shows like a chat
        // app. Other categories keep the Flipcash app icon.
        if payload.category == .chat, let sender = titleResolutions.compactMap({ $0 }).first {
            contentHandler(communicationContent(
                from: bestAttemptContent,
                sender: sender,
                conversationIdentifier: payload.groupKey
            ))
            return
        }

        contentHandler(bestAttemptContent)
    }

    override func serviceExtensionTimeWillExpire() {
        if let contentHandler, let bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
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
}
