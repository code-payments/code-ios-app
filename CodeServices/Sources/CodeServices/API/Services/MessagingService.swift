//
//  MessagingService.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import CodeAPI
import Combine
import GRPC
import SwiftProtobuf

class MessagingService: CodeService<Code_Messaging_V1_MessagingNIOClient> {
    
//    typealias KeepAliveMessageStreamReference = BidirectionalStreamReference<Code_Messaging_V1_OpenMessageStreamWithKeepAliveRequest, Code_Messaging_V1_OpenMessageStreamWithKeepAliveResponse>
//    
//    func openKeepaliveMessageStream(completion: @escaping (Result<[StreamMessage], Error>) -> Void) -> AnyCancellable {
//        trace(.open, components: "Opening keepalive message stream.")
//        
//        let request = Code_Messaging_V1_OpenMessageStreamWithKeepAliveRequest.with {
//            $0.request = .with {
//                $0.rendezvousKey = rendezvous.publicKey.codeRendezvousKey
//                $0.signature = $0.sign(with: rendezvous)
//            }
//        }
//        
//        let streamReference = KeepAliveMessageStreamReference()
//        streamReference.retain()
//        
//        openKeepAliveMessageStream(
//            assigningTo: streamReference,
//            completion: completion
//        )
//        
//        return AnyCancellable {
//            streamReference.release()
//            streamReference.cancel()
//        }
//    }
//    
//    private func openKeepAliveMessageStream(assigningTo reference: KeepAliveMessageStreamReference, completion: @escaping (Result<[StreamMessage], Error>) -> Void) {
//        let queue = self.queue
//        let stream = service.openMessageStreamWithKeepAlive { response in
//            guard let result = response.responseOrPing else {
//                trace(.failure, components: "Server sent empty message. This is unexpected.")
//                return
//            }
//            
//            switch result {
//            case .response(let response):
//                
//                let messages = response.messages.compactMap { try? StreamMessage($0) }
//                queue.async {
//                    trace(.receive, components: "Received \(messages.count) messages.")
//                    completion(.success(messages))
//                }
//                
//            case .ping(let ping):
//                // TODO: Implement
//                break
//            }
//        }
//        
//        stream.status.whenCompleteBlocking(onto: queue) { [weak self, weak reference] result in
//            guard let self = self, let streamReference = reference else { return }
//            
//            if case .success(let status) = result, status.code == .unavailable {
//                // Reconnect only if the stream was closed as a result of
//                // server actions and not cancelled by the client, etc.
//                trace(.note, components: "Reconnecting keepalive stream...")
//                self.openKeepAliveMessageStream(
//                    assigningTo: streamReference,
//                    completion: completion
//                )
//            }
//        }
//        
//        reference.cancel()
//        reference.stream = stream
//    }
    
    func openMessageStream(rendezvous: KeyPair, completion: @escaping (Result<PaymentRequest, Error>) -> Void) -> AnyCancellable {
        trace(.open, components: "Rendezvous: \(rendezvous.publicKey.base58)")
        
        let request = Code_Messaging_V1_OpenMessageStreamRequest.with {
            $0.rendezvousKey = rendezvous.publicKey.codeRendezvousKey
            $0.signature = $0.sign(with: rendezvous)
        }
        
        let streamReference = StreamReference<Code_Messaging_V1_OpenMessageStreamRequest, Code_Messaging_V1_OpenMessageStreamResponse>()
        openMessageStream(assigningTo: streamReference, request: request, rendezvous: rendezvous.publicKey, completion: completion)
        
        return AnyCancellable {
            streamReference.cancel()
        }
    }
    
    private func openMessageStream(assigningTo reference: StreamReference<Code_Messaging_V1_OpenMessageStreamRequest, Code_Messaging_V1_OpenMessageStreamResponse>, request: Code_Messaging_V1_OpenMessageStreamRequest, rendezvous: PublicKey, completion: @escaping (Result<PaymentRequest, Error>) -> Void) {
        let queue = self.queue
        let stream = service.openMessageStream(request) { [weak self] response in
            
            let messages = response.messages.compactMap { try? StreamMessage($0) }
            
            // Cleans up the message reference on the server after we've received
            // the message. We only expect on message - receiver's public key.
            self?.acknowledge(messages: messages, rendezvous: rendezvous, completion: { _ in })
            
            let paymentRequests = response.messages.compactMap { try? StreamMessage($0).paymentRequest }
            
            queue.async {
                if let paymentRequest = paymentRequests.first {
                    var components = [
                        "Recipient: \(paymentRequest.account.base58)",
                        "Signature: \(paymentRequest.signature.base58)",
                    ]
                    components.append(contentsOf: response.messages.hexEncodedIDs.map { "Message ID: \($0)" })
                    trace(.receive, components: components)
                    completion(.success(paymentRequest))
                } else {
                    trace(.failure, components: "No accounts received.")
                    completion(.failure(MessagingError.failedToParsePaymentRequests))
                }
            }
        }
        
        stream.status.whenCompleteBlocking(onto: queue) { [weak self, weak reference] result in
            guard let self = self, let streamReference = reference else { return }
            
            if case .success(let status) = result, status.code == .unavailable {
                // Reconnect only if the stream was closed as a result of
                // server actions and not cancelled by the client, etc.
                trace(.note, components: "Reconnecting: \(rendezvous.base58)")
                self.openMessageStream(
                    assigningTo: streamReference,
                    request: request,
                    rendezvous: rendezvous,
                    completion: completion
                )
            }
        }
        
        reference.cancel()
        reference.stream = stream
    }
    
