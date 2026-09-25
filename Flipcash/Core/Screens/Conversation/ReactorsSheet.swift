//
//  ReactorsSheet.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// Everyone who reacted to a message, one row per person with every emoji they used.
struct ReactorsSheet: View {

    /// The message's pills, in the row's own display order — both the title count and the filter
    /// row read this rather than re-deriving it, so they always agree with what's on the bubble.
    let pills: [ReactionPill]
    /// Already loading its first pages when the sheet appears.
    let model: ReactorsListModel
    /// Opens a tapped reactor's profile; the caller dismisses the sheet first.
    let openProfile: (UserID) -> Void

    @Environment(Session.self) private var session
    @Environment(SessionContainer.self) private var sessionContainer
    @Environment(\.dismiss) private var dismiss

    /// Set once the first load has run long enough to be noticeable, so a quick load never flashes
    /// placeholders.
    @State private var showsPlaceholders = false
    /// Names and handles for the reactors on screen, keyed by user id — filled in as rows appear.
    @State private var identities: [UserID: Identity] = [:]

    private struct Identity {
        var name: String?
        var handle: String?
    }

    var body: some View {
        list
            .topBar { bar }
            .softScrollEdge(for: [.top, .bottom])
            .background(Color.backgroundMain)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
    }

    /// Names a reactor from what the device holds — a fetched profile, then any chat roster or known
    /// author that has them — and fetches their public profile through `KnownAuthorDirectory` only
    /// when none does. The viewer's own row reads "You".
    private func resolveProfile(for userID: UserID) async {
        if userID == session.userID {
            identities[userID] = Identity(name: "You", handle: session.profile?.username?.handle)
            await loadAvatar(for: userID, picture: session.profile?.profilePicture)
            return
        }
        if let cached = session.cachedUserProfile(for: userID), cached.displayName?.isEmpty == false {
            identities[userID] = Identity(name: cached.displayName, handle: cached.username?.handle)
            await loadAvatar(for: userID, picture: cached.profilePicture)
            return
        }
        if let member = knownMember(userID) {
            identities[userID] = Identity(name: member.displayName, handle: member.username?.handle)
            await loadAvatar(for: userID, picture: member.profilePicture)
            return
        }
        await sessionContainer.knownAuthors.resolve([userID])
        if let member = sessionContainer.knownAuthors.snapshot.membersByUserID[userID] {
            identities[userID] = Identity(name: member.displayName, handle: member.username?.handle)
            await loadAvatar(for: userID, picture: member.profilePicture)
        }
    }

    private func knownMember(_ userID: UserID) -> ConversationMember? {
        let rosterMember = sessionContainer.conversationController.conversations
            .lazy
            .flatMap(\.members)
            .first { $0.userID == userID && !$0.displayName.isEmpty }
        return rosterMember ?? sessionContainer.knownAuthors.snapshot.membersByUserID[userID]
    }

    private func loadAvatar(for userID: UserID, picture: ProfilePicture?) async {
        guard let picture else { return }
        await sessionContainer.profileAvatars.load(userID: userID, picture: picture)
    }

    /// The title and filter pills, floating over the list as it scrolls under them.
    private var bar: some View {
        VStack(spacing: 20) {
            ZStack {
                Text("\(pills.totalReactionCount) Reactions")
                    .font(.default(size: 18, weight: .semibold))
                    .foregroundStyle(Color.textMain)
                HStack {
                    Spacer()
                    CloseButton(style: .glass) { dismiss() }
                }
                .padding(.horizontal, 20)
            }
            filterRow
        }
        .padding(.top, 28)
        .padding(.bottom, 12)
    }

