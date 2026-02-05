//
//  CurrencyInfoViewModel.swift
//  Code
//
//  Created by Claude on 2025-02-04.
//

import SwiftUI
import FlipcashCore

@MainActor
class CurrencyInfoViewModel: ObservableObject {

    enum LoadingState {
        case loading
        case loaded(StoredMintMetadata)
        case error(Error)
    }

    enum Error: Swift.Error {
        case mintNotFound
        case networkError
    }

    @Published private(set) var loadingState: LoadingState = .loading

    private var updateableMint: Updateable<StoredMintMetadata>?

    var mintMetadata: StoredMintMetadata? {
        switch loadingState {
        case .loaded(let metadata):
            return metadata
        case .loading, .error:
            return nil
        }
    }

    var isLoaded: Bool {
        if case .loaded = loadingState { return true }
        return false
    }

    private let mint: PublicKey
    private let session: Session
    private let database: Database

    init(mint: PublicKey, sessionContainer: SessionContainer) {
        self.mint = mint
        self.session = sessionContainer.session
        self.database = sessionContainer.database

        // Load from database immediately if available (fast path)
        if let cachedMetadata = try? database.getMintMetadata(mint: mint) {
            setupUpdateable(with: cachedMetadata)
            loadingState = .loaded(cachedMetadata)
        }
    }

    func loadMintMetadata() async {
        // If already loaded from cache, no need to show loading state
        let wasAlreadyLoaded = isLoaded

        do {
            let metadata = try await session.fetchMintMetadata(mint: mint)
            setupUpdateable(with: metadata)
            loadingState = .loaded(metadata)
        } catch Session.Error.mintNotFound {
            // Only show error if we didn't have cached data
            if !wasAlreadyLoaded {
                loadingState = .error(.mintNotFound)
            }
        } catch {
            // Only show error if we didn't have cached data
            if !wasAlreadyLoaded {
                loadingState = .error(.networkError)
            }
        }
    }

    private func setupUpdateable(with initialValue: StoredMintMetadata) {
        updateableMint = Updateable { [database, mint] in
            (try? database.getMintMetadata(mint: mint)) ?? initialValue
        } didSet: { [weak self] in
            guard let self, let updateable = self.updateableMint else { return }
            self.loadingState = .loaded(updateable.value)
        }
    }
}
