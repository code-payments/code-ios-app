//
//  ActivityHistoryScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// The unified, cross-token activity history — the "dive in" from the Wallet's
/// Recent section. Lists every activity (newest first) with the same enriched
/// rows as the wallet preview. Rows are non-interactive; the per-token
/// ``TransactionHistoryScreen`` remains the place to cancel a pending cash link.
struct ActivityHistoryScreen: View {

    @Environment(SessionContainer.self) private var sessionContainer
    @Environment(HistoryController.self) private var historyController

    var body: some View {
        ActivityHistoryContent(session: sessionContainer.session, historyController: historyController)
    }
}

private struct ActivityHistoryContent: View {

    private let session: Session
    private let historyController: HistoryController

    /// The full local history. The server sync pages the complete set into the
    /// local DB, so this cap matches the per-token history's own 1024 ceiling.
    private static let historyLimit = 1024

    @State private var activities: [Activity]

    init(session: Session, historyController: HistoryController) {
        self.session = session
        self.historyController = historyController
        // Seed synchronously from the local DB so the list shows immediately,
        // then `sync()` refreshes it from the server.
        _activities = State(initialValue: session.recentActivities(limit: Self.historyLimit))
    }

    var body: some View {
        Background(color: .backgroundMain) {
            if activities.isEmpty {
                Text("No activity yet")
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(activities) { activity in
                            ActivityRow(activity: activity)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .softScrollEdge(for: .top)
            }
        }
        .navigationTitle("Activity")
        .toolbarTitleDisplayMode(.inline)
        .onAppear { historyController.sync() }
        // A sync writes new rows to the local DB independently of any balance
        // change, so reload the slice on any DB change.
        .onReceive(NotificationCenter.default.publisher(for: .databaseDidChange)) { _ in
            activities = session.recentActivities(limit: Self.historyLimit)
        }
    }
}