    /// The message's pills as a summary, opened at the first.
    /// Centred when the pills fit; otherwise a scroll row. Not a centre scroll anchor, which would
    /// also open an overflowing row scrolled to its middle.
    private var filterRow: some View {
        ViewThatFits(in: .horizontal) {
            pillStack
                .padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                pillStack
            }
            .contentMargins(.horizontal, 20, for: .scrollContent)
            .edgeFade(leading: 20, trailing: 20)
        }
    }

    private var pillStack: some View {
        HStack(spacing: 8) {
            ForEach(pills) { pill in
                filterPill(pill)
            }
        }
        .fixedSize()
    }

    private func filterPill(_ pill: ReactionPill) -> some View {
        HStack(spacing: 4) {
            Text(pill.emoji)
                .font(.system(size: 17))
            Text("\(pill.count)")
                .font(.default(size: 13, weight: .medium))
                .foregroundStyle(Color.textMain.opacity(0.5))
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(Capsule().fill(Color.black.opacity(0.3)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(pill.emoji), \(pill.count) reactions")
    }

    /// One row per reactor. The only spinner is the one at the bottom while the next page loads.
    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                let rows = model.rows
                if rows.isEmpty, model.isLoading, showsPlaceholders {
                    ForEach(0..<placeholderCount, id: \.self) { _ in
                        ReactorPlaceholderRow()
                    }
                    .transition(.opacity)
                }
                ForEach(rows) { row in
                    self.row(for: row)
                        .onAppear {
                            guard row.id == rows.last?.id else { return }
                            Task { await model.loadMoreIfNeeded() }
                        }
                }
                if model.isLoading, !rows.isEmpty {
                    ProgressView()
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 4)
            .animation(.easeOut(duration: 0.2), value: model.rows.isEmpty)
        }
        .task {
            try? await Task.sleep(for: Self.placeholderDelay)
            showsPlaceholders = true
        }
    }

    private static let placeholderDelay: Duration = .milliseconds(300)

    /// At least as many people as the biggest pill reacted; capped so a busy message doesn't fill
    /// the sheet with placeholders.
    private var placeholderCount: Int {
        Int(min(pills.map(\.count).max() ?? 1, 5))
    }

    /// The least room the emoji keep, so a long name truncates instead of squeezing them out.
    private static let minEmojiWidth: CGFloat = 140

    private func row(for reactor: ReactorsListModel.Row) -> some View {
        let identity = identities[reactor.userID]
        let displayName = identity?.name ?? ""
        let handle = identity?.handle
        // Only the person opens their profile; the emoji are theirs to scroll, not a tap target.
        return HStack(spacing: 0) {
            Button {
                openProfile(reactor.userID)
            } label: {
                HStack(spacing: 15) {
                    ContactAvatarView(
                        id: reactor.userID.uuidString,
                        displayName: displayName,
                        imageData: sessionContainer.profileAvatars.data(for: reactor.userID),
                        size: 48
                    )
                    VStack(alignment: .leading, spacing: 0) {
                        Text(displayName)
                            .font(.default(size: 16, weight: .semibold))
                            .foregroundStyle(Color.textMain)
                        if let handle {
                            Text(handle)
                                .font(.default(size: 13, weight: .medium))
                                .foregroundStyle(Color.textMain.opacity(0.5))
                        }
                    }
                    .lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .layoutPriority(1)
            ReactorEmojis(emojis: reactor.emojis)
                .frame(minWidth: Self.minEmojiWidth, maxWidth: .infinity)
        }
        .padding(.leading, 20)
        .padding(.vertical, 8.5)
        .task(id: reactor.userID) {
            await resolveProfile(for: reactor.userID)
        }
    }
}

/// A reactor row while the first page loads: an avatar and a name, with no emoji, since which emoji
/// each person used isn't known until the page lands.
private struct ReactorPlaceholderRow: View {

    var body: some View {
        HStack(spacing: 15) {
            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 0) {
                Text("Reactor Name")
                    .font(.default(size: 16, weight: .semibold))
                Text("@handle")
                    .font(.default(size: 13, weight: .medium))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8.5)
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }
}

private extension View {

    /// Pins `bar` above the scroll view so its content scrolls under it. On iOS 26+ the bar joins the
    /// scroll edge effect, so the list fades out beneath it instead of stopping at a hard line.
    @ViewBuilder
    func topBar(@ViewBuilder _ bar: () -> some View) -> some View {
        if #available(iOS 26.0, *) {
            safeAreaBar(edge: .top, spacing: 0, content: bar)
        } else {
            safeAreaInset(edge: .top, spacing: 0, content: bar)
        }
    }
}

/// A reactor's emoji, trailing-aligned in whatever the name leaves. When there are more than fit
/// they scroll sideways and run off the screen edge instead of stopping at the row's margin.
private struct ReactorEmojis: View {

    let emojis: [String]

    /// Also the gap to the name, so an emoji scrolled back fades out before it reaches it.
    private static let leadingMargin: CGFloat = 16
    private static let trailingMargin: CGFloat = 20

    // Two layouts rather than a trailing scroll anchor: that anchor also opens an overflowing row
    // scrolled to its end, and a row should always open on its first emoji.
    var body: some View {
        ViewThatFits(in: .horizontal) {
            glyphs
                .padding(.leading, Self.leadingMargin)
                .padding(.trailing, Self.trailingMargin)
            ScrollView(.horizontal, showsIndicators: false) {
                glyphs
            }
            .contentMargins(.leading, Self.leadingMargin, for: .scrollContent)
            .contentMargins(.trailing, Self.trailingMargin, for: .scrollContent)
            .edgeFade(leading: Self.leadingMargin, trailing: Self.trailingMargin)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(emojis.joined(separator: " "))
    }

    private var glyphs: some View {
        HStack(spacing: 2) {
            ForEach(Array(emojis.enumerated()), id: \.offset) { _, emoji in
                Text(emoji)
                    .font(.system(size: 30))
            }
        }
        .fixedSize()
    }
}

private extension View {

    /// Fades a horizontal scroll view out across its content margins, so content scrolled past
    /// either end runs off into nothing. Content at rest sits inside the margins and stays sharp.
    func edgeFade(leading: CGFloat, trailing: CGFloat) -> some View {
        mask {
            HStack(spacing: 0) {
                LinearGradient(stops: edgeFadeStops, startPoint: .leading, endPoint: .trailing)
                    .frame(width: leading)
                Color.black
                LinearGradient(stops: edgeFadeStops, startPoint: .trailing, endPoint: .leading)
                    .frame(width: trailing)
            }
        }
    }
}

/// Eased rather than linear, so the fade has no visible start line.
private let edgeFadeStops: [Gradient.Stop] = [
    .init(color: .black.opacity(0), location: 0),
    .init(color: .black.opacity(0.15), location: 0.25),
    .init(color: .black.opacity(0.5), location: 0.5),
    .init(color: .black.opacity(0.85), location: 0.75),
    .init(color: .black, location: 1),
]
