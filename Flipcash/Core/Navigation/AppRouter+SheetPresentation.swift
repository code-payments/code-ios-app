//
//  AppRouter+SheetPresentation.swift
//  Flipcash
//
//  Created by Raul Riera on 2026-04-27.
//

import Foundation
import FlipcashCore

extension AppRouter {

    /// Identifies a top-level modal sheet. The router can present multiple at
    /// once — the bottom of the stack is the root sheet (overlays `ScanScreen`)
    /// and any subsequent entries are nested sheets that visually stack on top.
    nonisolated enum SheetPresentation: Identifiable, Hashable, Sendable, CustomStringConvertible {
        case balance
        case settings
        case give
        case discover
        case buy(PublicKey)
        case downloadApp
        case send
        /// A DM conversation as a root sheet — the chat is the bottom view.
        /// Entered via deeplink / push notification (`present(.conversation)`)
        /// so no recipient picker sits beneath it. The picker → chat flow keeps
        /// pushing `Destination.dmConversation` onto the `.send` stack instead.
        case conversation(ConversationContext)
        /// Send Cash amount entry, stacked on top of the chat via
        /// `presentNested(.sendAmount)`. Dismissing it reveals the chat.
        case sendAmount(ResolvedContact)

        var id: Self { self }

        /// The stack hosted inside this sheet. Inverse of `Stack.sheet`.
        /// Used by `dismissSheet` to clear the dismissed stack's path so a
        /// re-presentation starts at root rather than restoring the stale leaf.
        var stack: Stack {
            switch self {
            case .balance:      .balance
            case .settings:     .settings
            case .give:         .give
            case .discover:     .discover
            case .buy:          .buy
            case .downloadApp:  .downloadApp
            case .send:         .send
            case .conversation: .conversation
            case .sendAmount:   .sendAmount
            }
        }

        /// Whether presenting this sheet should reset its stack to root first. A conversation is
        /// always re-entered fresh — a deeplink/push should land on the chat, never on a leaf pushed
        /// onto its stack (a cash card's currency info). Every other root preserves its path so a
        /// swap-back or tab re-tap restores where the user was.
        var resetsStackOnPresent: Bool {
            switch self {
            case .conversation: true
            case .balance, .settings, .give, .discover, .buy, .downloadApp, .send, .sendAmount: false
            }
        }

        /// Payload-free case discriminator. Used by `presentNested` to detect
        /// "same case, different payload" (e.g. `.buy(A)` → `.buy(B)`) without
        /// comparing the stringly-typed `description`.
        var caseKind: CaseKind {
            switch self {
            case .balance:      .balance
            case .settings:     .settings
            case .give:         .give
            case .discover:     .discover
            case .buy:          .buy
            case .downloadApp:  .downloadApp
            case .send:         .send
            case .conversation: .conversation
            case .sendAmount:   .sendAmount
            }
        }

        enum CaseKind: Hashable, Sendable {
            case balance
            case settings
            case give
            case discover
            case buy
            case downloadApp
            case send
            case conversation
            case sendAmount
        }

        var description: String {
            switch self {
            case .balance:      "balance"
            case .settings:     "settings"
            case .give:         "give"
            case .discover:     "discover"
            case .buy:          "buy"
            case .downloadApp:  "downloadApp"
            case .send:         "send"
            case .conversation: "conversation"
            case .sendAmount:   "sendAmount"
            }
        }
    }
}
