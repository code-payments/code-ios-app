//
//  TokenProgram.SetAuthority.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

extension TokenProgram {
    
    ///   Sets a new authority of a mint or account.
    ///
    ///   Accounts expected by this instruction:
    ///
    ///   * Single authority
    ///   0. `[writable]` The mint or account to change the authority of.
    ///   1. `[signer]` The current authority of the mint or account.
    ///
    ///   * Multisignature authority
    ///   0. `[writable]` The mint or account to change the authority of.
    ///   1. `[]` The mint's or account's multisignature authority.
    ///   2. ..2+M `[signer]` M signer accounts
    ///
    public struct SetAuthority: Equatable, Hashable, Codable {
        
        public var account: PublicKey
        public var authorityType: AuthorityType
        public var currentAuthority: PublicKey
        public var newAuthority: PublicKey?
        
        public init(account: PublicKey, authorityType: AuthorityType, currentAuthority: PublicKey, newAuthority: PublicKey?) {
            self.account = account
            self.authorityType = authorityType
            self.currentAuthority = currentAuthority
            self.newAuthority = newAuthority
        }
    }
}

extension TokenProgram.SetAuthority: InstructionType {
    
    public init(instruction: Instruction) throws {
        var data = try TokenProgram.parse(.setAuthority, instruction: instruction, expectingAccounts: 2)
        
        guard data.canConsume(1), let authorityType = TokenProgram.AuthorityType(rawValue: data.consume(1)[0]) else {
            throw ErrorGeneric.unknown
        }
        
        var newAuthority: PublicKey? = nil
        
        let isNulling = data.consume(1).first == 1
        if !isNulling {
            guard data.canConsume(PublicKey.length), let authority = PublicKey(data.consume(PublicKey.length)) else {
                throw ErrorGeneric.unknown
            }
            
            newAuthority = authority
        }
        
        self.init(
            account: instruction.accounts[0].publicKey,
            authorityType: authorityType,
            currentAuthority: instruction.accounts[1].publicKey,
            newAuthority: newAuthority
        )
    }
    
    public func instruction() -> Instruction {
        Instruction(
            program: TokenProgram.address,
            accounts: [
                .writable(publicKey: account),
                .readonly(publicKey: currentAuthority, signer: true),
            ],
            data: encode()
        )
    }
    
    public func encode() -> Data {
        var data = Data()
        
        data.append(TokenProgram.Command.setAuthority.rawValue)
        data.append(authorityType.rawValue)
        
        if let authority = newAuthority {
            data.append(1)
            data.append(contentsOf: authority.bytes)
        } else {
            data.append(0)
        }
        
        return data
    }
}
