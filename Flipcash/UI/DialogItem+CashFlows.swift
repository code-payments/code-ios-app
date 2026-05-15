//
//  DialogItem+CashFlows.swift
//  Code
//
//  Created by Raul Riera on 2026-04-29.
//

import FlipcashUI

extension DialogItem {

    static var somethingWentWrong: DialogItem {
        .init(
            style: .destructive,
            title: "Something Went Wrong",
            subtitle: "Please try again later",
            dismissable: true
        ) {
            .okay(kind: .destructive)
        }
    }

    static var cashReturned: DialogItem {
        .init(
            style: .destructive,
            title: "Something Went Wrong",
            subtitle: "The cash was returned to your wallet",
            dismissable: true
        ) {
            .okay(kind: .destructive)
        }
    }

    static var cashLinkNotAvailable: DialogItem {
        .init(
            style: .destructive,
            title: "Cash Already Collected",
            subtitle: "This cash has already been collected, or was cancelled by the sender",
            dismissable: true
        ) {
            .okay(kind: .destructive)
        }
    }

    static var cashLinkConnectionError: DialogItem {
        .init(
            style: .destructive,
            title: "Unable to Find Cash",
            subtitle: "Please check your connection and try again",
            dismissable: true
        ) {
            .okay(kind: .destructive)
        }
    }

    static func collectOwnCashConfirmation(
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void = {}
    ) -> DialogItem {
        .init(
            style: .destructive,
            title: "Collect Your Own Cash?",
            subtitle: "You tapped to collect the cash you sent. Are you sure you want to collect it yourself?",
            dismissable: false
        ) {
            .destructive("Collect", action: onConfirm);
            .subtle("Don't Collect", action: onCancel)
        }
    }

    static func noGiveableBalance(onDiscover: @escaping () -> Void) -> DialogItem {
        .init(
            style: .standard,
            title: "No Balance Yet",
            subtitle: "Buy a currency to get started, or get another Flipcash user to give you some cash",
            dismissable: true
        ) {
            .standard("Discover Currencies", action: onDiscover);
            .cancel()
        }
    }

    static var applePaySheetTimeout: DialogItem {
        .init(
            style: .standard,
            title: "Purchase Timed Out",
            subtitle: "Purchases must be authorized within 60 seconds",
            dismissable: true
        ) {
            .okay(kind: .standard)
        }
    }

    static var walletCancelled: DialogItem {
        .init(
            style: .destructive,
            title: "Transaction Cancelled",
            subtitle: "The transaction was cancelled in your wallet",
            dismissable: true
        ) {
            .okay(kind: .destructive)
        }
    }

    /// Coinbase Onramp rejects orders below `OnrampCoordinator.minimumPurchaseUSD`
    /// with a generic error; surface the constraint up-front instead of letting
    /// the user round-trip to Apple Pay. `minimum` is the USD floor already
    /// formatted in the user's selected display currency.
    static func applePayMinimumPurchase(minimum: String) -> DialogItem {
        .init(
            style: .destructive,
            title: "\(minimum) Minimum Purchase",
            subtitle: "Please enter an amount of \(minimum) or higher",
            dismissable: true
        ) {
            .okay(kind: .destructive)
        }
    }
}
