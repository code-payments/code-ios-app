//
//  Client+Message.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import Combine

extension Client {
    
    public func openMessageStream(rendezvous: KeyPair, completion: @escaping (Result<PaymentRequest, Error>) -> Void) -> AnyCancellable {
        messagingService.openMessageStream(rendezvous: rendezvous, completion: completion)
    }
    
    public func fetchMessages(rendezvous: KeyPair) async throws -> [StreamMessage] {
        try await withCheckedThrowingContinuation { c in
            messagingService.fetchMessages(rendezvous: rendezvous) { c.resume(with: $0) }
        }
    }
    
    public func acknowledge(messages: [StreamMessage], rendezvous: PublicKey) async throws {
        try await withCheckedThrowingContinuation { c in
            messagingService.acknowledge(messages: messages, rendezvous: rendezvous) { c.resume(with: $0) }
        }
    }
    
    public func verifyRequestToGrabBill(destination: PublicKey, rendezvous: PublicKey, signature: Signature) -> Bool {
        messagingService.verifyRequestToGrabBill(destination: destination, rendezvous: rendezvous, signature: signature)
    }
    
    public func sendRequestToLogin(domain: Domain, verifier: KeyPair, rendezvous: KeyPair) async throws -> Bool {
        try await withCheckedThrowingContinuation { c in
            messagingService.sendRequestToLogin(domain: domain, verifier: verifier, rendezvous: rendezvous) { c.resume(with: $0) }
        }
    }
    
    public func sendRequestToGrabBill(destination: PublicKey, rendezvous: KeyPair) async throws -> Bool {
        try await withCheckedThrowingContinuation { c in
            messagingService.sendRequestToGrabBill(destination: destination, rendezvous: rendezvous) { c.resume(with: $0) }
        }
    }
    
    public func sendRequestToReceiveBill(destination: PublicKey, fiat: Fiat, rendezvous: KeyPair) async throws -> Bool {
        try await withCheckedThrowingContinuation { c in
            messagingService.sendRequestToReceiveBill(destination: destination, fiat: fiat, rendezvous: rendezvous) { c.resume(with: $0) }
        }
    }
    
    public func rejectLogin(rendezvous: KeyPair) async throws -> Bool {
        try await withCheckedThrowingContinuation { c in
            messagingService.rejectLogin(rendezvous: rendezvous) { c.resume(with: $0) }
        }
    }
    
    public func rejectPayment(rendezvous: KeyPair) async throws -> Bool {
        try await withCheckedThrowingContinuation { c in
            messagingService.rejectPayment(rendezvous: rendezvous) { c.resume(with: $0) }
        }
    }
    
    public func codeScanned(rendezvous: KeyPair) async throws -> Bool {
        try await withCheckedThrowingContinuation { c in
            messagingService.codeScanned(rendezvous: rendezvous) { c.resume(with: $0) }
        }
    }
}
