//
//  DeepLinkController.swift
//  Code
//
//  Created by Dima Bart on 2023-04-14.
//

import Foundation
import UIKit
import FlipcashCore

private let logger = Logger(label: "flipcash.deeplink")

final class DeepLinkController {

    private let sessionAuthenticator: SessionAuthenticator

    private var inFlightDeepLinks: Set<URL> = []

    /// How long a URL stays deduped after its action finishes.
    private let repeatWindow: Duration

    // MARK: - Init -

    init(sessionAuthenticator: SessionAuthenticator, repeatWindow: Duration = .seconds(5)) {
        self.sessionAuthenticator = sessionAuthenticator
        self.repeatWindow = repeatWindow
    }

    // MARK: - Open -

    /// The canonical deep-link entry: dedups opens of the same URL within a short window, records
    /// analytics, and executes the parsed action. Returns false when the URL parses to no action.
    @discardableResult
    func open(_ url: URL) -> Bool {
        // Drop duplicate deliveries: a second claim is rejected server-side as
        // stale state and surfaces as a false error after the first succeeded.
        // A cold-launch link arrives twice — once from `SceneDelegate`, and
        // again from SwiftUI's `onOpenURL` when it replays the link, which can
        // land after the first action has finished — so the URL stays held for
        // `repeatWindow` past completion, not just while in flight.
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
            // Every action below reroutes what's on screen, and a link can land
            // while a text field elsewhere still holds focus — most often a chat
            // composer the user left focused. Take the keyboard down before any
            // of it runs. A one-shot, so a destination that focuses a field of
            // its own on appear still gets its keyboard: that ask comes after
            // this. It does not survive the first-responder restore that scene
            // activation performs, which is why the tipcard path additionally bars
            // the keyboard for a window (see `KeyboardSuppressor`).
            KeyboardSuppressor.lower()
        }

        Task {
            try? await action?.executeAction()
            try? await Task.sleep(for: repeatWindow)
            self.inFlightDeepLinks.remove(url)
        }

        return action != nil
    }

    // MARK: - Handle -

    func handle(open url: URL) -> DeepLinkAction? {
        
        if let container = sessionAuthenticator.loggedInContainer {
            container.walletConnection.didReceiveURL(url: url)
        }
        
        // Handle jump subdomains by forwarding the underlying
        // URL to the correct handler. Don't perform any
        // other action on jump subdomains.
        if let jumpURL = Route.unwrappingJump(url) {
            logger.info("Jumping to", metadata: ["url": "\(jumpURL.sanitizedForAnalytics)"])
            return handle(open: jumpURL)
        }
        
        // Not every URL that reaches here came through the associated-domains entitlement: a
        // tapped chat link and a scanned QR code both arrive at this method, and `Route` matches
        // on path alone, so `discord.gg/<invite>` would name a tipcard and `<anything>/login#e=…`
        // an account switch. Only our own hosts get to name an action; everything else resolves to
        // nil, which is what tells the chat screen to open the link externally instead.
        guard Route.isFlipcashLink(url) else {
            return nil
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

        case .username(let username):
            return action(.username(username))

        case .give:
            return action(.openSheet(.give))

        case .balance:
            return action(.wallet)

        case .discover:
            return action(.discoverCurrencies)

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

    /// Routes a chat id to its surface. Tip DMs and group chats are navigable — contact DMs
    /// are no longer surfaced in the app. The push payload carries no type, so
    /// the controller resolves it, hydrating an id the feed doesn't know yet
    /// (e.g. a first-ever tip's push) so the routed screen finds it populated.
    ///
    /// `GetGroupChatFeed` carries only the groups the user has joined, so for a group they have not
    /// joined this link is the only way in — and the screen it lands on is the one that offers the join.
    private static func routeChat(_ conversationID: ConversationID, in container: SessionContainer) async {
        let conversation = await container.conversationController.hydratedConversation(withID: conversationID)

        guard let destination = chatDestination(for: conversation?.type, conversationID: conversationID) else {
            logger.info("Ignoring non-tip chat deeplink", metadata: [
                "conversationID": "\(conversationID)",
            ])
            return
        }

        container.appRouter.navigate(to: destination)
    }

    /// The screen a chat id opens, or nil when it isn't one the app surfaces.
    ///
    /// A group routes to the same transcript a tip DM does whether or not the viewer is a member:
    /// the screen gates itself, so an invite link and a push tap land on one destination.
    static func chatDestination(for type: ConversationType?, conversationID: ConversationID) -> AppRouter.Destination? {
        switch type {
        case .tipDm, .group:
            return .tipConversation(conversationID)
        case .contactDm, nil:
            return nil
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
                // The wallet opens the token as its expanded card, so a link
                // lands exactly where tapping the card would — same chrome, same
                // dismissal. Pushing it instead gives a screen with a back
                // chevron that belongs to a stack the user never navigated.
                let router = container.appRouter
                router.setPath([], on: .balance)
                router.requestedTabStack = .balance
                router.requestedCardMint = mint
            }

        case .chat(let conversationID):
            if let container = sessionAuthenticator.loggedInContainer {
                Analytics.deeplinkRouted(kind: kind)
                await Self.routeChat(conversationID, in: container)
            }

        case .chatSendCash(let conversationID):
            if let container = sessionAuthenticator.loggedInContainer {
                // Only tip DMs resolve a send target now; contact/phone sends are no longer
                // surfaced, and a group has no single payee (`SendTarget.init` returns nil for one,
                // which is why a group push carries no Send Cash action to begin with).
                guard let target = SendTarget(
                    conversation: await container.conversationController.hydratedConversation(withID: conversationID),
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

        case .username(let username):
            if let container = sessionAuthenticator.loggedInContainer {
                Analytics.deeplinkRouted(kind: kind)
                // Same destination as `.tip`, reached by handle — including the
                // own-handle case, which `begin` routes to the user's own card.
                container.tipFlow.begin(username: username)
            }

        case .wallet:
            if let container = sessionAuthenticator.loggedInContainer {
                Analytics.deeplinkRouted(kind: kind)
                // `flipcash://balance` means "show me the wallet" — bring the tab
                // forward at its root rather than pushing anything onto it.
                let router = container.appRouter
                while router.presentedSheet != nil { router.dismissSheet() }
                router.setPath([], on: .balance)
                router.requestedTabStack = .balance
            }

        case .discoverCurrencies:
            if let container = sessionAuthenticator.loggedInContainer {
                Analytics.deeplinkRouted(kind: kind)
                // Discover is a push from the wallet, the same as its tile.
                container.appRouter.navigate(to: .discoverCurrencies)
            }

        case .openSheet(let sheet):
            if let container = sessionAuthenticator.loggedInContainer {
                Analytics.deeplinkRouted(kind: kind)
                if sheet == .give {
                    let rate = container.ratesController.rateForBalanceCurrency()
                    let gate = giveCashGate(session: container.session, rate: rate)
                    if let dialog = gate.blockingDialog(router: container.appRouter, addMoneySource: .giveShortfall) {
                        container.session.dialogItem = dialog
                        return
                    }
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
        case chatSendCash(ConversationID)
        case tip(UserID)
        case username(Username)
        /// The Wallet tab, at its root.
        case wallet
        /// Discover, pushed onto the Wallet tab.
        case discoverCurrencies
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
        case .username:             "Username"
        case .wallet:               "Wallet"
        case .discoverCurrencies:   "DiscoverCurrencies"
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
