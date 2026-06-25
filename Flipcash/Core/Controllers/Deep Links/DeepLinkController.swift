//
//  DeepLinkController.swift
//  Code
//
//  Created by Dima Bart on 2023-04-14.
//

import Foundation
import FlipcashCore

private let logger = Logger(label: "flipcash.deeplink")

final class DeepLinkController {
    
    private let sessionAuthenticator: SessionAuthenticator
    
    // MARK: - Init -
    
    init(sessionAuthenticator: SessionAuthenticator) {
        self.sessionAuthenticator = sessionAuthenticator
    }
    
    // MARK: - Handle -
    
    func handle(open url: URL) -> DeepLinkAction? {
        
        if case .loggedIn(let container) = sessionAuthenticator.state {
            container.walletConnection.didReceiveURL(url: url)
        }
        
        // Hadle jump subdomains by forwarding the underlying
        // URL to the correct handler. Don't perform any
        // other action on jump subdomains.
        let prefix = "https://jump.flipcash.com/#source="
        let urlString = url.absoluteString
        if urlString.hasPrefix(prefix) {

            let jumpString = urlString.replacingOccurrences(of: prefix, with: "")
            guard
                let decodedString = jumpString.removingPercentEncoding,
                let jumpURL = URL(string: decodedString)
            else {
                return nil
            }

            logger.info("Jumping to", metadata: ["url": "\(jumpURL.sanitizedForAnalytics)"])
            return handle(open: jumpURL)
        }
        
        // Resume handling URLs
        
        guard let route = Route(url: url) else {
            return nil
        }
        
        logger.debug("Deep link", metadata: ["url": "\(url.sanitizedForAnalytics)"])
        
        switch route.path {
        case .login:
            
            if
                let entropy = route.fragments[.entropy],
                let mnemonic = MnemonicPhrase(base58EncodedEntropy: entropy.value)
            {
                return actionForLogin(mnemonic: mnemonic)
            }
            
        case .cash:
            
            if
                let entropy = route.fragments[.entropy],
                let mnemonic = MnemonicPhrase(base58EncodedEntropy: entropy.value)
            {
                return actionForReceiveRemoteSend(mnemonic: mnemonic)
            }
            
        case .verifyEmail:
            if
                let code = route.properties["code"],
                let email = route.properties["email"]
            {
                var clientData: String? = route.properties["clientData"]
                if let c = clientData, c.isEmpty {
                    clientData = nil
                }
                
                return actionForVerificationCode(
                    email: email,
                    code: code,
                    clientData: clientData
                )
            }
            
        case .token(let mint):
            return actionForCurrencyInfo(mint: mint)

        case .chat(let conversationID):
            return actionForChat(conversationID: conversationID)

        case .chatContact(let phone):
            return actionForChatContact(phone: phone)

        case .chatSendCash(let conversationID):
            return actionForChatSendCash(conversationID: conversationID)

        case .give:
            return actionForOpenSheet(.give)

        case .balance:
            return actionForOpenSheet(.balance)

        case .discover:
            return actionForOpenSheet(.discover)

        case .send:
            return actionForOpenSheet(.send)

        case .unknown:
            break
        }

        return nil
    }
    
    private func actionForLogin(mnemonic: MnemonicPhrase) -> DeepLinkAction {
        DeepLinkAction(
            kind: .accessKey(mnemonic),
            sessionAuthenticator: sessionAuthenticator
        )
    }
    
    private func actionForReceiveRemoteSend(mnemonic: MnemonicPhrase) -> DeepLinkAction {
        DeepLinkAction(
            kind: .receiveCashLink(mnemonic),
            sessionAuthenticator: sessionAuthenticator
        )
    }
    
    private func actionForVerificationCode(email: String, code: String, clientData: String?) -> DeepLinkAction {
        DeepLinkAction(
            kind: .verifyEmail(
                .init(
                    email: email,
                    code: code,
                    clientData: clientData
                )
            ),
            sessionAuthenticator: sessionAuthenticator
        )
    }

    private func actionForCurrencyInfo(mint: PublicKey) -> DeepLinkAction {
        DeepLinkAction(
            kind: .currencyInfo(mint),
            sessionAuthenticator: sessionAuthenticator
        )
    }

    private func actionForChat(conversationID: ConversationID) -> DeepLinkAction {
        DeepLinkAction(
            kind: .chat(conversationID),
            sessionAuthenticator: sessionAuthenticator
        )
    }

    private func actionForChatContact(phone: Phone) -> DeepLinkAction {
        DeepLinkAction(
            kind: .chatContact(phone),
            sessionAuthenticator: sessionAuthenticator
        )
    }

    private func actionForChatSendCash(conversationID: ConversationID) -> DeepLinkAction {
        DeepLinkAction(
            kind: .chatSendCash(conversationID),
            sessionAuthenticator: sessionAuthenticator
        )
    }

    private func actionForOpenSheet(_ sheet: AppRouter.SheetPresentation) -> DeepLinkAction {
        DeepLinkAction(
            kind: .openSheet(sheet),
            sessionAuthenticator: sessionAuthenticator
        )
    }
}

