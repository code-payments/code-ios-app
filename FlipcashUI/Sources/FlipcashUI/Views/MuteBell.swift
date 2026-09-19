//
//  MuteBell.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashCore

/// The bell that says a chat is silenced, for the surfaces that name a chat in passing — a row in
/// the chat list, the transcript's title bar.
///
/// A glyph rather than the amber chip the chat's own profile draws. Those surfaces are about the
/// chat, and the mute is one attribute among several, so it carries the weight of the chevron and
/// the timestamp beside it rather than taking a ground of its own.
///
/// Takes the mute and compares it against its own clock rather than taking a boolean. A timed mute
/// lapses with nothing sent from the server, so a bell handed a boolean stays lit until something
/// unrelated happens to redraw its host.
public struct MuteBell: View {

    private let mute: ConversationMuteState?
    private let leadingGap: CGFloat

    /// The instant the mute is read against, re-read when a timed one lapses.
    @State private var now = Date.now

    /// - Parameter leadingGap: space before the glyph, drawn only when the glyph is. The gap
    ///   belongs to the bell rather than to the host's stack spacing because it has to disappear
    ///   with the bell — a host reserving it would shorten its own content on every audible chat.
    public init(_ mute: ConversationMuteState?, leadingGap: CGFloat = 0) {
        self.mute = mute
        self.leadingGap = leadingGap
    }

    /// When the current mute lapses, or nil when it is indefinite or absent.
    private var expiry: Date? {
        guard case .until(let expiry) = mute else { return nil }
        return expiry
    }

    public var body: some View {
        Group {
            if mute?.isActive(at: now) == true {
                Image(systemName: "bell.slash.fill")
                    .font(.appTextCaption)
                    .foregroundStyle(Color.textSecondary)
                    .accessibilityLabel("Muted")
                    .padding(.leading, leadingGap)
            }
        }
        // Drop the bell the moment a timed mute lapses. Re-armed whenever the expiry changes, so
        // muting again under an open screen re-arms it; cancelled with the view.
        .task(id: expiry) {
            guard let expiry, expiry > .now else { return }
            try? await Task.sleep(for: .seconds(expiry.timeIntervalSinceNow))
            guard !Task.isCancelled else { return }
            now = .now
        }
    }
}
