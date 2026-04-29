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
}
