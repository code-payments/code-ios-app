//
//  TokenController.swift
//  Code
//
//  Created by Brandon McAnsh on 11/25/25.
//

import Foundation
import Combine
import FlipcashCore

/// Controller responsible for persisting and managing the last selected token/currency
@MainActor
final class TokenController: ObservableObject {
    
    let container: Container
    let database: Database
    
    // MARK: - Properties
    
    /// The currently selected mint metadata
    @Published private(set) var selectedTokenMint: PublicKey? {
        didSet {
            if let mint = selectedTokenMint {
                persistSelectedTokenMint(mint)
            }
        }
    }
    
    // MARK: - Initialization
    
    /// Initialize the controller with optional custom UserDefaults
    /// - Parameter userDefaults: The UserDefaults instance to use for persistence. Defaults to .standard
    init(container: Container, database: Database) {
        self.container = container
        self.database = database
        self.selectedTokenMint = loadSelectedToken()
    }
    
    // MARK: - Public Methods
    
    /// Select a new mint and persist it
    /// - Parameter token: The token to save
    func selectToken(_ mint: PublicKey) {
        selectedTokenMint = mint
    }
    
    /// Get the currently selected token, or a default if none is selected
    /// - Parameter defaultMint: The default mint to return if none is selected. Defaults to USDC.
    /// - Returns: The selected token or the default
    func getSelectedToken(default defaultMint: PublicKey = .usdc) -> StoredMintMetadata? {
        let mint = selectedTokenMint ?? defaultMint
        
        return try! database.getMintMetadata(mint: mint)
    }
    
    /// Check if a given mint is currently selected
    /// - Parameter mint: The mint to check
    /// - Returns: True if the mint is selected
    func isSelected(_ mint: PublicKey) -> Bool {
        selectedTokenMint == mint
    }
    
    /// Prepare for logout of current user
    func prepareForLogout() {
        selectedTokenMint = nil
    }
    
    // MARK: - Private Methods
    
    private func persistSelectedTokenMint(_ mint: PublicKey) {
        LocalDefaults.storedTokenMint = mint.base58
    }
    
    private func loadSelectedToken() -> PublicKey? {
        guard let mintString = LocalDefaults.storedTokenMint,
              let mint = try? PublicKey(base58: mintString) else {
            return nil
        }
        
        return mint
    }
}

private enum LocalDefaults {
    @Defaults(.storedTokenMint)
    static var storedTokenMint: String?
}

// MARK: - Convenience Extensions

extension TokenController {
    
    static let mock = TokenController(container: .mock, database: .mock)
    
    /// Check if a mint is currently selected
    var hasSelection: Bool {
        selectedTokenMint != nil
    }
}
