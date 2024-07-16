//
//  Chat.Reference.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import CodeAPI

extension Chat {
    /// An ID that can be referenced to the source of the exchange of Kin
    public enum Reference: Equatable, Hashable {
        case intent(PublicKey)
        case signature(Signature)
    }
}

// MARK: - Proto -

extension Chat.Reference {
    init?(_ proto: Code_Chat_V2_ExchangeDataContent.OneOf_Reference?) {
        guard let proto else {
            return nil
        }
        
        switch proto {
        case .intent(let p):
            guard let intentID = PublicKey(p.value) else {
                return nil
            }
            
            self = .intent(intentID)
            
        case .signature(let p):
            guard let signature = Signature(p.value) else {
                return nil
            }
            
            self = .signature(signature)
        }
    }
}

extension Chat.Reference {
    public static let mock: Chat.Reference = .intent(.mock)
}
