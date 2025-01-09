//
//  DeepLinkController.swift
//  Code
//
//  Created by Dima Bart on 2023-04-14.
//

import Foundation
import FlipchatServices

@MainActor
final class DeepLinkController {
    
    private let sessionAuthenticator: SessionAuthenticator
    
    // MARK: - Init -
    
    init(sessionAuthenticator: SessionAuthenticator) {
        self.sessionAuthenticator = sessionAuthenticator
    }
    
    // MARK: - Handle -
    
    func handle(open url: URL) -> DeepLinkAction? {
        guard let route = try? Route(url: url) else {
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
            
        case .room(let roomNumber):
            var messageID: MessageID?
            
            if let stringID = route.value(for: .message), let data = Data(fromHexEncodedString: stringID) {
                messageID = MessageID(data: data)
            }
            
            return actionForRoom(roomNumber: roomNumber, messageID: messageID)
            
        case .user:
            break
            
        case .unknown:
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
    
    private func actionForRoom(roomNumber: RoomNumber, messageID: MessageID?) -> DeepLinkAction {
        return DeepLinkAction(
            kind: .room(roomNumber, messageID),
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
            
        case .room:
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
            
            sessionAuthenticator.completeLogin(with: try await sessionAuthenticator.initialize(using: mnemonic, name: nil, isRegistration: false))
            
        case .room(let roomNumber, let messageID):
            guard case .loggedIn(let container) = sessionAuthenticator.state else {
                return
            }
            
            try await Task.delay(milliseconds: 250)
            
            container.chatViewModel.previewChat(
                roomNumber: roomNumber,
                showSuccess: false,
                showModally: true
            )
        }
    }
}

// MARK: - Kind -

extension DeepLinkAction {
    enum Kind {
        case login(MnemonicPhrase)
        case room(RoomNumber, MessageID?)
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
