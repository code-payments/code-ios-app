//
//  ProgramDerivedAccounts.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

public struct TimelockDerivedAccounts: Codable, Hashable, Equatable, Sendable {
    
    public static let lockoutInDays: Byte = 21
    public static let dataVersion: Byte = 3
    
    public let owner: PublicKey
    public let state: ProgramDerivedAccount
    public let vault: ProgramDerivedAccount
    
    public init(owner: PublicKey) {
        
        let state: ProgramDerivedAccount
        let vault: ProgramDerivedAccount
        
        state = PublicKey.deriveTimelockStateAccount(owner: owner, lockout: Self.lockoutInDays)!
        vault = PublicKey.deriveTimelockVaultAccount(stateAccount: state.publicKey, version: Self.dataVersion)!
        
        self.owner = owner
        self.state = state
        self.vault = vault
    }
}

public struct SplitterCommitmentAccounts: Codable, Hashable, Equatable {
    
    public let treasury: PublicKey
    public let destination: PublicKey
    public let recentRoot: Hash
    public let transcript: Hash
    
    public let state: ProgramDerivedAccount
    public let vault: ProgramDerivedAccount
    
    public init(treasury: PublicKey, destination: PublicKey, recentRoot: Hash, transcript: Hash, amount: Kin) {
        
        let state = PublicKey.deriveCommitmentStateAccount(
            treasury: treasury,
            recentRoot: recentRoot,
            transcript: transcript,
            destination: destination,
            amount: amount
        )!
        
        let vault = PublicKey.deriveCommitmentVaultAccount(
            treasury: treasury,
            commitmentState: state.publicKey
        )!
        
        self.treasury    = treasury
        self.destination = destination
        self.recentRoot  = recentRoot
        self.transcript  = transcript
        self.state       = state
        self.vault       = vault
    }
    
    public init(source: AccountCluster, destination: PublicKey, amount: Kin, treasury: PublicKey, recentRoot: Hash, intentID: PublicKey, actionID: Int) {
        let transcript = SplitterTranscript(
            intentID: intentID,
            actionID: actionID,
            amount: amount,
            source: source.vaultPublicKey,
            destination: destination
        )
        
        self.init(
            treasury: treasury,
            destination: destination,
            recentRoot: recentRoot,
            transcript: transcript.transcriptHash,
            amount: amount
        )
    }
}

public struct AssociatedTokenAccount: Codable, Hashable, Equatable, Sendable {
 
    public let owner: PublicKey
    public let ata: ProgramDerivedAccount
    
    init(owner: PublicKey, mint: PublicKey) {
        self.owner = owner
        self.ata = PublicKey.deriveAssociatedAccount(from: owner, mint: mint)!
    }
}

public struct PreSwapStateAccount: Codable, Hashable, Equatable {
 
    public let owner: PublicKey
    public let state: ProgramDerivedAccount
    
    public init(owner: PublicKey, source: PublicKey, destination: PublicKey, nonce: PublicKey) {
        self.owner = owner
        self.state = PublicKey.derivePreSwapState(
            source: source,
            destination: destination,
            nonce: nonce
        )!
    }
}

public struct SplitterTranscript: Codable, Hashable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    
    public let intentID: PublicKey
    public let actionID: Int
    public let amount: Kin
    public let source: PublicKey
    public let destination: PublicKey
    
    public var transcriptHash: Hash {
        Hash(SHA256.digest(description))!
    }
    
    public init(intentID: PublicKey, actionID: Int, amount: Kin, source: PublicKey, destination: PublicKey) {
        self.intentID = intentID
        self.actionID = actionID
        self.amount = amount
        self.source = source
        self.destination = destination
    }
    
    public var description: String {
        [
            "receipt[\(intentID.base58), \(actionID)]:",
            "transfer \(amount.quarks) quarks",
            "from \(source.base58) to \(destination.base58)",
        ].joined(separator: " ")
    }
    
    public var debugDescription: String {
        description
    }
}

public struct ProgramDerivedAccount: Codable, Hashable, Equatable, Sendable  {
    
    public let publicKey: PublicKey
    public let bump: Byte
    
    init(publicKey: PublicKey, bump: Byte) {
        self.publicKey = publicKey
        self.bump = bump
    }
}

// MARK: - Timelock Derivation -

extension PublicKey {
    public static func deriveTimelockStateAccount(owner: PublicKey, lockout: Byte) -> ProgramDerivedAccount? {
        findProgramAddress(
            program: TimelockProgram.address,
            seeds:
                Data("timelock_state".utf8),
                PublicKey.kinMint.data,
                PublicKey.timeAuthority.data,
                owner.data,
                lockout.bytes.data
        )
    }
    
