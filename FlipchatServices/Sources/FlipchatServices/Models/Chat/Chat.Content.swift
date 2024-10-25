//
//  ChatLegacy.Content.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipchatAPI
import CodeServices

extension Chat {
    public enum Content: Equatable, Hashable, Sendable {
        case text(String)
        case localized(String)
        case sodiumBox(EncryptedData)
    }
}

extension Chat.Content: Identifiable {
    public var id: String {
        switch self {
        case .text(let value):
            return "text:\(value)"
        case .localized(let value):
            return "localized:\(value)"
        case .sodiumBox(let data):
            return "nacl:\(data.nonce.hexEncodedString())"
        }
    }
}

// MARK: - Proto -

extension Chat.Content {
    
    public var protoContent: Flipchat_Messaging_V1_Content {
        switch self {
        case .text(let string):
            return .with {
                $0.text = .with {
                    $0.text = string
                }
            }
            
        case .localized, .sodiumBox:
            fatalError("Content unsupported")
        }
    }
    
    public init?(_ proto: Flipchat_Messaging_V1_Content) {
        guard let type = proto.type else {
            return nil
        }
        
        switch type {
        case .localized(let localizedContent):
            self = .localized(localizedContent.keyOrText)
            
        case .text(let textContent):
            self = .text(textContent.text)
            
        case .naclBox(let encryptedContent):
            guard let peerPublicKey = PublicKey(encryptedContent.peerPublicKey.value) else {
                return nil
            }
            
            let data = EncryptedData(
                peerPublicKey: peerPublicKey,
                nonce: encryptedContent.nonce,
                encryptedData: encryptedContent.encryptedPayload
            )
            
            self = .sodiumBox(data)
        }
    }
}
