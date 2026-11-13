//
//  ChatListComposeRoute.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// Where the chat list's + goes: the New Chat menu today, or straight to New Group in the Group
/// Money shell, whose Groups tab has no DMs or community chats to start (node 13729:462).
enum ChatListComposeRoute {

    static func destination(showsGroupMoney: Bool) -> AppRouter.Destination {
        showsGroupMoney ? .newPrivateGroup : .newChat
    }
}
