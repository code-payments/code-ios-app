//
//  DeepLinkController.swift
//  Code
//
//  Created by Dima Bart on 2023-04-14.
//

import Foundation
import CodeServices

@MainActor
final class DeepLinkController {
    
    private let sessionAuthenticator: SessionAuthenticator
    private let abacus: Abacus
    
    // MARK: - Init -
    
    init(sessionAuthenticator: SessionAuthenticator, abacus: Abacus) {
        self.sessionAuthenticator = sessionAuthenticator
        self.abacus = abacus
    }
    
    // MARK: - Handle -
    
    func handle(open url: URL) -> DeepLinkAction? {
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
                
            } else if let entropy = route.properties["data"] { // Handle legacy login links
                
                // Attempt base64 encoding first (deprecated) then base58
                guard let mnemonic = MnemonicPhrase(base64EncodedEntropy: entropy) ?? MnemonicPhrase(base58EncodedEntropy: entropy) else {
                    return nil
                }
                
                return actionForLogin(mnemonic: mnemonic)
            }
            
        case .cash:
            
            if
                let entropy = route.fragments[.entropy],
                let mnemonic = MnemonicPhrase(base58EncodedEntropy: entropy.value)
            {
                let giftCard = GiftCardAccount(mnemonic: mnemonic)
                return actionForReceiveRemoteSend(giftCard: giftCard)
            } else {
                ErrorReporting.captureError(Error.failedToParseGiftCard, id: "giftCard")
            }
            
        case .paymentRequest:
            
            if
                let payload = route.fragments[.payload],
                let data = payload.value.base64EncodedData(),
                let request = try? JSONDecoder().decode(DeepLinkRequest.self, from: data)
            {
                return DeepLinkAction(
                    kind: .paymentRequest(request),
                    sessionAuthenticator: sessionAuthenticator
                )
            } else {
                ErrorReporting.captureError(Error.failedToParsePaymentRequest, id: "micropayment")
            }
            
        case .loginRequest:
            
            if
                let payload = route.fragments[.payload],
                let data = payload.value.base64EncodedData(),
                let request = try? JSONDecoder().decode(DeepLinkRequest.self, from: data)
            {
                return DeepLinkAction(
                    kind: .loginRequest(request),
                    sessionAuthenticator: sessionAuthenticator
                )
            } else {
                ErrorReporting.captureError(Error.failedToParseLoginRequest, id: "webLogin")
            }
            
        case .tip(let username):
            
            return DeepLinkAction(
                kind: .tip(username),
                sessionAuthenticator: sessionAuthenticator
            )
            
        case .tipSDK:
            
            if
                let payload = route.fragments[.payload],
                let data = payload.value.base64EncodedData(),
                let request = try? JSONDecoder().decode(DeepLinkRequest.self, from: data),
                let username = request.platform?.username
            {
                return DeepLinkAction(
                    kind: .tip(username),
                    sessionAuthenticator: sessionAuthenticator
                )
            } else {
                ErrorReporting.captureError(Error.failedToParseTipLink, id: "tipLink")
            }
            
        default:
            break
        }
        
        return nil
    }
    
    private func actionForLogin(mnemonic: MnemonicPhrase) -> DeepLinkAction {
        DeepLinkAction(
            kind: .login(mnemonic),
            sessionAuthenticator: sessionAuthenticator
        )
    }
    
    private func actionForReceiveRemoteSend(giftCard: GiftCardAccount) -> DeepLinkAction {
        abacus.start(.cashLinkGrabTime)
        return DeepLinkAction(
            kind: .receiveRemoteSend(giftCard),
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
    
    let kind: Kind
    
    var confirmationDescription: ConfirmationDescription? {
        switch kind {
        case .login:
            guard sessionAuthenticator.isLoggedIn else {
                return nil
            }
            
            return .init(
                confirmation: Localized.Action.logout,
                title: Localized.Subtitle.logoutAndLoginConfirmation,
                description: nil
            )
            
        case .receiveRemoteSend, .paymentRequest, .loginRequest, .tip:
            return nil // Don't need confirmation
        }
    }
    
    private let sessionAuthenticator: SessionAuthenticator
    
    // MARK: - Init -
    
    init(kind: Kind, sessionAuthenticator: SessionAuthenticator) {
        self.kind = kind
        self.sessionAuthenticator = sessionAuthenticator
    }
    
    // MARK: - Execute -
    
    func executeAction() async throws {
        switch kind {
        case .login(let mnemonic):
            if case .loggedIn = sessionAuthenticator.state {
                sessionAuthenticator.logout()
            }
            sessionAuthenticator.completeLogin(with: try await sessionAuthenticator.initialize(using: mnemonic))
            
        case .receiveRemoteSend(let giftCard):
            if case .loggedIn(let container) = sessionAuthenticator.state {
                container.session.receiveRemoteSend(giftCard: giftCard)
            }
            
        case .paymentRequest(let request):
            if case .loggedIn(let container) = sessionAuthenticator.state, let paymentRequest = request.paymentRequest {
                // Delay the presentation of the bill
                try await Task.delay(milliseconds: 500)
                
                let payload = Code.Payload(
                    kind: paymentRequest.fees.isEmpty ? .requestPayment : .requestPaymentV2, // Only use v2 for payments with fees
                    fiat: paymentRequest.fiat,
                    nonce: request.clientSecret
                )
                
                container.session.attempt(payload, request: request)
            }
            
        case .loginRequest(let request):
            if case .loggedIn(let container) = sessionAuthenticator.state {
                
                // Delay the presentation of the bill
                try await Task.delay(milliseconds: 500)
                
                let payload = Code.Payload(
                    kind: .login,
                    kin: 0,
                    nonce: request.clientSecret
                )
                
                container.session.attempt(payload, request: request)
            }
            
        case .tip(let username):
            if case .loggedIn(let container) = sessionAuthenticator.state {
                
                // Delay the presentation of the bill
                try await Task.delay(milliseconds: 500)
                
                let payload = Code.Payload(
                    kind: .tip,
                    username: username
                )
                
                container.session.presentScannedTipCard(payload: payload, username: username)
            }
            
        }
    }
}

// MARK: - Kind -

extension DeepLinkAction {
    enum Kind {
        case login(MnemonicPhrase)
        case receiveRemoteSend(GiftCardAccount)
        case paymentRequest(DeepLinkRequest)
        case loginRequest(DeepLinkRequest)
        case tip(String)
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
