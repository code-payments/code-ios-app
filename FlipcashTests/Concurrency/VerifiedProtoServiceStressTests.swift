//
//  VerifiedProtoStoreStressTests.swift
//  FlipcashTests
//
//  Pre-strip baseline for the Swift 6 / `defaultIsolation = MainActor`
//  migration. `VerifiedProtoService` is the actor that caches verified rate
//  and reserve proofs delivered from gRPC stream callbacks; it must stay
//  consistent under concurrent reads + writes. With TSan and Main Thread
//  Checker both enabled on the test scheme, a real data race here will
//  surface as a TSan warning or actor-isolation assertion.
//

import Foundation
import Testing
import FlipcashCore
import FlipcashAPI
@testable import Flipcash

@Suite("VerifiedProtoService concurrent access", .timeLimit(.minutes(1)))
struct VerifiedProtoServiceStressTests {

    @Test("100 concurrent reads + writes maintain consistency")
    func concurrentReadsAndWrites_doNotCrash() async {
        let service = VerifiedProtoService(store: InMemoryVerifiedProtoStore())
        let codes = CurrencyCode.allCases

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                let currency = codes[i % codes.count]
                let mint = PublicKey.testMint(index: i)

                group.addTask {
                    let rate = Ocp_Currency_V1_VerifiedCoreMintFiatExchangeRate.freshRate(
                        currencyCode: currency.rawValue,
                        rate: 1.0 + Double(i) * 0.01
                    )
                    let reserve = Ocp_Currency_V1_VerifiedLaunchpadCurrencyReserveState.freshReserve(
                        mint: mint,
                        supplyFromBonding: UInt64(i)
                    )
                    await service.saveRates([rate])
                    await service.saveReserveStates([reserve])
                }
                group.addTask {
                    _ = await service.getVerifiedState(for: currency, mint: mint)
                    _ = await service.hasVerifiedRate(for: currency)
                    _ = await service.rate(for: currency)
                }
            }
        }

        // If we got here without TSan warnings or actor-isolation
        // assertions, the actor's isolation holds under the load that
        // mirrors what the live mint-data stream delivers.
    }

    @Test("Cancellation tears down cleanly")
    func cancellation_doesNotLeakOrCrash() async {
        let service = VerifiedProtoService(store: InMemoryVerifiedProtoStore())
        let mint = PublicKey.testMint(index: 0)
        let task = Task {
            for _ in 0..<1_000 {
                _ = await service.getVerifiedState(for: .usd, mint: mint)
            }
        }
        task.cancel()
        await task.value
    }
}
