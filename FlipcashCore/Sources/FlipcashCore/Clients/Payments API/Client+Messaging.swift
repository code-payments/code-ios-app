//
//  Client+Messaging.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import Combine

extension Client {
    
    public func openMessageStream(rendezvous: KeyPair, completion: @MainActor @Sendable @escaping (Result<PaymentRequest, Error>) -> Void) -> AnyCancellable {
        messagingService.openMessageStream(rendezvous: rendezvous, completion: completion)
    }
    
    public func verifyRequestToGrabBill(destination: PublicKey, rendezvous: PublicKey, signature: Signature) -> Bool {
        messagingService.verifyRequestToGrabBill(destination: destination, rendezvous: rendezvous, signature: signature)
    }
    
    public func sendRequestToGrabBill(destination: PublicKey, rendezvous: KeyPair) async throws -> Bool {
        try await withCheckedThrowingContinuation { c in
            messagingService.sendRequestToGrabBill(destination: destination, rendezvous: rendezvous) { c.resume(with: $0) }
        }
    }
}
