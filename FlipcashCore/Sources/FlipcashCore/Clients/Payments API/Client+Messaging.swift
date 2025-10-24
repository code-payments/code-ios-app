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
    
    public func openMessageStream(rendezvous: KeyPair, completion: @MainActor @Sendable @escaping (Result<[StreamMessage], Error>) -> Void) -> AnyCancellable {
        messagingService.openMessageStream(rendezvous: rendezvous, completion: completion)
    }
    
    public func fetchMessages(rendezvous: KeyPair) async throws -> [StreamMessage] {
        try await withCheckedThrowingContinuation { c in
            messagingService.fetchMessages(rendezvous: rendezvous) { c.resume(with: $0) }
        }
    }
    
    public func verifyRequestToGrabBill(destination: PublicKey, rendezvous: PublicKey, signature: Signature) -> Bool {
        messagingService.verifyRequestToGrabBill(destination: destination, rendezvous: rendezvous, signature: signature)
    }
    
    public func sendRequestToGrabBill(destination: PublicKey, rendezvous: KeyPair) async throws -> Bool {
        try await withCheckedThrowingContinuation { c in
            messagingService.sendRequestToGrabBill(destination: destination, rendezvous: rendezvous) { c.resume(with: $0) }
        }
    }
    
    public func sendRequestToGiveBill(mint: PublicKey, rendezvous: KeyPair) async throws -> Bool {
        try await withCheckedThrowingContinuation { c in
            messagingService.sendRequestToGiveBill(mint: mint, rendezvous: rendezvous) { c.resume(with: $0) }
        }
    }
}
