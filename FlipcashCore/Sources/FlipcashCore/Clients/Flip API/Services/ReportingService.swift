//
//  ReportingService.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI
import GRPCCore

private let logger = Logger(label: "flipcash.reporting-service")

/// What a report names. See `reporting.v1.ReportRequest.target`.
public enum ReportTarget: Sendable {
    case user(UserID)
    case chat(ConversationID)
    case message(chatID: ConversationID, messageID: MessageID)
    case blob(BlobID)
}

extension ReportTarget {
    var proto: Flipcash_Reporting_V1_ReportRequest.OneOf_Target {
        switch self {
        case .user(let userID):
            return .userID(userID.proto)
        case .chat(let chatID):
            return .chatID(chatID.proto)
        case .message(let chatID, let messageID):
            return .message(.with {
                $0.chatID = chatID.proto
                $0.messageID = messageID.proto
            })
        case .blob(let blobID):
            return .blobID(.with { $0.value = blobID.data })
        }
    }
}

final class ReportingService: Sendable {

    private let service: Flipcash_Reporting_V1_Reporting.Client<AppTransport>

    init(client: GRPCClient<AppTransport>) {
        self.service = Flipcash_Reporting_V1_Reporting.Client(wrapping: client)
    }

    /// Files a report against a user, chat, message, or blob. Reports are advisory: filing one has
    /// no immediate client-visible effect and outcomes are never surfaced back to the reporter — a
    /// `.success` here means the report was filed, not that any action was taken. Reporting the same
    /// target more than once is a no-op that still returns `.ok`.
    func report(owner: KeyPair, target: ReportTarget, description: String?, completion: @Sendable @escaping (Result<Void, ErrorReport>) -> Void) {
        let request = Flipcash_Reporting_V1_ReportRequest.with {
            $0.target = target.proto
            if let description {
                $0.description_p = description
            }
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.report(request, options: .unaryDefault)
                let error = ErrorReport(rawValue: response.result.rawValue) ?? .unknown
                guard error == .ok else {
                    logger.error("Failed to file report")
                    await MainActor.run { completion(.failure(error)) }
                    return
                }
                await MainActor.run { completion(.success(())) }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }
}

// MARK: - Errors -

public enum ErrorReport: Int, Error {
    case ok
    case denied
    case notFound
    case unknown          = -1
    case transportFailure = -2
    case cancelled = -3
    case rejected = -4
}

extension ErrorReport: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .cancelled: .info
        case .denied, .notFound: .info
        case .unknown, .rejected: .error
        }
    }
}
