//
//  TokenController.swift
//  Code
//
//  Created by Brandon McAnsh on 11/25/25.
//

import Foundation
import Combine
import FlipcashCore

struct StoredToken: Identifiable, Sendable, Equatable, Hashable {
    let mint: PublicKey
    let name: String
    let imageURL: URL?
    
    var id: PublicKey { mint }
    
    init(mint: PublicKey, name: String, imageURL: URL?) {
        self.mint = mint
        self.name = name
        self.imageURL = imageURL
    }
}

/// Controller responsible for persisting and managing the last selected token/currency
@MainActor
final class TokenController: ObservableObject {
    
    let container: Container
    
    // MARK: - Properties
    
    /// The currently selected mint metadata
    @Published private(set) var selectedToken: StoredToken? {
        didSet {
            if let token = selectedToken {
                persistSelectedToken(token)
            }
        }
    }
    
    // MARK: - Initialization
    
    /// Initialize the controller with optional custom UserDefaults
    /// - Parameter userDefaults: The UserDefaults instance to use for persistence. Defaults to .standard
    init(container: Container) {
        self.container = container
        self.selectedToken = loadSelectedToken()
    }
    
    // MARK: - Public Methods
    
    /// Select a new mint and persist it
    /// - Parameter token: The token to save
    func selectToken(_ token: MintMetadata) {
        selectedToken = StoredToken(mint: token.address, name: token.name, imageURL: token.imageURL)
    }
    
    /// Select a balance and persist its mint
    /// - Parameter balance: The exchanged balance to select
    func selectBalance(_ balance: ExchangedBalance) {
        selectedToken = StoredToken(mint: balance.stored.mint, name: balance.stored.name, imageURL: balance.stored.imageURL)
    }
    
    /// Get the currently selected mint, or a default if none is selected
    /// - Parameter defaultMint: The default mint to return if none is selected. Defaults to USDC.
    /// - Returns: The selected mint or the default
    func getSelectedMint(default defaultMint: PublicKey = .usdc) -> PublicKey {
        selectedToken?.mint ?? defaultMint
    }
    
    /// Check if a given mint is currently selected
    /// - Parameter mint: The mint to check
    /// - Returns: True if the mint is selected
    func isSelected(_ mint: PublicKey) -> Bool {
        selectedToken?.mint == mint
    }
    
    /// Check if a given balance is currently selected
    /// - Parameter balance: The balance to check
    /// - Returns: True if the balance's mint is selected
    func isSelected(_ balance: ExchangedBalance) -> Bool {
        selectedToken?.mint == balance.stored.mint
    }
    
    /// Prepare for logout of current user
    func prepareForLogout() {
        selectedToken = nil
    }
    
    // MARK: - Private Methods
    
    private func persistSelectedToken(_ token: StoredToken) {
        LocalDefaults.storedTokenMint = token.mint.base58
        LocalDefaults.storedTokenName = token.name
        LocalDefaults.storedTokenImageURL = token.imageURL?.absoluteString
    }
    
    private func loadSelectedToken() -> StoredToken? {
        guard let mintString = LocalDefaults.storedTokenMint,
              let name = LocalDefaults.storedTokenName,
              let mint = try? PublicKey(base58: mintString) else {
            return nil
        }
        
        let imageURL: URL?
        if let urlString = LocalDefaults.storedTokenImageURL {
            imageURL = URL(string: urlString)
        } else {
            imageURL = nil
        }
        
        return StoredToken(mint: mint, name: name, imageURL: imageURL)
    }
}

private enum LocalDefaults {
    @Defaults(.storedTokenMint)
    static var storedTokenMint: String?
    
    @Defaults(.storedTokenName)
    static var storedTokenName: String?
    
    @Defaults(.storedTokenImageURL)
    static var storedTokenImageURL: String?
}

// MARK: - Convenience Extensions

extension TokenController {
    
    static let mock = TokenController(container: .mock)
    
    /// Check if a mint is currently selected
    var hasSelection: Bool {
        selectedToken != nil
    }
}
