//
//  MemoProgram.Memo.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

extension MemoProgram {
    
    ///   Send tokens from one accounts to another. Accounts expected by this instruction:
    ///
    ///   ## Single owner/delegate
    ///
    ///   0. `[writable]` The source account.
    ///   1. `[writable]` The destination account.
    ///   2. `[signer]` The source account's owner/delegate.
    ///
    ///   ## Multisignature owner/delegate
    ///
    ///   0. `[writable]` The source account.
    ///   1. `[writable]` The destination account.
    ///   2. `[]` The source account's multisignature owner/delegate.
    ///   3. ..3+M `[signer]` M signer accounts.
    ///
    ///   Reference:
    ///   https://github.com/solana-labs/solana-program-library/blob/b011698251981b5a12088acba18fad1d41c3719a/token/program/src/instruction.rs#L76-L91
    ///
    public struct Memo: Equatable, Hashable, Codable {
        
        public var data: Data
        
        public init(data: Data) {
            self.data = data
        }
    }
}

//extension MemoProgram.Memo {
//    
//    public var agoraMemo: AgoraMemo? {
//        try? AgoraMemo(data: data)
//    }
//    
//    public init(transferType: AgoraMemo.TransferType, kreIndex: UInt16) {
//        self.data = AgoraMemo(transferType: transferType, appIndex: kreIndex).encode()
//    }
//    
//    public init(tipAccount: TipAccount) {
//        let components = [
//            "tip",
//            tipAccount.platform,
//            tipAccount.username,
//        ]
//        
//        self.data = Data(components.joined(separator: ":").utf8)
//    }
//}

extension MemoProgram.Memo: InstructionType {
    
    public init(instruction: Instruction) throws {
        try MemoProgram.parse(instruction: instruction, expectingAccounts: 0)
        self.init(data: instruction.data)
    }
    
    public func instruction() -> Instruction {
        Instruction(
            program: MemoProgram.address,
            accounts: [],
            data: encode()
        )
    }
    
    public func encode() -> Data {
        data
    }
}
