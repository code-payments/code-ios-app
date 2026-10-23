//
//  DialogItem+NewChat.swift
//  Flipcash
//

import FlipcashUI

extension DialogItem {

    /// Raised by Create a New Community Chat when the user holds no community currency to gate the
    /// chat on (node 12370:77242). Informational: buying a currency is the way past it.
    static func noCommunityCurrencies(onExplore: @escaping () -> Void) -> DialogItem {
        .info(
            title: "No Community Currencies",
            subtitle: "Buy a community currency to start or join community chats."
        ) {
            .standard("Explore Currencies", action: onExplore);
            .dismiss(kind: .subtle)
        }
    }
}
