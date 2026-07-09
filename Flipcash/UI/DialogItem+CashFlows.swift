//
//  DialogItem+CashFlows.swift
//  Code
//
//  Created by Raul Riera on 2026-04-29.
//

import FlipcashUI

extension DialogItem {

    /// First-scan nudge surfaced once when a user's initial contact sync finds
    /// people they already know on Flipcash. `count` is the number of their
    /// contacts the server matched.
    static func contactsOnFlipcash(count: Int) -> DialogItem {
        .info(
            title: "\(count) \(count == 1 ? "Contact" : "Contacts") Already On Flipcash",
            subtitle: "Send them money, or invite other contacts to sign up for Flipcash"
        )
    }

    /// "No Balance Yet" prompt nudging the user into the Add Money flow.
    static func noBalance(subtitle: String, onAddMoney: @escaping () -> Void) -> DialogItem {
        .info(
            title: "No Balance Yet",
            subtitle: subtitle
        ) {
            .standard("Add Money", action: onAddMoney);
            .cancel()
        }
    }

    /// Nudges the user toward Discover when they hold USDF but no community
    /// currency to give.
    static func noCommunityCurrencies(onDiscover: @escaping () -> Void) -> DialogItem {
        .info(
            title: "No Community Currencies Yet",
            subtitle: "Discover and buy a currency, or create your own"
        ) {
            .standard("Discover Currencies", action: onDiscover);
            .cancel()
        }
    }
}

extension GiveCashGate {
    /// The blocking dialog for this gate outcome, or `nil` to proceed into
    /// the flow.
    @MainActor
    func blockingDialog(router: AppRouter) -> DialogItem? {
        switch self {
        case .proceed:
            nil
        case .discoverCurrencies:
            .noCommunityCurrencies { router.present(.discover) }
        case .addMoney:
            .noBalance(subtitle: AddMoneyContext.giveCash.noBalanceSubtitle) {
                router.presentAddMoney(.giveCash)
            }
        }
    }
}