struct DeepLinkAction {

    let kind: Kind
    
    private let sessionAuthenticator: SessionAuthenticator
    
    // MARK: - Init -
    
    init(kind: Kind, sessionAuthenticator: SessionAuthenticator) {
        self.kind = kind
        self.sessionAuthenticator = sessionAuthenticator
    }
    
    // MARK: - Execute -
    
    func executeAction() async throws {
        logger.info("Executing deep link action", metadata: ["kind": "\(kind.analyticsName)"])

        switch kind {
        case .accessKey(let mnemonic):
            if case .loggedIn(let sessionContainer) = sessionAuthenticator.state {
                guard mnemonic != sessionContainer.session.keyAccount.mnemonic else {
                    return
                }

                sessionContainer.session.attemptLogin(with: mnemonic) {
                    sessionAuthenticator.switchAccount(to: mnemonic)
                }

            } else {
                sessionAuthenticator.switchAccount(to: mnemonic)
            }

        case .receiveCashLink(let mnemonic):
            if case .loggedIn(let container) = sessionAuthenticator.state {
                Analytics.deeplinkRouted(kind: kind)
                container.session.receiveCashLink(mnemonic: mnemonic)
            }

        case .verifyEmail(let description):
            if case .loggedIn(let container) = sessionAuthenticator.state {
                container.onrampDeeplinkInbox.pendingEmailVerification = description
            }

        case .currencyInfo(let mint):
            if case .loggedIn(let container) = sessionAuthenticator.state {
                Analytics.deeplinkRouted(kind: kind)
                container.appRouter.navigate(to: .currencyInfo(mint))
            }

        case .chat(let conversationID):
            if case .loggedIn(let container) = sessionAuthenticator.state {
                Analytics.deeplinkRouted(kind: kind)
                // Present the chat as the root (bottom) sheet so anything stacked
                // on top — Send Cash — reveals the chat when dismissed.
                container.appRouter.present(.conversation(.existing(conversationID)))
            }

        case .chatContact(let phone):
            if case .loggedIn(let container) = sessionAuthenticator.state {
                Analytics.deeplinkRouted(kind: kind)
                // Resolve the phone against the synced directory. No match (not a
                // contact, or contact sync hasn't settled yet) is a silent no-op,
                // like any other unresolvable deeplink. The `.contact` context
                // resolves the `dmChatID` live and opens whether or not the chat
                // exists yet.
                guard let contact = container.contactSyncController.resolvedContacts.onFlipcash
                    .first(where: { $0.phoneE164 == phone.e164 }) else {
                    logger.info("No synced contact for chat deeplink phone — ignoring")
                    return
                }
                container.appRouter.present(.conversation(.contact(contact)))
            }

        case .chatSendCash(let conversationID):
            if case .loggedIn(let container) = sessionAuthenticator.state {
                let conversation = container.conversationController.conversation(withID: conversationID)
                if let target = ResolvedContact.sendTarget(
                    in: conversation,
                    dmChatID: conversationID.data,
                    selfUserID: container.session.userID
                ), container.session.canSend {
                    Analytics.deeplinkRouted(kind: kind)
                    // Open the Send Cash amount entry directly as the sheet — one
                    // animation, no chat behind it. Dismissing returns to where the
                    // user was (the chat itself is reachable via the chat deeplink).
                    container.appRouter.present(.sendAmount(target))
                }
            }

        case .openSheet(let sheet):
            if case .loggedIn(let container) = sessionAuthenticator.state {
                Analytics.deeplinkRouted(kind: kind)
                if sheet == .give {
                    let rate = container.ratesController.rateForBalanceCurrency()
                    guard container.session.hasGiveableBalance(for: rate) else {
                        container.session.dialogItem = .noGiveableBalance {
                            container.appRouter.navigate(to: .deposit)
                        }
                        return
                    }
                }
                if sheet == .send {
                    guard container.session.canSend else { return }
                }
                container.appRouter.present(sheet)
            }
        }
    }
}

// MARK: - Kind -

extension DeepLinkAction {
    enum Kind {
        case accessKey(MnemonicPhrase)
        case receiveCashLink(MnemonicPhrase)
        case verifyEmail(VerificationDescription)
        case currencyInfo(PublicKey)
        case chat(ConversationID)
        case chatContact(Phone)
        case chatSendCash(ConversationID)
        case openSheet(AppRouter.SheetPresentation)
    }
}

extension DeepLinkAction.Kind {
    var analyticsName: String {
        switch self {
        case .accessKey:            "Login"
        case .receiveCashLink:      "CashLink"
        case .verifyEmail:          "EmailVerification"
        case .currencyInfo:         "TokenInfo"
        case .chat:                 "Chat"
        case .chatContact:          "ChatContact"
        case .chatSendCash:         "ChatSendCash"
        case .openSheet(let sheet): "Sheet:\(sheet)"
        }
    }
}

struct VerificationDescription: Identifiable, Equatable {
    var email: String
    var code: String
    var clientData: String?

    var id: String {
        "\(email):\(code)"
    }
}
