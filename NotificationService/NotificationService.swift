//
//  NotificationService.swift
//  NotificationService
//

import UserNotifications
import Contacts
import FlipcashCore
import FlipcashAPI

/// Rewrites `CONTACT_JOIN` pushes to use the user's local contact name.
///
/// Phone-to-name resolution happens on-device. The server sends only E.164s
/// and substitution placeholders; the extension queries `CNContactStore`
/// directly with each phone and applies positional substitutions.
final class NotificationService: UNNotificationServiceExtension {

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

        let titleResolutions = payload.titleSubstitutions.map { resolve($0.contact) }
        let bodyResolutions = payload.bodySubstitutions.map { resolve($0.contact) }

        bestAttemptContent.title = SubstitutionApplier.apply(
            template: bestAttemptContent.title,
            resolutions: titleResolutions
        )
        bestAttemptContent.body = SubstitutionApplier.apply(
            template: bestAttemptContent.body,
            resolutions: bodyResolutions
        )
        bestAttemptContent.threadIdentifier = payload.groupKey

        contentHandler(bestAttemptContent)
    }

    override func serviceExtensionTimeWillExpire() {
        if let contentHandler, let bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }

    /// Returns the display name of the first contact matching `phone`, or
    /// `nil` if no contact matches or Contacts permission is unavailable.
    private func resolve(_ phone: Flipcash_Phone_V1_PhoneNumber) -> String? {
        let predicate = CNContact.predicateForContacts(
            matching: CNPhoneNumber(stringValue: phone.value)
        )
        let keys = [CNContactFormatter.descriptorForRequiredKeys(for: .fullName)]
        guard let contact = try? contactStore.unifiedContacts(matching: predicate, keysToFetch: keys).first else {
            return nil
        }
        return CNContactFormatter.string(from: contact, style: .fullName)
    }
}
