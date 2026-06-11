//
//  Session+Purchases.swift
//  Flipcash
//

import Foundation
import FlipcashCore

private let logger = Logger(label: "flipcash.purchases")

extension Session {

    /// Buy, sell, and currency-launch RPC choreography, namespaced off
    /// ``Session`` as `session.purchases`. Owns no UI state — callers
    /// surface dialogs and navigation.
    final class Purchases {

        private unowned let session: Session
        private let client: Client
        private let owner: AccountCluster

        private var ownerKeyPair: KeyPair {
            owner.authority.keyPair
        }

        init(session: Session, client: Client, owner: AccountCluster) {
            self.session = session
            self.client = client
            self.owner = owner
        }

        // MARK: - Buy -

        @discardableResult
        func buy(amount: ExchangedFiat, verifiedState: VerifiedState, of mint: PublicKey) async throws -> SwapId {
            try session.assertFresh(verifiedState, operation: "buy", currency: amount.nativeAmount.currency, mint: amount.mint)

            let token = try await session.fetchMintMetadata(mint: mint)

            logger.info("buying", metadata: ["amount": "\(amount.nativeAmount.formatted())", "symbol": "\(token.symbol)"])

            return try await client.buy(amount: amount, verifiedState: verifiedState, of: token.metadata, owner: owner)
        }

        @discardableResult
        func buyWithExternalFunding(
            swapId: SwapId,
            amount: ExchangedFiat,
            of mint: PublicKey,
            transactionSignature: Signature
        ) async throws -> SwapId {
            let token = try await session.fetchMintMetadata(mint: mint)

            return try await client.buyWithExternalFunding(
                swapId: swapId,
                amount: amount,
                of: token.metadata,
                owner: owner,
                transactionSignature: transactionSignature
            )
        }

        @discardableResult
        func buyWithCoinbaseOnramp(
            amount: ExchangedFiat,
            of mint: PublicKey,
            orderId: String
        ) async throws -> SwapId {
            let token = try await session.fetchMintMetadata(mint: mint)
            let swapId = SwapId.generate()

            return try await client.buyWithCoinbaseOnramp(
                swapId: swapId,
                amount: amount,
                of: token.metadata,
                owner: owner,
                orderId: orderId
            )
        }

        // MARK: - Launch -

        @discardableResult
        func launchCurrency(
            name: String,
            description: String,
            billColors: [String],
            icon: Data,
            nameAttestation: ModerationAttestation,
            descriptionAttestation: ModerationAttestation,
            iconAttestation: ModerationAttestation
        ) async throws -> PublicKey {
            logger.info("Launching currency")

            let mint = try await client.launch(
                name: name,
                description: description,
                billColors: billColors,
                icon: icon,
                nameAttestation: nameAttestation,
                descriptionAttestation: descriptionAttestation,
                iconAttestation: iconAttestation,
                owner: ownerKeyPair
            )

            logger.info("Currency launched", metadata: ["mint": "\(mint.base58)"])
            return mint
        }

        @discardableResult
        func buyNewCurrency(
            amount: ExchangedFiat,
            feeAmount: ExchangedFiat,
            verifiedState: VerifiedState,
            mint: PublicKey,
            swapId: SwapId = .generate()
        ) async throws -> SwapId {
            try session.assertFresh(verifiedState, operation: "buyNewCurrency", currency: amount.nativeAmount.currency, mint: amount.mint)

            logger.info("Buying new currency", metadata: [
                "amount": "\(amount.nativeAmount.formatted())",
                "feeAmount": "\(feeAmount.nativeAmount.formatted())",
                "mint": "\(mint.base58)",
                "swapId": "\(swapId.publicKey.base58)"
            ])

            // Intentionally no fetchMintMetadata: a freshly-launched currency isn't
            // yet in the local DB, and in dry-run mode the server doesn't surface it
            // via fetchMints either. The new-currency swap path in SwapService skips
            // VM/launchpad metadata validation, and SwapInstructionBuilder derives
            // every account from the ReserveNewCurrencyServerParameter, so the mint
            // PublicKey is all we need.
            let metadata = try await client.buyNewCurrency(
                swapId: swapId,
                amount: amount,
                feeAmount: feeAmount,
                verifiedState: verifiedState,
                mint: mint,
                owner: owner
            )

            logger.info("New currency buy completed", metadata: [
                "swapId": "\(metadata.swapId.publicKey.base58)",
                "state": "\(metadata.state)"
            ])

            session.updatePostTransaction()
            return metadata.swapId
        }

