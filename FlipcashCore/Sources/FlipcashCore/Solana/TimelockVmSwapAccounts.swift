//
//  TimelockAccounts.swift
//  FlipcashCore
//
//  Created by Brandon McAnsh on 12/16/25.
//

public struct TimelockVmSwapAccounts: Equatable, Sendable {
    public let pda: ProgramDerivedAccount
    public let ata: ProgramDerivedAccount
    
    public init(pda: ProgramDerivedAccount, ata: ProgramDerivedAccount) {
        self.pda = pda
        self.ata = ata
    }
}

extension TimelockVmSwapAccounts {
    public init(with owner: PublicKey, mint: PublicKey, vm: VMMetadata) throws {
        
        guard let pda = PublicKey.deriveSwapAddress(
            owner: owner,
            mint: mint,
            timeAuthority: vm.authority,
            lockout: Byte(vm.lockDurationInDays)
        ) else {
            fatalError("Failed to derive PDA")
        }
        
        guard let ata = PublicKey.deriveAssociatedAccount(
            from: pda.publicKey,
            mint: mint
        ) else {
            fatalError("Failed to derive ATA")
        }
        
        self.init(pda: pda, ata: ata)
    }
}
