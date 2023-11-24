//
//  TokenProgram.InitializeAccount.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

extension TokenProgram {
    
    ///   Initializes a new account to hold tokens.  If this account is associated with the native
    ///   mint then the token balance of the initialized account will be equal to the amount of SOL
    ///   in the account. If this account is associated with another mint, that mint must be
    ///   initialized before this command can succeed.
    ///
    ///   The `InitializeAccount` instruction requires no signers and MUST be included within
    ///   the same Transaction as the system program's `CreateInstruction` that creates the account
    ///   being initialized.  Otherwise another party can acquire ownership of the uninitialized account.
    ///
    ///   Accounts expected by this instruction:
    ///
    ///   0. `[writable]`  The account to initialize.
    ///   1. `[]` The mint this account will be associated with.
    ///   2. `[]` The new account's owner/multisignature.
    ///   3. `[]` Rent sysvar
    ///
    public struct InitializeAccount: Equatable, Hashable, Codable {
        
        public var account: PublicKey
        public var mint: PublicKey
        public var owner: PublicKey
        
        public init(account: PublicKey, mint: PublicKey, owner: PublicKey) {
            self.account = account
            self.mint = mint
            self.owner = owner
        }
    }
}

extension TokenProgram.InitializeAccount: InstructionType {
    
    public init(instruction: Instruction) throws {
        try TokenProgram.parse(.closeAccount, instruction: instruction, expectingAccounts: 4)
        
        self.init(
            account: instruction.accounts[0].publicKey,
            mint: instruction.accounts[1].publicKey,
            owner: instruction.accounts[2].publicKey
        )
    }
    
    public func instruction() -> Instruction {
        Instruction(
            program: TokenProgram.address,
            accounts: [
                .writable(publicKey: account, signer: true),
                .readonly(publicKey: mint),
                .readonly(publicKey: owner),
                .readonly(publicKey: SysVar.rent.address),
            ],
            data: encode()
        )
    }
    
    public func encode() -> Data {
        var data = Data()
        
        data.append(TokenProgram.Command.initializeAccount.rawValue)
        
        return data
    }
}
