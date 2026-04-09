//
//  MessagingService.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI
import Combine
import GRPC
import SwiftProtobuf

private let logger = Logger(label: "flipcash.messaging-service")

class MessagingService: CodeService<Ocp_Messaging_V1_MessagingNIOClient> {
    
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
    
    func openMessageStream(rendezvous: KeyPair, completion: @MainActor @Sendable @escaping (Result<[StreamMessage], Error>) -> Void) -> AnyCancellable {
        logger.info("Opening message stream", metadata: ["rendezvous": "\(rendezvous.publicKey.base58)"])
        
        let request = Ocp_Messaging_V1_OpenMessageStreamRequest.with {
            $0.rendezvousKey = rendezvous.publicKey.codeRendezvousKey
            $0.signature = $0.sign(with: rendezvous)
        }
        
        let streamReference = StreamReference<Ocp_Messaging_V1_OpenMessageStreamRequest, Ocp_Messaging_V1_OpenMessageStreamResponse>()
        openMessageStream(assigningTo: streamReference, request: request, rendezvous: rendezvous.publicKey, completion: completion)
        
        return AnyCancellable {
            streamReference.cancel()
        }
    }
    
    private func openMessageStream(assigningTo reference: StreamReference<Ocp_Messaging_V1_OpenMessageStreamRequest, Ocp_Messaging_V1_OpenMessageStreamResponse>, request: Ocp_Messaging_V1_OpenMessageStreamRequest, rendezvous: PublicKey, completion: @MainActor @Sendable @escaping (Result<[StreamMessage], Error>) -> Void) {
        let queue = self.queue
        let stream = service.openMessageStream(request, callOptions: .streaming) { response in
            let messages = response.messages.compactMap { try? StreamMessage($0) }
                        
            Task { @MainActor in
                completion(.success(messages))
            }
        }
        
        stream.status.whenCompleteBlocking(onto: queue) { [weak self, weak reference] result in
            guard let self = self, let streamReference = reference else { return }
            
            if case .success(let status) = result, status.code == .unavailable {
                // Reconnect only if the stream was closed as a result of
                // server actions and not cancelled by the client, etc.
                logger.debug("Reconnecting message stream", metadata: ["rendezvous": "\(rendezvous.base58)"])
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
    
    func fetchMessages(rendezvous: KeyPair, completion: @Sendable @escaping (Result<[StreamMessage], Error>) -> Void) {
        logger.info("Fetching messages", metadata: ["rendezvous": "\(rendezvous.publicKey.base58)"])

        let request = Ocp_Messaging_V1_PollMessagesRequest.with {
            $0.rendezvousKey = rendezvous.publicKey.codeRendezvousKey
            $0.signature = $0.sign(with: rendezvous)
        }

        let call = service.pollMessages(request)

        call.handle(on: queue) { response in
            let messages = response.messages.compactMap { try? StreamMessage($0) }
            logger.info("Fetched messages", metadata: ["count": "\(response.messages.count)"])
            completion(.success(messages))
            
        } failure: { error in
            completion(.failure(error))
        }
    }
    
    func acknowledge(messages: [StreamMessage], rendezvous: PublicKey, completion: @Sendable @escaping (Result<Void, Error>) -> Void) {
        let ids = messages.map { $0.id }

        logger.info("Acknowledging messages", metadata: ["count": "\(ids.count)"])

        let request = Ocp_Messaging_V1_AckMessagesRequest.with {
            $0.rendezvousKey = rendezvous.codeRendezvousKey
            $0.messageIds = ids.map { id in
                Ocp_Messaging_V1_MessageId.with { $0.value = id.data }
            }
        }

        let call = service.ackMessages(request)
        call.handle(on: queue) { response in
            switch response.result {
            case .ok:
                logger.info("Messages acknowledged successfully")
                completion(.success(()))

            case .UNRECOGNIZED:
                logger.error("Failed to acknowledge messages")
                completion(.failure(ErrorGeneric.unknown))
            }
            
        } failure: { error in
            completion(.failure(error))
        }
    }
    
    private func requestToGrabBill(destination: PublicKey) -> Ocp_Messaging_V1_Message {
        .with {
            $0.requestToGrabBill = .with {
                $0.requestorAccount = destination.solanaAccountID
            }
        }
    }
    
    private func requestToGiveBill(mint: PublicKey, exchangeData: Ocp_Transaction_V1_VerifiedExchangeData?) -> Ocp_Messaging_V1_Message {
        .with {
            $0.requestToGiveBill = .with {
                $0.mint = mint.solanaAccountID
                if let exchangeData {
                    $0.exchangeData = exchangeData
                }
            }
        }
    }
    
    func verifyRequestToGrabBill(destination: PublicKey, rendezvous: PublicKey, signature: Signature) -> Bool {
        let messageData = try! requestToGrabBill(destination: destination).serializedData()
        return rendezvous.verify(signature: signature, data: messageData)
    }
    
    func sendRequestToGrabBill(destination: PublicKey, rendezvous: KeyPair, completion: @Sendable @escaping (Result<Bool, Error>) -> Void) {
        logger.info("Sending request to grab bill", metadata: [
            "destination": "\(destination.base58)",
            "rendezvous": "\(rendezvous.publicKey.base58)"
        ])
        
        let message = requestToGrabBill(destination: destination)
        
        sendRendezvousMessage(
            message: message,
            rendezvous: rendezvous,
            completion: completion
        )
    }
    
    func sendRequestToGiveBill(mint: PublicKey, exchangedFiat: ExchangedFiat, verifiedState: VerifiedState?, rendezvous: KeyPair, completion: @Sendable @escaping (Result<Bool, Error>) -> Void) {
        logger.info("Sending request to give bill", metadata: [
            "mint": "\(mint.base58)",
            "rendezvous": "\(rendezvous.publicKey.base58)"
        ])

        var exchangeData: Ocp_Transaction_V1_VerifiedExchangeData?
        if let verifiedState {
            exchangeData = Ocp_Transaction_V1_VerifiedExchangeData.with {
                $0.mint = exchangedFiat.mint.solanaAccountID
                $0.quarks = exchangedFiat.underlying.quarks
                $0.nativeAmount = exchangedFiat.converted.doubleValue
                $0.coreMintFiatExchangeRate = verifiedState.rateProto
                if let reserveProto = verifiedState.reserveProto {
                    $0.launchpadCurrencyReserveState = reserveProto
                }
            }
        }

        let message = requestToGiveBill(mint: mint, exchangeData: exchangeData)

        sendRendezvousMessage(
            message: message,
            rendezvous: rendezvous,
            completion: completion
        )
    }
    
    private func sendRendezvousMessage(message: Ocp_Messaging_V1_Message, rendezvous: KeyPair, completion: @Sendable @escaping (Result<Bool, Error>) -> Void) {
        let request = Ocp_Messaging_V1_SendMessageRequest.with {
            $0.message = message
            $0.rendezvousKey = rendezvous.publicKey.codeRendezvousKey
            $0.signature = Ocp_Common_V1_Signature.with {
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
            logger.info("Message sent", metadata: [
                "messageId": "\(response.messageID.hexEncoded)",
                "streamOpen": "\(isStreamOpen)"
            ])
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

extension InterceptorFactory: Ocp_Messaging_V1_MessagingClientInterceptorFactoryProtocol {
    func makeOpenMessageStreamWithKeepAliveInterceptors() -> [GRPC.ClientInterceptor<FlipcashAPI.Ocp_Messaging_V1_OpenMessageStreamWithKeepAliveRequest, FlipcashAPI.Ocp_Messaging_V1_OpenMessageStreamWithKeepAliveResponse>] {
        makeInterceptors()
    }
    
    func makePollMessagesInterceptors() -> [GRPC.ClientInterceptor<FlipcashAPI.Ocp_Messaging_V1_PollMessagesRequest, FlipcashAPI.Ocp_Messaging_V1_PollMessagesResponse>] {
        makeInterceptors()
    }
    
    func makeSendMessageInterceptors() -> [ClientInterceptor<Ocp_Messaging_V1_SendMessageRequest, Ocp_Messaging_V1_SendMessageResponse>] {
        makeInterceptors()
    }
    
    func makeAckMessagesInterceptors() -> [ClientInterceptor<Ocp_Messaging_V1_AckMessagesRequest, Ocp_Messaging_V1_AckMesssagesResponse>] {
        makeInterceptors()
    }
    
    func makeOpenMessageStreamInterceptors() -> [ClientInterceptor<Ocp_Messaging_V1_OpenMessageStreamRequest, Ocp_Messaging_V1_OpenMessageStreamResponse>] {
        makeInterceptors()
    }
}

// MARK: - GRPCClientType -

extension Ocp_Messaging_V1_MessagingNIOClient: GRPCClientType {
    init(channel: GRPCChannel) {
        self.init(channel: channel, defaultCallOptions: .default, interceptors: InterceptorFactory())
    }
}

// MARK: - Message IDs -

extension Ocp_Messaging_V1_MessageId {
    var hexEncoded: String {
        value.hexEncodedString()
    }
}

extension Array where Element == Ocp_Messaging_V1_Message {
    var hexEncodedIDs: [String] {
        map { $0.id.hexEncoded }
    }
}
