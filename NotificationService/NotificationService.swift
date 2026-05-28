//
//  NotificationService.swift
//  NotificationService
//

import UserNotifications
import FlipcashCore
import FlipcashAPI

/// Rewrites `CONTACT_JOIN` pushes to use the user's local contact name.
///
/// Phone-to-name resolution happens on-device inside this extension. The server
/// sends only E.164s and substitution placeholders; it never sees the user's
/// address book. The extension reads the locally-synced matched set and queries
/// `CNContactStore` directly — no network calls from the extension.
final class NotificationService: UNNotificationServiceExtension {

    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?

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

        guard let payload = NotificationPayload.decode(request.content.userInfo),
              let ownerBase58 = SharedDefaults.currentOwnerBase58 else {
            contentHandler(bestAttemptContent)
            return
        }

        let storeURL = AppGroup.containerURL
            .appendingPathComponent("flipcash-\(ownerBase58).sqlite")
        let resolver = ContactNameResolver(
            snapshotReader: ContactSnapshotReader(storeURL: storeURL),
            nameProvider: CNContactNameProvider()
        )

        let titleResolutions = payload.titleSubstitutions.map { resolver.resolve(phone: $0.contact) }
        let bodyResolutions = payload.bodySubstitutions.map { resolver.resolve(phone: $0.contact) }

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
}
