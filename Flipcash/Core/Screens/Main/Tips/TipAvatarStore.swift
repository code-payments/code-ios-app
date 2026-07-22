//
//  TipAvatarStore.swift
//  Flipcash
//

import Foundation
import FlipcashCore

private let logger = Logger(label: "flipcash.tip-avatars")

/// Session-scoped cache of tip counterparts' profile-picture thumbnails, as
/// raw bytes so every surface renders them through the same
/// `ContactAvatarView(imageData:)` path address-book avatars use.
@Observable
final class TipAvatarStore {

    private var dataByUser: [UserID: Data] = [:]

    @ObservationIgnored private var inFlight: Set<UserID> = []
    @ObservationIgnored private let flipClient: FlipClient
    @ObservationIgnored private let owner: KeyPair

    init(flipClient: FlipClient, owner: KeyPair) {
        self.flipClient = flipClient
        self.owner = owner
    }

    /// The cached thumbnail bytes for a user, or nil until ``load(userID:picture:)``
    /// has fetched them.
    func data(for userID: UserID?) -> Data? {
        userID.flatMap { dataByUser[$0] }
    }

    /// Fetches and caches the thumbnail for a member's current profile
    /// picture. No-ops when already cached, already fetching, or the member
    /// has no picture. Download URLs expire, so one is minted per fetch.
    func load(userID: UserID?, picture: ProfilePicture?) async {
        guard let userID,
              let blobID = picture?.thumbnailBlobID,
              dataByUser[userID] == nil,
              !inFlight.contains(userID) else { return }

        inFlight.insert(userID)
        defer { inFlight.remove(userID) }

        do {
            guard let url = try await flipClient.blobDownloadURL(
                blobID: blobID,
                owner: owner,
                accessContext: .profile(userID)
            ) else { return }

            let (data, _) = try await URLSession.shared.data(from: url)
            dataByUser[userID] = data
        } catch {
            guard !Task.isCancelled else { return }
            // The surfaces render the monogram placeholder without it.
            logger.info("Failed to load tip avatar", metadata: [
                "userId": "\(userID)",
                "error": "\(error)",
            ])
        }
    }
}
