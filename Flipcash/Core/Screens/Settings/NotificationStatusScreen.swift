//
//  NotificationStatusScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// Settings › Advanced › Notifications: whether notifications can reach this phone, what to fix
/// when they can't, and a local test notification.
struct NotificationStatusScreen: View {

    @Environment(PushController.self) private var pushController
    @Environment(\.scenePhase) private var scenePhase

    @State private var model: NotificationStatusViewModel?

    var body: some View {
        Background(color: .backgroundMain) {
            if let model, let page = model.page {
                content(model: model, page: page)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Notifications")
        .toolbarTitleDisplayMode(.inline)
        .task {
            let model = model ?? NotificationStatusViewModel(pushController: pushController)
            self.model = model
            await model.runChecks()
        }
        .onChange(of: scenePhase) { _, phase in
            // Coming back from Settings after a fix re-runs every check.
            guard phase == .active, let model else { return }
            Task { await model.runChecks() }
        }
        .onDisappear {
            model?.stop()
        }
    }

    @ViewBuilder
    private func content(model: NotificationStatusViewModel, page: NotificationStatus.Page) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SummaryCard(summary: page.summary)
                        .padding(.top, 20)

                    if let foldedTitle = page.foldedTitle, !model.isExpanded {
                        FoldedRow(title: foldedTitle) {
                            model.isExpanded = true
                        }
                        .padding(.top, 12)
                    } else {
                        ForEach(NotificationStatus.Group.allCases, id: \.self) { group in
                            let rows = page.rows(in: group)
                            if !rows.isEmpty {
                                SettingsSectionHeader(group.title)
                                    .padding(.horizontal, -20)
                                CheckGroup(rows: rows) { fix in
                                    Task { await model.perform(fix) }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
            }

            footer(model: model, page: page)
        }
    }

    @ViewBuilder
    private func footer(model: NotificationStatusViewModel, page: NotificationStatus.Page) -> some View {
        VStack(spacing: 12) {
            Button(model.isTestSent ? "Send again" : "Send test notification") {
                Task { await model.sendTest() }
            }
            .buttonStyle(model.isTestSent ? .filled20 : .filled)
            .disabled(!page.isTestEnabled)
            .accessibilityIdentifier("notification-status-send-test")

            ShareLink(item: model.report) {
                Text("Share report")
            }
            .buttonStyle(.subtle)

            Group {
                if !page.isTestEnabled {
                    Text("Turn on notifications to send a test.")
                        .foregroundStyle(Color.textSecondary)
                } else if model.isTestSent {
                    Text("Sent. Lock your phone in the next 3 seconds to see it on the Lock Screen.")
                        .foregroundStyle(Color.textSuccess)
                } else {
                    Text("The test is posted by this phone. It shows that notifications can appear here, not that Flipcash's servers can reach you.")
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .font(.appTextCaption)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }
}

// MARK: - Summary -

private struct SummaryCard: View {

    let summary: NotificationStatus.Summary

    var body: some View {
        HStack(spacing: 12) {
            StatusMark(status: summary.status, size: .large)

            VStack(alignment: .leading, spacing: 2) {
                Text(summary.title)
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textMain)
                if let detail = summary.detail {
                    Text(detail)
                        .font(.appTextCaption)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color.backgroundRow, in: RoundedRectangle(cornerRadius: Metrics.boxRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Rows -

private struct FoldedRow: View {

    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                StatusMark(status: .pass, size: .small)
                Text(title)
                    .font(.appTextMessage)
                    .foregroundStyle(Color.textMain)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(16)
            .background(Color.backgroundRow, in: RoundedRectangle(cornerRadius: Metrics.boxRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("notification-status-folded")
    }
}

private struct CheckGroup: View {

    let rows: [NotificationStatus.Row]
    let onFix: (NotificationStatus.Fix) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(rows) { row in
                CheckRow(row: row, onFix: onFix)
            }
        }
        .padding(16)
        .background(Color.backgroundRow, in: RoundedRectangle(cornerRadius: Metrics.boxRadius, style: .continuous))
    }
}

private struct CheckRow: View {

    let row: NotificationStatus.Row
    let onFix: (NotificationStatus.Fix) -> Void

    var body: some View {
        HStack(spacing: 12) {
            StatusMark(status: row.status, size: .small)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.appTextMessage)
                    .foregroundStyle(Color.textMain)
                if let detail = row.detail {
                    Text(detail)
                        .font(.appTextCaption)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 0)

            if let fix = row.fix, let fixTitle = row.fixTitle {
                Button(fixTitle) { onFix(fix) }
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textAction)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.action))
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("notification-status-fix-\(row.check.rawValue)")
            }
        }
    }
}

// MARK: - Status Mark -

private struct StatusMark: View {

    enum Size {
        case small
        case large

        var width: CGFloat { self == .small ? 16 : 26 }
        var height: CGFloat { self == .small ? 24 : 40 }
        var glyph: Font { self == .small ? .appTextCaption : .appTextMedium }
    }

    let status: NotificationStatus.Status
    let size: Size

    var body: some View {
        ZStack {
            Capsule()
                .fill(color)
            if status == .checking {
                ProgressView()
                    .controlSize(.mini)
                    .tint(Color.textAction)
            } else {
                Image(systemName: glyph)
                    .font(size.glyph)
                    .foregroundStyle(Color.textAction)
            }
        }
        .frame(width: size.width, height: size.height)
        .accessibilityLabel(Text(status.rawValue))
    }

    private var color: Color {
        switch status {
        case .pass:              .textSuccess
        case .warning:           .textWarning
        case .fail:              .textError
        case .checking, .unknown: .textSecondary
        }
    }

    private var glyph: String {
        switch status {
        case .pass:              "checkmark"
        case .warning, .fail:    "exclamationmark"
        case .checking, .unknown: "questionmark"
        }
    }
}