        @discardableResult
        func buyNewCurrencyWithExternalFunding(
            amount: ExchangedFiat,
            feeAmount: ExchangedFiat,
            mint: PublicKey,
            transactionSignature: Signature
        ) async throws -> SwapId {
            logger.info("Buying new currency (external funding)", metadata: [
                "amount": "\(amount.nativeAmount.formatted())",
                "feeAmount": "\(feeAmount.nativeAmount.formatted())",
                "mint": "\(mint.base58)"
            ])

            let swapId = SwapId.generate()
            let metadata = try await client.buyNewCurrencyWithExternalFunding(
                swapId: swapId,
                amount: amount,
                feeAmount: feeAmount,
                mint: mint,
                owner: ownerKeyPair,
                transactionSignature: transactionSignature
            )

            logger.info("New currency buy (external) completed", metadata: [
                "swapId": "\(metadata.swapId.publicKey.base58)",
                "state": "\(metadata.state)"
            ])

            session.updatePostTransaction()
            return metadata.swapId
        }

        @discardableResult
        func buyNewCurrencyWithCoinbaseOnramp(
            amount: ExchangedFiat,
            feeAmount: ExchangedFiat,
            mint: PublicKey,
            orderId: String
        ) async throws -> SwapId {
            logger.info("Buying new currency (Coinbase onramp funding)", metadata: [
                "amount": "\(amount.nativeAmount.formatted())",
                "feeAmount": "\(feeAmount.nativeAmount.formatted())",
                "mint": "\(mint.base58)",
                "orderId": "\(orderId)"
            ])

            let swapId = SwapId.generate()
            let metadata = try await client.buyNewCurrencyWithCoinbaseOnramp(
                swapId: swapId,
                amount: amount,
                feeAmount: feeAmount,
                mint: mint,
                owner: ownerKeyPair,
                orderId: orderId
            )

            logger.info("New currency buy (Coinbase onramp) completed", metadata: [
                "swapId": "\(metadata.swapId.publicKey.base58)",
                "state": "\(metadata.state)"
            ])

            session.updatePostTransaction()
            return metadata.swapId
        }

        // MARK: - Sell -

        @discardableResult
        func sell(amount: ExchangedFiat, verifiedState: VerifiedState, in mint: PublicKey) async throws -> SwapId {
            try session.assertFresh(verifiedState, operation: "sell", currency: amount.nativeAmount.currency, mint: mint)

            let token = try await session.fetchMintMetadata(mint: mint)

            guard let supply = verifiedState.supplyFromBonding else {
                throw Error.missingSupply
            }

            // Cap to the on-chain balance when rounding pushed quarks above it.
            // compute(fromEntered:) already round-trips through compute(onChainAmount:)
            // for server consistency, so we only need to recompute when capping.
            let amountForIntent: ExchangedFiat
            if let balance = session.balance(for: mint),
               amount.onChainAmount.quarks > balance.quarks,
               mint != .usdf {
                logger.error("Sell workaround branch fired — pinning should have prevented this", metadata: [
                    "currency": "\(amount.nativeAmount.currency.rawValue)",
                    "mint": "\(mint.base58)",
                    "enteredQuarks": "\(amount.onChainAmount.quarks)",
                    "balanceQuarks": "\(balance.quarks)"
                ])
                // If the cap ever fires, the recompute MUST use the pinned rate
                // and supply — otherwise we replace one mismatch with another.
                amountForIntent = ExchangedFiat.compute(
                    onChainAmount: TokenAmount(quarks: balance.quarks, mint: mint),
                    rate: verifiedState.rate,
                    supplyQuarks: supply
                )
            } else {
                amountForIntent = amount
            }

            logger.info("selling", metadata: ["amount": "\(amountForIntent.nativeAmount.formatted())", "symbol": "\(token.symbol)"])

            return try await client.sell(amount: amountForIntent, verifiedState: verifiedState, in: token.metadata, owner: owner)
        }
    }
}