    public static func deriveTimelockVaultAccount(stateAccount: PublicKey, version: Byte) -> ProgramDerivedAccount? {
        findProgramAddress(
            program: TimelockProgram.address,
            seeds:
                Data("timelock_vault".utf8),
                stateAccount.data,
                version.bytes.data
        )
    }
}

// MARK: - Commitment Derivation -

extension PublicKey {
    public static func deriveCommitmentStateAccount(treasury: PublicKey, recentRoot: Hash, transcript: Hash, destination: PublicKey, amount: Kin) -> ProgramDerivedAccount? {
        findProgramAddress(
            program: SplitterProgram.address,
            seeds:
                Data("commitment_state".utf8),
                treasury.data,
                recentRoot.data,
                transcript.data,
                destination.data,
                amount.quarks.bytes.data
        )
    }
    
    public static func deriveCommitmentVaultAccount(treasury: PublicKey, commitmentState: PublicKey) -> ProgramDerivedAccount? {
        findProgramAddress(
            program: SplitterProgram.address,
            seeds:
                Data("commitment_vault".utf8),
                treasury.data,
                commitmentState.data
        )
    }
}

// MARK: - PreSwap State -

extension PublicKey {
    public static func derivePreSwapState(source: PublicKey, destination: PublicKey, nonce: PublicKey) -> ProgramDerivedAccount? {
        findProgramAddress(
            program: SwapValidatorProgram.address,
            seeds:
                Data("pre_swap_state".utf8),
                source.data,
                destination.data,
                nonce.data
        )
    }
}

// MARK: - Associated Token Account Derivation -

extension PublicKey {
    
    private static let maxSeeds = 16
    
    public static func deriveAssociatedAccount(from owner: PublicKey, mint: PublicKey) -> ProgramDerivedAccount? {
        findProgramAddress(
            program: AssociatedTokenProgram.address,
            seeds: owner.data, TokenProgram.address.data, mint.data
        )
    }
    
    /// FindProgramAddress mirrors the implementation of the Solana SDK's FindProgramAddress. Its primary
    /// use case (for Kin and Agora) is for deriving associated accounts.
    ///
    /// Reference: https://github.com/solana-labs/solana/blob/5548e599fe4920b71766e0ad1d121755ce9c63d5/sdk/program/src/pubkey.rs#L234
    ///
    private static func findProgramAddress(program: PublicKey, seeds: Data...) -> ProgramDerivedAccount? {
        findProgramAddress(program: program, seeds: seeds)
    }
    
    private static func findProgramAddress(program: PublicKey, seeds: [Data]) -> ProgramDerivedAccount? {
        for i in 0...Byte.max {
            let bumpValue = Byte.max - i
            let bumpSeed = Data([bumpValue])
            if let publicKey = deriveProgramAddress(program: program, seeds: seeds + [bumpSeed]) {
                return ProgramDerivedAccount(
                    publicKey: publicKey,
                    bump: bumpValue
                )
            }
        }
        
        return nil
    }
    
    /// CreateProgramAddress mirrors the implementation of the Solana SDK's CreateProgramAddress.
    ///
    /// ProgramAddresses are public keys that _do not_ lie on the ed25519 curve to ensure that
    /// there is no associated private key. In the event that the program and seed parameters
    /// result in a valid public key, ErrInvalidPublicKey is returned.
    ///
    /// Reference: https://github.com/solana-labs/solana/blob/5548e599fe4920b71766e0ad1d121755ce9c63d5/sdk/program/src/pubkey.rs#L158
    ///
    static func deriveProgramAddress(program: PublicKey, seeds: [Data]) -> PublicKey? {
        if seeds.count > maxSeeds {
            return nil
        }
        
        var digest = SHA256()
        
        seeds.forEach { seed in
            digest.update(seed)
        }
        
        digest.update(program.data)
        digest.update("ProgramDerivedAddress")
        
        let publicKey = PublicKey(digest.digestBytes())!
        
        // Following the Solana SDK, we want to _reject_ the generated public key
        // if it's a valid compressed EdwardsPoint (on the curve).
        //
        // Reference: https://github.com/solana-labs/solana/blob/5548e599fe4920b71766e0ad1d121755ce9c63d5/sdk/program/src/pubkey.rs#L182-L187
        guard !publicKey.isOnCurve() else {
            return nil
        }
        
        return publicKey
    }
}
