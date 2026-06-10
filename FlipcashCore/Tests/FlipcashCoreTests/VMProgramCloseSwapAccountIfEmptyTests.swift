//
//  VMProgramCloseSwapAccountIfEmptyTests.swift
//  FlipcashCore
//

import Foundation
import Testing
@testable import FlipcashCore

@Suite("VMProgram.CloseSwapAccountIfEmpty")
struct VMProgramCloseSwapAccountIfEmptyTests {

    private static func key(_ base58: String) -> PublicKey { try! PublicKey(base58: base58) }

    private static let vmAuthority = key("cash11ndAmdKFEnG2wrQQ5Zqvr1kN9htxxLyoPLYFUV")
    private static let vm          = key("JACkaKsm2Rd6TNJwH4UB7G6tHrWUATJPTgNNnRVsg4ip")
    private static let swapper     = key("admJSWL9vzQfoFm9HoLsgTHCK5G1SKzdsMJCdAtKXnN")
    private static let swapPda     = key("FGH6ZKtsd7kLE6ToxEyjBgVrQQefKF7XKLxNAoU56X2q")
    private static let swapAta     = key("6QffJbV83ZpSRGvmvba9agN8xfZ9PatHoYcBUXRnmoDr")
    private static let destination = key("FNdBL7w2pRxBoz349ygKdWfGvrzPN6Wjcqu9mmVXjmcx")

    private func makeInstance(bump: Byte) -> VMProgram.CloseSwapAccountIfEmpty {
        .init(
            vmAuthority: Self.vmAuthority,
            vm: Self.vm,
            swapper: Self.swapper,
            swapPda: Self.swapPda,
            swapAta: Self.swapAta,
            destination: Self.destination,
            bump: bump
        )
    }

    @Test("Opcode is 19 and data layout is opcode + bump")
    func encoding_dataLayout() {
        let data = makeInstance(bump: 253).encode()

        #expect(data.count == 2)
        #expect(data[0] == VMProgram.Command.closeSwapAccountIfEmpty.rawValue)
        #expect(data[1] == 253)
    }

    @Test("Round-trip encode/decode preserves every field")
    func roundTrip() throws {
        let original = makeInstance(bump: 253)
        let parsed = try VMProgram.CloseSwapAccountIfEmpty(instruction: original.instruction())
        #expect(parsed == original)
    }

    @Test("Truncated payload missing the bump byte throws payloadNotFound")
    func truncatedPayload_throwsPayloadNotFound() {
        let truncated = Instruction(
            program: VMProgram.address,
            accounts: [
                .writable(publicKey: Self.vmAuthority, signer: true),
                .writable(publicKey: Self.vm),
                .readonly(publicKey: Self.swapper),
                .readonly(publicKey: Self.swapPda),
                .writable(publicKey: Self.swapAta),
                .writable(publicKey: Self.destination),
                .readonly(publicKey: TokenProgram.address)
            ],
            data: Data([VMProgram.Command.closeSwapAccountIfEmpty.rawValue])
        )

        #expect(throws: CommandParseError.payloadNotFound) {
            try VMProgram.CloseSwapAccountIfEmpty(instruction: truncated)
        }
    }
}
