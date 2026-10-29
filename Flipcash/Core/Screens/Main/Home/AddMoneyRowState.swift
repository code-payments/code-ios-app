//
//  AddMoneyRowState.swift
//  Flipcash
//

/// Whether the wallet draws its Add Money row.
///
/// `hasAddedMoney` reads a *local* cache that starts empty on every fresh login —
/// switching accounts included — so it cannot be trusted until the history has
/// been reconciled with the server at least once. Without that wait, an
/// established account signing in is greeted with the row for as long as its
/// history takes to arrive. Mirrors Android's `WalletViewModel.State.isAwaitingActivity`.
struct AddMoneyRowState: Equatable {

    let hasAddedMoney: Bool
    let historySyncState: HistoryController.SyncState
    /// Whether the local history already holds activity. Stored rows short-circuit
    /// the wait: history that is already here is nothing to mistake for a new
    /// account.
    let hasStoredActivity: Bool

    var isAwaitingHistory: Bool {
        historySyncState == .unknown && !hasStoredActivity
    }

    /// Withheld while `hasAddedMoney` is still unknown — the row is never the
    /// thing the wallet guesses at.
    var isVisible: Bool { !isAwaitingHistory && !hasAddedMoney }
}
