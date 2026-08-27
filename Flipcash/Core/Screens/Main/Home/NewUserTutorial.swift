//
//  NewUserTutorial.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

/// A step in the wallet's new-user tutorial (Figma frame 8966:1516, ported from
/// Android's `TutorialItem`).
nonisolated enum TutorialItem: TutorialItemPresentable {
    case addMoney(isCompleted: Bool)
    case scanTipCard(isCompleted: Bool)

    var id: String { title }

    var isCompleted: Bool {
        switch self {
        case .addMoney(let done), .scanTipCard(let done): return done
        }
    }

    var title: String {
        switch self {
        case .addMoney:    return "Add Money"
        case .scanTipCard: return "Scan a Tip Card"
        }
    }

    var subtitle: String {
        switch self {
        case .addMoney:    return "Add money to your account"
        case .scanTipCard: return "Give your first tip"
        }
    }

    var icon: Image {
        switch self {
        case .addMoney:    return Image(systemName: "plus.circle")
        case .scanTipCard: return Image("NavScan")
        }
    }
}

/// Whether the wallet draws the new-user tutorial, and with which milestones
/// checked off.
///
/// Both milestones are reads of a *local* cache that starts empty on every fresh
/// login — switching accounts included — so neither can be trusted until the
/// history has been reconciled with the server at least once. Without that wait,
/// an established account signing in is greeted with the new-user tutorial for
/// as long as its history takes to arrive. Mirrors Android's
/// `WalletViewModel.State.isAwaitingActivity`.
struct NewUserTutorialState: Equatable {

    let hasAddedMoney: Bool
    let hasTipped: Bool
    let historySyncState: HistoryController.SyncState
    /// Whether the local history already holds activity. Stored rows short-circuit
    /// the wait: history that is already here is nothing to mistake for a new
    /// account.
    let hasStoredActivity: Bool

    var items: [TutorialItem] {
        [.addMoney(isCompleted: hasAddedMoney), .scanTipCard(isCompleted: hasTipped)]
    }

    var isComplete: Bool { hasAddedMoney && hasTipped }

    var isAwaitingHistory: Bool {
        historySyncState == .unknown && !hasStoredActivity
    }

    /// Withheld while the milestones are still unknown — the tutorial is never
    /// the thing the wallet guesses at.
    var isVisible: Bool { !isAwaitingHistory && !isComplete }
}
