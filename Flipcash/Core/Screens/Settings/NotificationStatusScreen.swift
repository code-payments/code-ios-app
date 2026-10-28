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
    @Environment(ToastController.self) private var toasts
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var model: NotificationStatusViewModel?

    var body: some View {
        // The page lays out every check before the first read so nothing moves as results land;
        // status changes, hidden rows and the fold all animate in place.
        let page = model?.page
        let shown = page ?? NotificationStatus.checkingPage()
        // At accessibility sizes a pinned footer would cover most of the screen.
        let scrollsFooter = dynamicTypeSize.isAccessibilitySize

        Background(color: .backgroundMain) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SummaryCard(summary: shown.summary)
                        .padding(.horizontal, 20)
                        .padding(.top, 20)

                    checks(page: shown)

                    if scrollsFooter {
                        footer(page: page)
                    }
                }
                .padding(.bottom, 20)
                .animation(.smooth, value: shown)
                .animation(.smooth, value: model?.isExpanded)
            }
        }
        // A scroll edge bar, so the checks fade out under the buttons.
        .scrollEdgeBar(.bottom) {
            if !scrollsFooter {
                footer(page: page)
                    .toastClearance(toasts)
            }
        }
        .navigationTitle("Notifications")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                checkAgainButton
            }
        }
        .task {
            let model = model ?? NotificationStatusViewModel(pushController: pushController)
            self.model = model
            await model.runChecks()
        }
        .onChange(of: scenePhase) { _, phase in
            // Coming back from Settings after a fix re-reads the phone's settings; registration
            // keeps its last result.
            guard phase == .active, let model else { return }
            Task { await model.rereadSettings() }
        }
        .onDisappear {
            model?.stop()
        }
    }

    private var checkAgainButton: some View {
        Button {
            guard let model else { return }
            Task { await model.checkAgain() }
        } label: {
            Image(systemName: "arrow.clockwise")
        }
        .disabled(model?.isRunning != false)
        .accessibilityLabel("Check Again")
        .accessibilityIdentifier("notification-status-check-again")
    }

    @ViewBuilder
    private func checks(page: NotificationStatus.Page) -> some View {
        if let foldedTitle = page.foldedTitle, model?.isExpanded != true {
            FoldedRow(title: foldedTitle) {
                model?.isExpanded = true
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .transition(.opacity)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(NotificationStatus.Group.allCases, id: \.self) { group in
                    let rows = page.rows(in: group)
                    if !rows.isEmpty {
                        // Title case, which `SettingsSectionHeader` would uppercase; padded to match it.
                        ListHeader(group.title)
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                            .padding(.bottom, 3)
                        CheckGroup(rows: rows) { fix in
                            guard let model else { return }
                            Task { await model.perform(fix) }
                        }
                        .padding(.horizontal, 20)
                    }
                }
            }
            .transition(.opacity)
        }
    }

    /// `page` is `nil` until the phone's settings have been read; the test stays off until then.
    @ViewBuilder
    private func footer(page: NotificationStatus.Page?) -> some View {
        let isTestSent = model?.isTestSent == true
        let isTestEnabled = page?.isTestEnabled == true

        VStack(spacing: 12) {
            Button(isTestSent ? "Send Again" : "Send Test Notification") {
                guard let model else { return }
                Task {
                    guard await model.sendTest() else { return }
                    toasts.show(.init(
                        "Test notification sent",
                        systemImage: "checkmark.circle.fill",
                        messageIdentifier: "notification-status-test-sent",
                        duration: .seconds(2)
                    ))
                }
            }
            .buttonStyle(isTestSent ? .filled20 : .filled)
            // Both fills are translucent; without this the checks show through them.
            .background(Color.backgroundMain, in: RoundedRectangle(cornerRadius: Metrics.buttonRadius))
            .disabled(!isTestEnabled)
            .accessibilityIdentifier("notification-status-send-test")

            ShareLink(item: model?.report ?? "") {
                Text("Share Report")
            }
            .buttonStyle(.subtle)
            .disabled(model == nil)

            Group {
                if page != nil, !isTestEnabled {
                    Text("Turn on notifications to send a test.")
                        .foregroundStyle(Color.textSecondary)
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
        .padding(.top, 12)
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
            .contentTransition(.opacity)
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

            // Every row, Checking included, is as tall as a title over two lines of detail, so a
            // result that wraps doesn't move the rows below it.
            ZStack(alignment: .leading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: " ")
                        .font(.appTextMessage)
                    Text(verbatim: " ")
                        .font(.appTextCaption)
                        .lineLimit(2, reservesSpace: true)
                }
                .hidden()
                .accessibilityHidden(true)

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
                .contentTransition(.opacity)
                .accessibilityElement(children: .combine)
            }

            Spacer(minLength: 0)

            if let fix = row.fix, let fixTitle = row.fixTitle {
                Button(fixTitle) { onFix(fix) }
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textAction)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.action))
                    .buttonStyle(.plain)
                    .disabled(row.status == .checking)
                    .accessibilityIdentifier("notification-status-fix-\(row.check.rawValue)")
                    .transition(.opacity)
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
                    .transition(.opacity)
            } else {
                Image(systemName: glyph)
                    .font(size.glyph)
                    .foregroundStyle(Color.textAction)
                    .contentTransition(.symbolEffect(.replace))
                    .transition(.opacity)
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
