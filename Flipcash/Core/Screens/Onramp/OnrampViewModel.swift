//
//  OnrampViewModel.swift
//  Code
//
//  Created by Dima Bart on 2025-08-11.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

private let logger = Logger(label: "flipcash.onramp")

/// Long-lived store for Onramp email verification deeplinks. `DeepLinkController`
/// drops incoming verifications here; `OnrampHostModifier` observes the value
/// with `.onChange(initial: true)` and hands it off to `OnrampCoordinator`, so
/// whether the link arrived before or after the sheet opened the verification
/// is picked up through the same entry point. Lives on `SessionContainer` so
/// it survives sheet dismissal but not logout.
@MainActor @Observable
final class OnrampDeeplinkInbox {
    var pendingEmailVerification: VerificationDescription?
}

@MainActor @Observable
class OnrampViewModel {

    var enteredAmount: String = ""

    var dialogItem: DialogItem?

    /// Display name forwarded to the onrampCoordinator when a buy is kicked off.
    let displayName: String

    var enteredFiat: ExchangedFiat? {
        guard !enteredAmount.isEmpty else {
            return nil
        }

        guard let amount = NumberFormatter.decimal(from: enteredAmount) else {
            return nil
        }

        guard let converted = try? Quarks(fiatDecimal: amount, currencyCode: .usd, decimals: PublicKey.usdf.mintDecimals) else {
            return nil
        }

        return try? ExchangedFiat(
            converted: converted,
            rate: .oneToOne,
            mint: .usdf
        )
    }

    @ObservationIgnored private let session: Session

    /// Target mint for the buy. Captured at init time by `forBuying`.
    @ObservationIgnored private let mint: PublicKey

    /// Coordinator that drives the Coinbase order and Apple Pay flow at root.
    /// The VM hands off the validated amount via `startBuy`; the onrampCoordinator
    /// publishes a `.buyProcessing` completion once the post-onramp swap is
    /// submitted.
    @ObservationIgnored private let onrampCoordinator: OnrampCoordinator
    @ObservationIgnored private let onUsdfReady: @MainActor @Sendable (Signature, ExchangedFiat) async throws -> SignedSwapResult

    // MARK: - Init -

    static func forBuying(
        mint: PublicKey,
        displayName: String,
        session: Session,
        onrampCoordinator: OnrampCoordinator,
        onUsdfReady: @escaping @MainActor @Sendable (Signature, ExchangedFiat) async throws -> SignedSwapResult
    ) -> OnrampViewModel {
        OnrampViewModel(
            displayName: displayName,
            mint: mint,
            session: session,
            onrampCoordinator: onrampCoordinator,
            onUsdfReady: onUsdfReady
        )
    }

    private init(
        displayName: String,
        mint: PublicKey,
        session: Session,
        onrampCoordinator: OnrampCoordinator,
        onUsdfReady: @escaping @MainActor @Sendable (Signature, ExchangedFiat) async throws -> SignedSwapResult
    ) {
        self.displayName = displayName
        self.mint = mint
        self.session = session
        self.onrampCoordinator = onrampCoordinator
        self.onUsdfReady = onUsdfReady
    }

    // MARK: - Actions -

    func customAmountEnteredAction() {
        guard let exchangedFiat = enteredFiat else {
            return
        }

        guard let maxPerDay = session.sendLimitFor(currency: exchangedFiat.converted.currencyCode)?.maxPerDay else {
            return
        }

        guard exchangedFiat.converted <= maxPerDay else {
            logger.info("Onramp rejected: amount exceeds limit", metadata: [
                "amount": "\(exchangedFiat.converted.formatted())",
                "max_per_day": "\(maxPerDay.decimalValue)",
                "currency": "\(exchangedFiat.converted.currencyCode)",
            ])
            showAmountTooLargeError()
            return
        }

        guard exchangedFiat.converted.decimalValue >= 5.00 else {
            showAmountTooSmallError()
            return
        }

        onrampCoordinator.startBuy(
            amount: exchangedFiat,
            mint: mint,
            displayName: displayName,
            onCompleted: onUsdfReady
        )
    }

    // MARK: - Dialog Factories -

    private func presentDestructiveDialog(
        title: String,
        subtitle: String,
        action: @escaping DialogAction.DialogActionHandler = {}
    ) {
        dialogItem = .init(
            style: .destructive,
            title: title,
            subtitle: subtitle,
            dismissable: true,
        ) {
            .okay(kind: .destructive, action: action)
        }
    }

    // MARK: - Errors -

    private func showAmountTooSmallError() {
        presentDestructiveDialog(
            title: "$5 Minimum Purchase",
            subtitle: "Please enter an amount of $5 or higher"
        )
    }

    private func showAmountTooLargeError() {
        presentDestructiveDialog(
            title: "Amount Too Large",
            subtitle: "Please enter a smaller amount"
        )
    }
}

// MARK: - Paths -

/// Navigation path for `VerifyInfoScreen`'s NavigationStack.
enum OnrampVerificationPath: Hashable {
    case info
    case enterPhoneNumber
    case confirmPhoneNumberCode
    case enterEmail
    case confirmEmailCode
}

// MARK: - Profile -

extension Profile {
    var canCreateCoinbaseOrder: Bool {
        phone != nil && email?.isEmpty == false
    }
}

// MARK: - OnrampError -

enum OnrampError: Error {
    case coinbaseOrderFailed(status: String)
    case coinbaseOrderPollTimeout
    case missingCoinbaseApiKey
}

