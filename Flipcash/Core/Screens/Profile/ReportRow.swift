//
//  ReportRow.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// The report control as both profile surfaces draw it: one row that opens the reason sheet.
///
/// A named unit rather than a copy per screen, for the same reason ``ChatMuteRow`` is one — except
/// that here the two screens report *different things*, so the target is the parameter. A user's
/// profile names the person; a group's names the chat. Never the other way around: a tip DM's id is
/// derived on this client, so a report naming that chat would name something the server has never
/// been told about.
struct ReportRow: View {

    let target: ReportTarget
    let insets: EdgeInsets
    var chevron: ChatMuteRow.Chevron = .standard

    @State private var isReporting = false

    var body: some View {
        Row(insets: insets, accessory: chevron == .standard ? .chevron : nil) {
            Image(systemName: "flag")
                .frame(minWidth: 45)
            Text("Report")
                .foregroundStyle(.textMain)

            if chevron == .secondary {
                // Nothing has claimed the slack, so the chevron needs the spacer the accessory
                // would have brought.
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.textSecondary)
            }
        } action: {
            isReporting = true
        }
        .accessibilityIdentifier("chat-report")
        .fullScreenCover(isPresented: $isReporting) {
            NavigationStack {
                ReportFlowScreen(target: target)
            }
        }
    }
}
