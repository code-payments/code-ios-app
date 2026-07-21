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

    // MARK: - Setters -
    // Async-native, unlike `fetchProfile` above: a continuation over a detached
    // Task never propagates cancellation into the RPC.

    func setDisplayName(_ displayName: String, owner: KeyPair) async throws {
        var request = Flipcash_Profile_V1_SetDisplayNameRequest()
        request.displayName = displayName
        request.auth        = owner.authFor(message: request)

        do {
            let response = try await service.setDisplayName(request, options: .unaryDefault)

            switch response.result {
            case .ok:
                logger.info("Display name set")
            case .invalidDisplayName:
                throw ErrorProfile.invalidDisplayName
            case .denied:
                throw ErrorProfile.denied
            case .failedModerated:
                throw ErrorProfile.moderated(response.flaggedCategory)
            case .UNRECOGNIZED:
                throw ErrorProfile.unknown
            }
        } catch let error as ErrorProfile {
            throw error
        } catch {
            throw ErrorProfile.network(error)
        }
    }

    func setProfilePicture(blobID: BlobID, owner: KeyPair) async throws -> ProfilePicture {
        var request = Flipcash_Profile_V1_SetProfilePictureRequest()
        request.blobID = .with { $0.value = blobID.data }
        request.auth   = owner.authFor(message: request)

        do {
            let response = try await service.setProfilePicture(request, options: .unaryDefault)

            switch response.result {
            case .ok:
                guard let picture = ProfilePicture(response.profilePicture) else {
                    throw ErrorProfile.unknown
                }

                logger.info("Profile picture set", metadata: ["blobId": "\(blobID)"])
                return picture

            case .denied:
                throw ErrorProfile.denied
            case .blobNotFound:
                throw ErrorProfile.blobNotFound
            case .blobNotReady:
                throw ErrorProfile.blobNotReady
            case .blobRejected:
                throw ErrorProfile.blobRejected
            case .invalidBlob:
                throw ErrorProfile.invalidBlob
            case .UNRECOGNIZED:
                throw ErrorProfile.unknown
            }
        } catch let error as ErrorProfile {
            throw error
        } catch {
            throw ErrorProfile.network(error)
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

public enum ErrorProfile: Error, Sendable {
    case denied
    case invalidDisplayName
    case moderated(Flipcash_Moderation_V1_FlaggedCategory)
    case blobNotFound
    case blobNotReady
    case blobRejected
    case invalidBlob
    case unknown
    case network(Error)
}

extension ErrorProfile: ServerError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .denied, .invalidDisplayName, .moderated,
             .blobNotFound, .blobNotReady, .blobRejected, .invalidBlob:
            .info
        case .unknown:
            .error
        case .network(let error):
            (error as? ServerError)?.reportingLevel ?? .error
        }
    }
}
