//
//  ChatListComposeRoute.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// Where the chat list's + goes.
enum ChatListComposeRoute {

    static func destination(showsGroupMoney: Bool) -> AppRouter.Destination {
        .newChat
    }
}
