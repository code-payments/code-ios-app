//
//  DeepLinkController.swift
//  Code
//
//  Created by Dima Bart on 2023-04-14.
//

import Foundation
import FlipcashCore

@MainActor
final class DeepLinkController {
    
    private let sessionAuthenticator: SessionAuthenticator
    
    // MARK: - Init -
    
    init(sessionAuthenticator: SessionAuthenticator) {
        self.sessionAuthenticator = sessionAuthenticator
    }
    
    // MARK: - Handle -
    
    func handle(open url: URL) -> DeepLinkAction? {
        
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

            trace(.warning, components: "Jumping to: \(jumpURL)")
            return handle(open: jumpURL)
        }
        
        // Resume handling URLs
        
        guard let route = Route(url: url) else {
            return nil
        }
        
        trace(.warning, components: "Deep link: \(url.absoluteString)")
        
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
                let giftCard = GiftCardCluster(mnemonic: mnemonic)
                return actionForReceiveRemoteSend(giftCard: giftCard)
            }
            
        case .pool:
            if
                let rendezvousSeed = route.fragments[.entropy],
                let seed = Seed32(base58: rendezvousSeed.value)
            {
                let rendezvous = KeyPair(seed: seed)
                return actionForOpenPool(rendezvous: rendezvous)
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
                
                var action = actionForVerificationCode(
                    email: email,
                    code: code,
                    clientData: clientData
                )

                // Only prevent user interface reset when
                // the onboarding flow is midflight.
                if case .loggedIn(let container) = sessionAuthenticator.state, container.onrampViewModel.isMidlight {
                    action.preventUserInterfaceReset = true
                }
                
                return action
            }
            
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
    
    private func actionForReceiveRemoteSend(giftCard: GiftCardCluster) -> DeepLinkAction {
        DeepLinkAction(
            kind: .receiveCashLink(giftCard),
            sessionAuthenticator: sessionAuthenticator
        )
    }
    
    private func actionForOpenPool(rendezvous: KeyPair) -> DeepLinkAction {
        DeepLinkAction(
            kind: .pool(rendezvous),
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
}

extension DeepLinkController {
    enum Error: Swift.Error {
        case failedToParsePaymentRequest
        case failedToParseLoginRequest
        case failedToParseTipLink
        case failedToParseGiftCard
    }
}

@MainActor
struct DeepLinkAction {
    
    var preventUserInterfaceReset: Bool = false
    
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
            
        case .receiveCashLink(let giftCard):
            if case .loggedIn(let container) = sessionAuthenticator.state {
                container.session.receiveCashLink(giftCard: giftCard)
            }
            
        case .pool(let rendezvous):
            if case .loggedIn(let container) = sessionAuthenticator.state {
                container.poolViewModel.openPoolFromDeeplink(rendezvous: rendezvous)
            }
            
        case .verifyEmail(let description):
            if case .loggedIn(let container) = sessionAuthenticator.state {
                container.onrampViewModel.confirmEmailFromDeeplinkAction(verification: description)
            }
        }
    }
}

// MARK: - Kind -

extension DeepLinkAction {
    enum Kind {
        case accessKey(MnemonicPhrase)
        case receiveCashLink(GiftCardCluster)
        case pool(KeyPair)
        case verifyEmail(VerificationDescription)
    }
}

struct VerificationDescription: Identifiable {
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
