//
//  File.swift
//  
//
//  Created by Dima Bart on 2022-08-03.
//

import Foundation

public struct AccountInfo: Equatable, Sendable {
    
    /// The account's derivation index for applicable account types. When this field
    /// doesn't apply, a zero value is provided.
    public var index: Int
    
    /// The type of token account, which infers its intended use.
    public var accountType: AccountType
    
    /// The token account's address
    public var address: PublicKey
    
    /// The owner of the token account, which can also be thought of as a parent
    /// account that links to one or more token accounts. This is provided when
    /// available.
    public var owner: PublicKey?
    
    /// The token account's authority, which has access to moving funds for the
    /// account. This can be the owner account under certain circumstances (eg.
    /// ATA, primary account). This is provided when available.
    public var authority: PublicKey?
    
    /// The source of truth for the balance calculation.
    public var balanceSource: BalanceSource
    
    /// The Kin balance in quarks, as observed by Code. This may not reflect the
    /// value on the blockchain and could be non-zero even if the account hasn't
    /// been created. Use balance_source to determine how this value was calculated.
    public var balance: Kin
    
    /// The state of the account as it pertains to Code's ability to manage funds.
    public var managementState: ManagementState
    
    /// The state of the account on the blockchain.
    public var blockchainState: BlockchainState
    
    /// Whether an account is claimed. This only applies to relevant account types
    /// (eg. REMOTE_SEND_GIFT_CARD).
    public var claimState: ClaimState
    
    /// For temporary incoming accounts only. Flag indicates whether client must
    /// actively try rotating it by issuing a ReceivePayments intent. In general,
    /// clients should wait as long as possible until this flag is true or requiring
    /// the funds to send their next payment.
    public var mustRotate: Bool
    
    /// For account types used as an intermediary for sending money between two
    /// users (eg. REMOTE_SEND_GIFT_CARD), this represents the original exchange
    /// data used to fund the account. Over time, this value will become stale:
    ///  1. Exchange rates will fluctuate, so the total fiat amount will differ.
    ///  2. External entities can deposit additional funds into the account, so
    ///     the balance, in quarks, may be greater than the original quark value.
    ///  3. The balance could have been received, so the total balance can show
    ///     as zero.
    public var originalKinAmount: KinAmount?
    
    /// The relationship with a third party that this account has established with.
    /// This only applies to relevant account types (eg. RELATIONSHIP).
    public var relationship: Relationship?
    
    // MARK: - Init -
    
    init(index: Int, accountType: AccountType, address: PublicKey, owner: PublicKey?, authority: PublicKey?, balanceSource: BalanceSource, balance: Kin, managementState: ManagementState, blockchainState: BlockchainState, claimState: ClaimState, mustRotate: Bool, originalKinAmount: KinAmount?, relationship: Relationship?) {
        self.index = index
        self.accountType = accountType
        self.address = address
        self.owner = owner
        self.authority = authority
        self.balanceSource = balanceSource
        self.balance = balance
        self.managementState = managementState
        self.blockchainState = blockchainState
        self.claimState = claimState
        self.mustRotate = mustRotate
        self.originalKinAmount = originalKinAmount
        self.relationship = relationship
    }
}

// MARK: - Extensions -

extension AccountInfo {
    /// An account is deemed unuseable in Code if the management
    /// state for said account is no longer `locked`. Some accounts may
    /// be allowed to operated in an 'unlocked' or another state
    var unuseable: Bool {
        if managementState == .none {
            // If the account is not managed
            // by Code, it is always useable
            return false
        } else {
            return managementState != .locked
        }
    }
}

// MARK: - ManagementState -

extension AccountInfo {
    public enum ManagementState: Int, CaseIterable, Sendable {
        /// The state of the account is unknown. This may be returned when the
        /// data source is unstable and a reliable state cannot be determined.
        case unknown
        
        /// Code does not maintain a management state and won't move funds for this
        /// account.
        case none
        
        /// The account is in the process of transitioning to the LOCKED state.
        case locking
        
        /// The account's funds are locked and Code has co-signing authority.
        case locked
        
        /// The account is in the process of transitioning to the UNLOCKED state.
        case unlocking
        
        /// The account's funds are unlocked and Code no longer has co-signing
        /// authority. The account must transition to the LOCKED state to have
        /// management capabilities.
        case unlocked
        
        /// The account is in the process of transitioning to the CLOSED state.
        case closing
        
        /// The account has been closed and doesn't exist on the blockchain.
        /// Subsequently, it also has a zero balance.
        case closed
    }
}

// MARK: - BlockchainState -

extension AccountInfo {
    public enum BlockchainState: Int, CaseIterable, Sendable {
        /// The state of the account is unknown. This may be returned when the
        /// data source is unstable and a reliable state cannot be determined.
        case unknown
        
        /// The account does not exist on the blockchain.
        case doesntExist
        
        /// The account is created and exists on the blockchain.
        case exists
    }
}

// MARK: - BalanceSource -

extension AccountInfo {
    public enum BalanceSource: Int, CaseIterable, Sendable {
        /// The account's balance could not be determined. This may be returned when
        /// the data source is unstable and a reliable balance cannot be determined.
        case unknown
        
        /// The account's balance was fetched directly from a finalized state on the
        /// blockchain.
        case blockchain
        
        /// The account's balance was calculated using cached values in Code. Accuracy
        /// is only guaranteed when management_state is LOCKED.
        case cache
    }
}

// MARK: - Claim State -

extension AccountInfo {
    public enum ClaimState: Int, CaseIterable, Sendable {
        /// could not be fetched by server.
        case unknown
        
        /// The account has not yet been claimed.
        case notClaimed
        
        /// The account is claimed. Attempting to claim it will fail.
        case claimed
        
        /// The account hasn't been claimed, but is expired. Funds will move
        /// back to the issuer. Attempting to claim it will fail.
        case expired
    }
}

// MARK: - Relationship -

extension AccountInfo {
    public struct Relationship: Equatable, Sendable {
        
        public let domain: Domain
        
        init?(domain: String) {
            guard let domain = Domain(domain) else {
                return nil
            }
            
            self.domain = domain
        }
    }
}
