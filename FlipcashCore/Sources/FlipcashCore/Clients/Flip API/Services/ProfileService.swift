//
//  ProfileService.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI
import GRPCCore

private let logger = Logger(label: "flipcash.profile-service")

final class ProfileService: Sendable {

    private let service: Flipcash_Profile_V1_Profile.Client<AppTransport>

    init(client: GRPCClient<AppTransport>) {
        self.service = Flipcash_Profile_V1_Profile.Client(wrapping: client)
    }

    func fetchProfile(userID: UserID, owner: KeyPair, completion: @Sendable @escaping (Result<Profile, Error>) -> Void) {
        logger.info("Fetching profile", metadata: ["userId": "\(userID)"])

        let request = Flipcash_Profile_V1_GetProfileRequest.with {
            $0.userID = .with { $0.value = userID.data }
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.getProfile(request, options: .unaryDefault)

                let error = ErrorFetchProfile(rawValue: response.result.rawValue) ?? .unknown
                if error == .ok {
                    logger.info("Profile fetched successfully")
                    do {
                        let profile = try Profile(response.userProfile)
                        await MainActor.run { completion(.success(profile)) }
                    } catch {
                        await MainActor.run { completion(.failure(error)) }
                    }

                } else if error == .notFound {
                    logger.info("Profile not found, returning empty profile")
                    await MainActor.run { completion(.success(.empty)) }

                } else {
                    logger.error("Failed to fetch profile", metadata: ["userId": "\(userID)"])
                    await MainActor.run { completion(.failure(error)) }
                }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(ErrorFetchProfile.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(ErrorFetchProfile.unknown)) }
            }
        }
    }
}

// MARK: - Errors -

public enum ErrorFetchProfile: Int, Error {
    case ok
    case notFound
    case unknown          = -1
    case transportFailure = -2
    case cancelled = -3
    case rejected = -4
}

extension ErrorFetchProfile: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .cancelled: .info
        case .notFound: .info
        case .unknown, .rejected: .error
        }
    }
}
