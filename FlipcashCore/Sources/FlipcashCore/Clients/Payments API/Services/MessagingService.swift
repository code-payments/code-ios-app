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
import GRPCCore
import SwiftProtobuf

private let logger = Logger(label: "flipcash.messaging-service")

final class MessagingService: Sendable {

    private let service: Ocp_Messaging_V1_Messaging.Client<AppTransport>

    init(client: GRPCClient<AppTransport>) {
        self.service = Ocp_Messaging_V1_Messaging.Client(wrapping: client)
    }

    func openMessageStream(rendezvous: KeyPair, completion: @MainActor @Sendable @escaping (Result<[StreamMessage], Error>) -> Void) -> AnyCancellable {
        logger.info("Opening message stream", metadata: ["rendezvous": "\(rendezvous.publicKey.base58)"])

        let request = Ocp_Messaging_V1_OpenMessageStreamRequest.with {
            $0.rendezvousKey = rendezvous.publicKey.codeRendezvousKey
            $0.signature = $0.sign(with: rendezvous)
        }

        let stream = ServerGRPCStream()
        openMessageStream(on: stream, request: request, rendezvous: rendezvous.publicKey, completion: completion)

        return AnyCancellable {
            stream.cancel()
        }
    }

    private func openMessageStream(on stream: ServerGRPCStream, request: Ocp_Messaging_V1_OpenMessageStreamRequest, rendezvous: PublicKey, completion: @MainActor @Sendable @escaping (Result<[StreamMessage], Error>) -> Void) {
        stream.open(onComplete: { [weak self] result in
            guard let self else { return }

            // Reconnect only if the stream was closed as a result of
            // server actions and not cancelled by the client, etc.
            if case .failure(let error) = result, let rpcError = error as? RPCError, rpcError.code == .unavailable {
                logger.debug("Reconnecting message stream", metadata: ["rendezvous": "\(rendezvous.base58)"])
                self.openMessageStream(
                    on: stream,
                    request: request,
                    rendezvous: rendezvous,
                    completion: completion
                )
            }
        }) {
            try await self.service.openMessageStream(request) { response in
                for try await message in response.messages {
                    let messages = message.messages.compactMap { try? StreamMessage($0) }

                    // Awaiting (not spawning a Task per batch) preserves batch
                    // ordering — v1 delivered batches through a serial queue.
                    await MainActor.run {
                        completion(.success(messages))
                    }
                }
            }
        }
    }

    func fetchMessages(rendezvous: KeyPair, completion: @Sendable @escaping (Result<[StreamMessage], Error>) -> Void) {
        logger.info("Fetching messages", metadata: ["rendezvous": "\(rendezvous.publicKey.base58)"])

        let request = Ocp_Messaging_V1_PollMessagesRequest.with {
            $0.rendezvousKey = rendezvous.publicKey.codeRendezvousKey
            $0.signature = $0.sign(with: rendezvous)
        }

        Task {
            do {
                let response = try await service.pollMessages(request, options: .unaryDefault)
                let messages = response.messages.compactMap { try? StreamMessage($0) }
                logger.info("Fetched messages", metadata: ["count": "\(response.messages.count)"])
                await MainActor.run {
                    completion(.success(messages))
                }
            } catch {
                await MainActor.run {
                    completion(.failure(error))
                }
            }
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

        Task {
            do {
                let response = try await service.ackMessages(request, options: .unaryDefault)
                switch response.result {
                case .ok:
                    logger.info("Messages acknowledged successfully")
                    await MainActor.run {
                        completion(.success(()))
                    }

                case .UNRECOGNIZED:
                    logger.error("Failed to acknowledge messages")
                    await MainActor.run {
                        completion(.failure(ErrorGeneric.unknown))
                    }
                }
            } catch {
                await MainActor.run {
                    completion(.failure(error))
                }
            }
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
                $0.quarks = exchangedFiat.onChainAmount.quarks
                $0.nativeAmount = exchangedFiat.nativeAmount.doubleValue
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

        Task {
            do {
                let response = try await service.sendMessage(request, options: .unaryDefault)
                let isStreamOpen: Bool
                switch response.result {
                case .ok:
                    isStreamOpen = true
                case .noActiveStream, .UNRECOGNIZED:
                    isStreamOpen = false
                }
                logger.info("Message sent", metadata: [
                    "messageId": "\(response.messageID.hexEncoded)",
                    "streamOpen": "\(isStreamOpen)"
                ])
                await MainActor.run {
                    completion(.success(isStreamOpen))
                }
            } catch {
                await MainActor.run {
                    completion(.failure(error))
                }
            }
        }
    }
}

// MARK: - Error -

extension MessagingService {
    enum MessagingError: Error {
        case failedToParsePaymentRequests
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