    func fetchMessages(rendezvous: KeyPair, completion: @escaping (Result<[StreamMessage], Error>) -> Void) {
        trace(.send, components: "Rendezvous: \(rendezvous.publicKey.base58)")
        
        let request = Code_Messaging_V1_PollMessagesRequest.with {
            $0.rendezvousKey = rendezvous.publicKey.codeRendezvousKey
            $0.signature = $0.sign(with: rendezvous)
        }
        
        let call = service.pollMessages(request)
        
        call.handle(on: queue) { response in
            let messages = response.messages.compactMap { try? StreamMessage($0) }
            trace(.success, components: "Fetched \(response.messages.count) messages.")
            completion(.success(messages))
            
        } failure: { error in
            completion(.failure(error))
        }
    }
    
    func acknowledge(messages: [StreamMessage], rendezvous: PublicKey, completion: @escaping (Result<Void, Error>) -> Void) {
        let ids = messages.map { $0.id }
        
        let stringsIDs = ids.map { "Message ID: \($0.data.hexEncodedString())" }
        trace(.send, components: stringsIDs)
        
        let request = Code_Messaging_V1_AckMessagesRequest.with {
            $0.rendezvousKey = rendezvous.codeRendezvousKey
            $0.messageIds = ids.map { id in
                Code_Messaging_V1_MessageId.with { $0.value = id.data }
            }
        }
        
        let call = service.ackMessages(request)
        call.handle(on: queue) { response in
            switch response.result {
            case .ok:
                trace(.success, components: stringsIDs)
                completion(.success(()))
                
            case .UNRECOGNIZED:
                trace(.failure, components: stringsIDs)
                completion(.failure(ErrorGeneric.unknown))
            }
            
        } failure: { error in
            completion(.failure(error))
        }
    }
    
    private func requestToGrabBill(destination: PublicKey) -> Code_Messaging_V1_Message {
        .with {
            $0.requestToGrabBill = .with {
                $0.requestorAccount = destination.codeAccountID
            }
        }
    }
    
    private func requestToLogin(domain: Domain, verifier: KeyPair, rendezvous: PublicKey) -> Code_Messaging_V1_Message {
        .with {
            $0.requestToLogin = .with {
                $0.domain = .with { $0.value = domain.relationshipHost }
                $0.rendezvousKey = rendezvous.codeRendezvousKey
                $0.verifier = verifier.publicKey.codeAccountID
                $0.signature = $0.sign(with: verifier)
            }
        }
    }
    
    func verifyRequestToGrabBill(destination: PublicKey, rendezvous: PublicKey, signature: Signature) -> Bool {
        let messageData = try! requestToGrabBill(destination: destination).serializedData()
        return rendezvous.verify(signature: signature, data: messageData)
    }
    
    func sendRequestToLogin(domain: Domain, verifier: KeyPair, rendezvous: KeyPair, completion: @escaping (Result<Bool, Error>) -> Void) {
        trace(.send, components:
            "Domain: \(domain.relationshipHost)",
            "Rendezvous: \(rendezvous.publicKey.base58)"
        )
        
        let message = requestToLogin(
            domain: domain,
            verifier: verifier,
            rendezvous: rendezvous.publicKey
        )
        
        sendRendezvousMessage(
            message: message,
            rendezvous: rendezvous,
            completion: completion
        )
    }
    
    func sendRequestToGrabBill(destination: PublicKey, rendezvous: KeyPair, completion: @escaping (Result<Bool, Error>) -> Void) {
        trace(.send, components:
            "Destination: \(destination.base58)",
            "Rendezvous: \(rendezvous.publicKey.base58)"
        )
        
        let message = requestToGrabBill(destination: destination)
        
        sendRendezvousMessage(
            message: message,
            rendezvous: rendezvous,
            completion: completion
        )
    }
    
    func sendRequestToReceiveBill(destination: PublicKey, fiat: Fiat, rendezvous: KeyPair, completion: @escaping (Result<Bool, Error>) -> Void) {
        trace(.send, components:
            "Destination: \(destination.base58)",
            "Rendezvous: \(rendezvous.publicKey.base58)"
        )
        
        let message: Code_Messaging_V1_Message = .with {
            $0.requestToReceiveBill = .with {
                $0.requestorAccount = destination.codeAccountID
                $0.exchangeData = .partial(.with {
                    $0.currency = fiat.currency.rawValue
                    $0.nativeAmount = fiat.amount.doubleValue
                })
            }
        }
        
        sendRendezvousMessage(
            message: message,
            rendezvous: rendezvous,
            completion: completion
        )
    }
    
