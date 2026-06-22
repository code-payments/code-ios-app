//
//  SendCashIntent.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import AppIntents

/// Opens the app at the send amount-entry screen for a chosen contact. Launches
/// the app rather than completing the payment headlessly — entering an amount
/// and confirming always happens in-app, matching Apple's money-handling
/// guidance and the verified-state invariant a headless send would break.
///
/// `contact` is required so Siri/Spotlight prompt "who?" using the on-Flipcash
/// contacts the query offers, then proceed once one is chosen.
struct SendCashIntent: AppIntent {

    static let title: LocalizedStringResource = "Send Cash"
    static let description = IntentDescription("Start sending cash to one of your Flipcash contacts.")

    /// Bring the app to the foreground so the user finishes the send in-app.
    static let openAppWhenRun = true

    @Parameter(title: "To")
    var contact: ContactEntity

    func perform() async throws -> some IntentResult {
        guard await AppIntentContext.canSend else {
            throw SendCashIntentError.sendUnavailable
        }
        guard let resolved = await AppIntentContext.contact(withID: contact.id) else {
            throw SendCashIntentError.recipientUnavailable
        }
        await AppIntentContext.openSendFlow(to: resolved)
        return .result()
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Send cash to \(\.$contact)")
    }
}

enum SendCashIntentError: Error, CustomLocalizedStringResourceConvertible {
    case sendUnavailable
    case recipientUnavailable

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .sendUnavailable:      "Sending isn’t available yet."
        case .recipientUnavailable: "That contact isn’t available to send to."
        }
    }
}
