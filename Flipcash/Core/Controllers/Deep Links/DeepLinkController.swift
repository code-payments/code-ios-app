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

        case .give:
            return actionForOpenSheet(.give)

        case .wallet:
            return actionForOpenSheet(.balance)

        case .discover:
            return actionForOpenSheet(.discover)

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

    private func actionForOpenSheet(_ sheet: AppRouter.SheetPresentation) -> DeepLinkAction {
        DeepLinkAction(
            kind: .openSheet(sheet),
            sessionAuthenticator: sessionAuthenticator
        )
    }
}

extension DeepLinkController {
    enum Error: Swift.Error {
        case failedToParsePaymentRequest
        case failedToParseLoginRequest
        case failedToParseTipLink
        case failedToParseGiftCard
    }
}

struct DeepLinkAction {

    let kind: Kind
    
//    var confirmationDescription: ConfirmationDescription? {
//        switch kind {
//        case .accessKey:
//            guard sessionAuthenticator.isLoggedIn else {
//                return nil
//            }
//            
//            return .init(
//                confirmation: "Log Out",
//                title: "You're currently logged into an account. Please ensure you have saved your Access Key before proceeding. Would you like to logout and login with a new account?",
//                description: nil
//            )
//            
//        case .receiveCashLink:
//            return nil // Don't need confirmation
//        }
//    }
    
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

        case .openSheet(let sheet):
            if case .loggedIn(let container) = sessionAuthenticator.state {
                Analytics.deeplinkRouted(kind: kind)
                if sheet == .give {
                    let rate = container.ratesController.rateForBalanceCurrency()
                    guard container.session.hasGiveableBalance(for: rate) else {
                        container.session.dialogItem = .noGiveableBalance(
                            onDiscover: { container.appRouter.present(.discover) }
                        )
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
        case openSheet(AppRouter.SheetPresentation)
    }
}

extension DeepLinkAction.Kind {
    var analyticsName: String {
        switch self {
        case .accessKey:        "Login"
        case .receiveCashLink:  "CashLink"
        case .verifyEmail:      "EmailVerification"
        case .currencyInfo:     "TokenInfo"
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

// MARK: - ConfirmationDescription -

extension DeepLinkAction {
    struct ConfirmationDescription {
        var confirmation: String
        var title: String?
        var description: String?
    }
}
