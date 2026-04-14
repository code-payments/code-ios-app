//
//  VMProgram.InitializeVm.swift
//  FlipcashCore
//

import Foundation

extension VMProgram {

    /// Initializes a new VM for a given mint/authority/lock-duration tuple,
    /// creating the VM PDA and its omnibus token account. Used once per
    /// launchpad-currency launch to create the VM that will hold deposits of
    /// the newly-minted token.
    ///
    /// Account structure (mirrors code-payments/code-vm api/src/sdk.rs vm_init):
    /// 0. [WRITE, SIGNER] VM authority
    /// 1. [WRITE] VM PDA                  (seeds: ["code_vm", mint, authority, [lock_duration]])
    /// 2. [WRITE] Omnibus PDA             (seeds: ["code_vm", "vm_omnibus", vm])
    /// 3. []      Mint
    /// 4. []      SPL Token program
    /// 5. []      System program
    /// 6. []      Sysvar rent
    public struct InitializeVm: Equatable, Hashable, Codable {

        public let vmAuthority: PublicKey
        public let vm: PublicKey
        public let omnibus: PublicKey
        public let mint: PublicKey
        public let lockDuration: UInt8
        public let vmBump: UInt8
        public let vmOmnibusBump: UInt8

        public init(
            vmAuthority: PublicKey,
            vm: PublicKey,
            omnibus: PublicKey,
            mint: PublicKey,
            lockDuration: UInt8,
            vmBump: UInt8,
            vmOmnibusBump: UInt8
        ) {
            self.vmAuthority = vmAuthority
            self.vm = vm
            self.omnibus = omnibus
            self.mint = mint
            self.lockDuration = lockDuration
            self.vmBump = vmBump
            self.vmOmnibusBump = vmOmnibusBump
        }
    }
}

// MARK: - InstructionType -

extension VMProgram.InitializeVm: InstructionType {

    public init(instruction: Instruction) throws {
        let data = try VMProgram.parse(.initializeVm, instruction: instruction, expectingAccounts: 7)

        guard data.count >= 3 else {
            throw CommandParseError.payloadNotFound
        }

        let bytes = Array(data)

        self.init(
            vmAuthority: instruction.accounts[0].publicKey,
            vm: instruction.accounts[1].publicKey,
            omnibus: instruction.accounts[2].publicKey,
            mint: instruction.accounts[3].publicKey,
            lockDuration: bytes[0],
            vmBump: bytes[1],
            vmOmnibusBump: bytes[2]
        )
    }

    public func instruction() -> Instruction {
        Instruction(
            program: VMProgram.address,
            accounts: [
                .writable(publicKey: vmAuthority, signer: true),
                .writable(publicKey: vm),
                .writable(publicKey: omnibus),
                .readonly(publicKey: mint),
                .readonly(publicKey: TokenProgram.address),
                .readonly(publicKey: SystemProgram.address),
                .readonly(publicKey: SysVar.rent.address),
            ],
            data: encode()
        )
    }

    public func encode() -> Data {
        var data = Data()
        data.append(contentsOf: VMProgram.Command.initializeVm.rawValue.bytes)
        data.append(lockDuration)
        data.append(vmBump)
        data.append(vmOmnibusBump)
        return data
    }
}
