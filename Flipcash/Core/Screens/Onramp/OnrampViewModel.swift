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
@Observable
final class OnrampDeeplinkInbox {
    var pendingEmailVerification: VerificationDescription?
}

@Observable
class OnrampViewModel {

    var enteredAmount: String = ""

    var dialogItem: DialogItem?

    let displayName: String

    var enteredFiat: ExchangedFiat? {
        guard !enteredAmount.isEmpty else {
            return nil
        }

        guard let amount = NumberFormatter.decimal(from: enteredAmount) else {
            return nil
        }

        return ExchangedFiat(
            nativeAmount: FiatAmount(value: amount, currency: .usd),
            rate: .oneToOne
        )
    }

    @ObservationIgnored private let session: Session
    @ObservationIgnored private let mint: PublicKey
    @ObservationIgnored private let onrampCoordinator: OnrampCoordinator

    // MARK: - Init -

    static func forBuying(
        mint: PublicKey,
        displayName: String,
        session: Session,
        onrampCoordinator: OnrampCoordinator
    ) -> OnrampViewModel {
        OnrampViewModel(
            displayName: displayName,
            mint: mint,
            session: session,
            onrampCoordinator: onrampCoordinator
        )
    }

    private init(
        displayName: String,
        mint: PublicKey,
        session: Session,
        onrampCoordinator: OnrampCoordinator
    ) {
        self.displayName = displayName
        self.mint = mint
        self.session = session
        self.onrampCoordinator = onrampCoordinator
    }

    // MARK: - Actions -

    func customAmountEnteredAction() {
        guard let exchangedFiat = enteredFiat else {
            return
        }

        guard let maxPerDay = session.sendLimitFor(currency: exchangedFiat.nativeAmount.currency)?.maxPerDay else {
            return
        }

        guard exchangedFiat.nativeAmount.value <= maxPerDay.value else {
            logger.info("Onramp rejected: amount exceeds limit", metadata: [
                "amount": "\(exchangedFiat.nativeAmount.formatted())",
                "max_per_day": "\(maxPerDay.value)",
                "currency": "\(exchangedFiat.nativeAmount.currency)",
            ])
            showAmountTooLargeError()
            return
        }

        guard exchangedFiat.nativeAmount.value >= 5.00 else {
            showAmountTooSmallError()
            return
        }

        onrampCoordinator.start(
            .buy(mint: mint, displayName: displayName),
            amount: exchangedFiat
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
    case missingCoinbaseApiKey
}