    func rejectPayment(rendezvous: KeyPair, completion: @escaping (Result<Bool, Error>) -> Void) {
        trace(.send, components: "Rendezvous: \(rendezvous.publicKey.base58)")
        
        let message: Code_Messaging_V1_Message = .with {
            $0.clientRejectedPayment = .with {
                $0.intentID = rendezvous.publicKey.codeIntentID
            }
        }
        
        sendRendezvousMessage(
            message: message,
            rendezvous: rendezvous,
            completion: completion
        )
    }
    
    func rejectLogin(rendezvous: KeyPair, completion: @escaping (Result<Bool, Error>) -> Void) {
        trace(.send, components: "Rendezvous: \(rendezvous.publicKey.base58)")
        
        let message: Code_Messaging_V1_Message = .with {
            $0.clientRejectedLogin = .with {
                $0.timestamp = Google_Protobuf_Timestamp(date: .now())
            }
        }
        
        sendRendezvousMessage(
            message: message,
            rendezvous: rendezvous,
            completion: completion
        )
    }
    
    func codeScanned(rendezvous: KeyPair, completion: @escaping (Result<Bool, Error>) -> Void) {
        trace(.send, components: "Rendezvous: \(rendezvous.publicKey.base58)")
        
        let message: Code_Messaging_V1_Message = .with {
            $0.codeScanned = .with {
                $0.timestamp = Google_Protobuf_Timestamp(date: Date())
            }
        }
        
        sendRendezvousMessage(
            message: message,
            rendezvous: rendezvous,
            completion: completion
        )
    }
    
    private func sendRendezvousMessage(message: Code_Messaging_V1_Message, rendezvous: KeyPair, completion: @escaping (Result<Bool, Error>) -> Void) {
        let request = Code_Messaging_V1_SendMessageRequest.with {
            $0.message = message
            $0.rendezvousKey = rendezvous.publicKey.codeRendezvousKey
            $0.signature = Code_Common_V1_Signature.with {
                $0.value = rendezvous.sign(try! message.serializedData()).data
            }
        }
        
        let call = service.sendMessage(request)
        call.handle(on: queue) { response in
            let isStreamOpen: Bool
            switch response.result {
            case .ok:
                isStreamOpen = true
            case .noActiveStream:
                isStreamOpen = false
            default:
                isStreamOpen = false
            }
            trace(.success, components: response.messageID.hexEncoded, "Stream: \(isStreamOpen ? "Open" : "n/a")")
            completion(.success(isStreamOpen))
            
        } failure: { error in
            completion(.failure(error))
        }
    }
}

// MARK: - Error -

extension MessagingService {
    enum MessagingError: Error {
        case failedToParsePaymentRequests
    }
}

// MARK: - Interceptors -

extension InterceptorFactory: Code_Messaging_V1_MessagingClientInterceptorFactoryProtocol {
    func makePollMessagesInterceptors() -> [GRPC.ClientInterceptor<CodeAPI.Code_Messaging_V1_PollMessagesRequest, CodeAPI.Code_Messaging_V1_PollMessagesResponse>] {
        makeInterceptors()
    }
    
    func makeSendMessageInterceptors() -> [ClientInterceptor<Code_Messaging_V1_SendMessageRequest, Code_Messaging_V1_SendMessageResponse>] {
        makeInterceptors()
    }
    
    func makeAckMessagesInterceptors() -> [ClientInterceptor<Code_Messaging_V1_AckMessagesRequest, Code_Messaging_V1_AckMesssagesResponse>] {
        makeInterceptors()
    }
    
    func makeOpenMessageStreamInterceptors() -> [ClientInterceptor<Code_Messaging_V1_OpenMessageStreamRequest, Code_Messaging_V1_OpenMessageStreamResponse>] {
        makeInterceptors()
    }
    
    func makeOpenMessageStreamWithKeepAliveInterceptors() -> [GRPC.ClientInterceptor<CodeAPI.Code_Messaging_V1_OpenMessageStreamWithKeepAliveRequest, CodeAPI.Code_Messaging_V1_OpenMessageStreamWithKeepAliveResponse>] {
        makeInterceptors()
    }
}

// MARK: - GRPCClientType -

extension Code_Messaging_V1_MessagingNIOClient: GRPCClientType {
    init(channel: GRPCChannel) {
        self.init(channel: channel, defaultCallOptions: CallOptions(), interceptors: InterceptorFactory())
    }
}

// MARK: - Message IDs -

extension Code_Messaging_V1_MessageId {
    var hexEncoded: String {
        value.hexEncodedString()
    }
}

extension Array where Element == Code_Messaging_V1_Message {
    var hexEncodedIDs: [String] {
        map { $0.id.hexEncoded }
    }
}
