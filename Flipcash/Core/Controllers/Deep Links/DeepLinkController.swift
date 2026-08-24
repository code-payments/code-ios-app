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

    private var inFlightDeepLinks: Set<URL> = []

    // MARK: - Init -

    init(sessionAuthenticator: SessionAuthenticator) {
        self.sessionAuthenticator = sessionAuthenticator
    }

    // MARK: - Open -

    /// The canonical deep-link entry: dedups concurrent opens of the same URL, records analytics, and
    /// executes the parsed action. Returns false when the URL parses to no action.
    @discardableResult
    func open(_ url: URL) -> Bool {
        // Drop duplicate in-flight deliveries: a concurrent second claim is
        // rejected server-side as stale state and surfaces as a false error
        // after the first claim has already succeeded.
        guard inFlightDeepLinks.insert(url).inserted else {
            logger.info("Ignoring duplicate deep link", metadata: ["url": "\(url.sanitizedForAnalytics)"])
            return true
        }

        Analytics.deeplinkOpened(url: url)
        let action = handle(open: url)
        // Only record a parse result for URLs that resolve to an action. Chat links now route through
        // here too, and most are ordinary web URLs — logging every non-match as a "failed to parse"
        // error would bury genuine deep-link parse failures in expected noise.
        if let action {
            Analytics.deeplinkParsed(action: action, url: url)
        }

        Task {
            defer { self.inFlightDeepLinks.remove(url) }
            try await action?.executeAction()
        }

        return action != nil
    }

    // MARK: - Handle -

    func handle(open url: URL) -> DeepLinkAction? {
        
        if let container = sessionAuthenticator.loggedInContainer {
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
                return action(.accessKey(mnemonic))
            }
            
        case .cash:
            
            if
                let entropy = route.fragments[.entropy],
                let mnemonic = MnemonicPhrase(base58EncodedEntropy: entropy.value)
            {
                return action(.receiveCashLink(mnemonic))
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
                
                return action(.verifyEmail(
                    .init(
                        email: email,
                        code: code,
                        clientData: clientData
                    )
                ))
            }
            
        case .token(let mint):
            return action(.currencyInfo(mint))

        case .chat(let conversationID):
            return action(.chat(conversationID))

        case .chatSendCash(let conversationID):
            return action(.chatSendCash(conversationID))

        case .tip(let userID):
            return action(.tip(userID))

        case .give:
            return action(.openSheet(.give))

        case .balance:
            return action(.openSheet(.balance))

        case .discover:
            return action(.openSheet(.discover))

        case .unknown:
            break
        }

        return nil
    }
    
    private func action(_ kind: DeepLinkAction.Kind) -> DeepLinkAction {
        DeepLinkAction(kind: kind, sessionAuthenticator: sessionAuthenticator)
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

    /// Routes a chat id to its surface. Only tip DMs are navigable — contact DMs
    /// are no longer surfaced in the app. The push payload carries no type, so
    /// the controller resolves it, hydrating an id the feed doesn't know yet
    /// (e.g. a first-ever tip's push) so the routed screen finds it populated.
    private static func routeChat(_ conversationID: ConversationID, in container: SessionContainer) async {
        let conversation = await container.conversationController.hydratedConversation(withID: conversationID)

        switch conversation?.type {
        case .tipDm:
            container.appRouter.navigate(to: .tipConversation(conversationID))
        case .contactDm, .group, nil:
            logger.info("Ignoring non-tip chat deeplink", metadata: [
                "conversationID": "\(conversationID)",
            ])
        }
    }

    func executeAction() async throws {
        logger.info("Executing deep link action", metadata: ["kind": "\(kind.analyticsName)"])

        switch kind {
        case .accessKey(let mnemonic):
            if let sessionContainer = sessionAuthenticator.loggedInContainer {
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
            if let container = sessionAuthenticator.loggedInContainer {
                Analytics.deeplinkRouted(kind: kind)
                container.session.receiveCashLink(mnemonic: mnemonic)
            }

        case .verifyEmail(let description):
            if let container = sessionAuthenticator.loggedInContainer {
                container.onrampDeeplinkInbox.pendingEmailVerification = description
            }

        case .currencyInfo(let mint):
            if let container = sessionAuthenticator.loggedInContainer {
                Analytics.deeplinkRouted(kind: kind)
                let router = container.appRouter
                if router.tabStacks.contains(.balance) {
                    // v2: the wallet opens the token as its expanded card, so a
                    // link lands exactly where tapping the card would — same
                    // chrome, same dismissal. Pushing it instead gives a screen
                    // with a back chevron that belongs to a stack the user never
                    // navigated.
                    router.setPath([], on: .balance)
                    router.requestedTabStack = .balance
                    router.requestedCardMint = mint
                } else {
                    router.navigate(to: .currencyInfo(mint))
                }
            }

        case .chat(let conversationID):
            if let container = sessionAuthenticator.loggedInContainer {
                Analytics.deeplinkRouted(kind: kind)
                await Self.routeChat(conversationID, in: container)
            }

        case .chatSendCash(let conversationID):
            if let container = sessionAuthenticator.loggedInContainer {
                let conversation = await container.conversationController.hydratedConversation(withID: conversationID)
                // Only tip DMs resolve a send target now; contact/phone sends
                // are no longer surfaced.
                guard let target = SendTarget(
                    conversation: conversation,
                    dmChatID: conversationID.data,
                    selfUserID: container.session.userID
                ), case .tip = target else { return }

                Analytics.deeplinkRouted(kind: kind)
                // Open the Send Cash amount entry directly as the sheet — one
                // animation, no chat behind it. Dismissing returns to where the
                // user was (the chat itself is reachable via the chat deeplink).
                container.appRouter.present(.sendAmount(target))
            }

        case .tip(let userID):
            if let container = sessionAuthenticator.loggedInContainer {
                Analytics.deeplinkRouted(kind: kind)
                // `begin` owns the own-id case: a self link lands on the user's
                // own tip card rather than starting a tip.
                container.tipFlow.begin(userID: userID)
            }

        case .openSheet(let sheet):
            if let container = sessionAuthenticator.loggedInContainer {
                Analytics.deeplinkRouted(kind: kind)
                if sheet == .give {
                    let rate = container.ratesController.rateForBalanceCurrency()
                    let gate = giveCashGate(session: container.session, rate: rate, includingDollars: BetaFlags.shared.allowsDollarsGive)
                    if let dialog = gate.blockingDialog(router: container.appRouter, addMoneySource: .giveShortfall) {
                        container.session.dialogItem = dialog
                        return
                    }
                }
                let router = container.appRouter
                // Discover is a push from the wallet in the tab UI, the same as
                // its tile — its own sheet is the v1 route in.
                if sheet == .discover, router.tabStacks.contains(.balance) {
                    router.navigate(to: .discoverCurrencies)
                    return
                }

                // A sheet whose stack a tab owns is that tab — `flipcash://balance`
                // means "show me the wallet", and presenting the sheet puts the v1
                // balance list over the wallet tab instead of selecting it.
                let stack = sheet.stack
                if router.tabStacks.contains(stack) {
                    while router.presentedSheet != nil { router.dismissSheet() }
                    router.setPath([], on: stack)
                    router.requestedTabStack = stack
                } else {
                    router.present(sheet)
                }
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
        case chatSendCash(ConversationID)
        case tip(UserID)
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
        case .chatSendCash:         "ChatSendCash"
        case .tip:                  "Tip"
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
