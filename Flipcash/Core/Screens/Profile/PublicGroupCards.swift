//
//  PublicGroupCards.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// What it takes to join and chat in a public group: one tile with the amount as its hero when
/// joining and chatting ask the same, two side by side when they differ, and the viewer's balance
/// under them.
struct PublicGroupRequirementsView: View {

    let tiles: [PublicGroupRequirementTile]
    let yourBalance: String?
    let onToken: (PublicGroupToken) -> Void

    @Environment(\.bleedPalette) private var palette

    var body: some View {
        content
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Requirements")
    }

    @ViewBuilder
    private var content: some View {
        if tiles.count == 1, let tile = tiles.first {
            VStack(alignment: .leading, spacing: 0) {
                tileContent(tile, isWide: true)
                if let yourBalance {
                    PublicGroupHairline()
                        .padding(.vertical, PublicGroupLook.dividerGap)
                    footer(yourBalance, style: palette.controlSecondaryStyle)
                }
            }
            .padding(PublicGroupLook.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.controlTint, in: PublicGroupLook.cardShape)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: PublicGroupLook.cardGap) {
                    ForEach(tiles) { tile in
                        tileContent(tile, isWide: false)
                            .padding(PublicGroupLook.cardPadding)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(palette.controlTint, in: PublicGroupLook.cardShape)
                    }
                }
                if let yourBalance {
                    footer(yourBalance, style: palette.secondaryStyle)
                        .padding(.horizontal, PublicGroupLook.cardPadding)
                }
            }
        }
    }

    private func tileContent(_ tile: PublicGroupRequirementTile, isWide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if isWide {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    amount(tile)
                    tokenButton(tile.token, purpose: tile.purpose)
                }
            } else {
                amount(tile)
                tokenButton(tile.token, purpose: tile.purpose)
            }
            Text(tile.purpose.caption)
                .font(.appTextSmall)
                .foregroundStyle(palette.controlSecondaryStyle)
                // The amount's label already reads it.
                .accessibilityHidden(true)
        }
    }

    private func amount(_ tile: PublicGroupRequirementTile) -> some View {
        Text(tile.amount)
            .font(.appDisplayMedium)
            .foregroundStyle(palette.primaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .accessibilityLabel("\(tile.amount) \(tile.purpose.caption)")
            .accessibilityIdentifier(tile.purpose == .chat ? "group-profile-chat-minimum" : "group-profile-join-minimum")
    }

    @ViewBuilder
    private func tokenButton(_ token: PublicGroupToken?, purpose: PublicGroupRequirementTile.Purpose) -> some View {
        if let token {
            Button {
                onToken(token)
            } label: {
                HStack(spacing: 6) {
                    Text("of")
                        .font(.appTextMedium)
                        .foregroundStyle(palette.controlSecondaryStyle)
                    TokenIconWithName(
                        url: token.imageURL,
                        monogramID: token.mint.base58,
                        name: token.name,
                        iconSize: 16
                    )
                }
                // Grown to a 44pt target without moving anything.
                .padding(.vertical, 12)
                .contentShape(Rectangle())
                .padding(.vertical, -12)
            }
            .buttonStyle(PublicGroupDimButtonStyle())
            .accessibilityIdentifier(Self.tokenIdentifier(for: purpose))
        }
    }

    /// A split pair's tiles each name the token, so their buttons need their own identifiers.
    private static func tokenIdentifier(for purpose: PublicGroupRequirementTile.Purpose) -> String {
        switch purpose {
        case .joinAndChat:  "group-profile-token"
        case .join:         "group-profile-token-join"
        case .chat:         "group-profile-token-chat"
        }
    }

    private func footer(_ yourBalance: String, style: AnyShapeStyle) -> some View {
        HStack {
            Text("Your Balance")
            Spacer()
            Text(yourBalance)
        }
        .font(.appTextSmall)
        .foregroundStyle(style)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("group-profile-your-balance")
    }

}

/// Who has been chatting in a public group lately: a facepile, how many people that is, when the
/// last message was, and the host, who opens their profile.
struct PublicGroupPulseCard: View {

    let pulse: PublicGroupPulse
    let host: GroupPortrait?
    let memberCount: UInt64?
    let portraitData: (UserID) -> Data?
    let loadPortrait: (GroupPortrait) async -> Void
    let onSelect: (UserID) -> Void

    @Environment(\.bleedPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !pulse.faces.isEmpty {
                facepile
                    .padding(.bottom, PublicGroupLook.facepileToHeadline)
            }

            Text(PublicGroupCopy.chatting(count: pulse.chattingCount))
                .font(.appTextMedium)
                .foregroundStyle(palette.primaryText)

            if let meta = PublicGroupCopy.pulseMeta(lastMessageAt: pulse.lastMessageAt, memberCount: memberCount, now: .now) {
                Text(meta)
                    .font(.appTextCaption)
                    .foregroundStyle(palette.controlSecondaryStyle)
                    .padding(.top, PublicGroupLook.headlineToMeta)
            }

            if let host {
                PublicGroupHairline()
                    .padding(.vertical, PublicGroupLook.dividerGap)
                hostRow(host)
            }
        }
        .padding(PublicGroupLook.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.controlTint, in: PublicGroupLook.cardShape)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Chatting recently")
        .accessibilityIdentifier("group-profile-chatting")
    }

    // MARK: - Facepile -

    private var facepile: some View {
        HStack(spacing: -Self.faceOverlap) {
            ForEach(Array(pulse.faces.enumerated()), id: \.element.userID) { index, portrait in
                // The next face covers the last 10pt of this one, so only the rest is this face's.
                let isCovered = index < pulse.faces.count - 1 || pulse.overflow > 0
                Button {
                    onSelect(portrait.userID)
                } label: {
                    ContactAvatarView(
                        id: portrait.userID.uuidString,
                        displayName: portrait.name,
                        imageData: portraitData(portrait.userID),
                        blurhash: portrait.picture?.thumbnailBlurhash,
                        size: Self.faceSize
                    )
                    .overlay { Circle().strokeBorder(palette.controlTint, lineWidth: 2) }
                    // Grown to a 44pt-tall target without moving anything, and cut to the visible part.
                    .padding(.vertical, (Self.hitHeight - Self.faceSize) / 2)
                    .contentShape(FaceHitShape(visibleWidth: isCovered ? Self.faceSize - Self.faceOverlap : Self.faceSize))
                    .padding(.vertical, -(Self.hitHeight - Self.faceSize) / 2)
                }
                .buttonStyle(PublicGroupDimButtonStyle())
                .accessibilityLabel(portrait.name)
                .task(id: portrait.userID) { await loadPortrait(portrait) }
            }
            if pulse.overflow > 0 {
                Text("+\(pulse.overflow)")
                    .font(.appTextHeading)
                    .foregroundStyle(palette.primaryText)
                    .frame(width: Self.faceSize, height: Self.faceSize)
                    .background(palette.hairline, in: Circle())
                    .overlay { Circle().strokeBorder(palette.controlTint, lineWidth: 2) }
                    .accessibilityLabel("\(pulse.overflow) more")
            }
        }
    }

    // MARK: - Host -

    private func hostRow(_ host: GroupPortrait) -> some View {
        Button {
            onSelect(host.userID)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                ContactAvatarView(
                    id: host.userID.uuidString,
                    displayName: host.name,
                    imageData: portraitData(host.userID),
                    blurhash: host.picture?.thumbnailBlurhash,
                    size: Self.hostSize
                )
                .overlay(alignment: .bottomTrailing) { hostMark }

                HStack(spacing: 4) {
                    Text("Hosted by")
                        .foregroundStyle(palette.controlSecondaryStyle)
                    Text(host.name)
                        .foregroundStyle(palette.primaryText)
                        .lineLimit(1)
                }
                .font(.appTextSmall)

                Spacer(minLength: 8)

                Image.icon(.chevronRightMedium)
                    .iconSize(16)
                    .foregroundStyle(palette.controlSecondaryStyle)
            }
            // Grown to a 44pt target without moving anything, so the row's visible space is the box's.
            .padding(.vertical, (Self.hitHeight - Self.hostSize) / 2)
            .contentShape(Rectangle())
            .padding(.vertical, -(Self.hitHeight - Self.hostSize) / 2)
        }
        .buttonStyle(PublicGroupDimButtonStyle())
        .accessibilityLabel("Hosted by \(host.name)")
        .task(id: host.userID) { await loadPortrait(host) }
    }

    private var hostMark: some View {
        Image.icon(.hand5Finger)
            .iconSize(9)
            .foregroundStyle(palette.primaryText)
            .frame(width: 16, height: 16)
            .background(palette.background, in: Circle())
            .overlay { Circle().strokeBorder(palette.controlTint, lineWidth: 1.5) }
            .offset(x: 3, y: 3)
            .accessibilityHidden(true)
    }

    private static var faceSize: CGFloat { 36 }
    private static var faceOverlap: CGFloat { 10 }
    private static var hitHeight: CGFloat { 44 }
    private static var hostSize: CGFloat { 28 }
}

/// A face's tap area: the full height of the rect, but only the width the next face doesn't cover.
nonisolated private struct FaceHitShape: Shape {

    let visibleWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX, y: rect.minY, width: visibleWidth, height: rect.height))
    }
}
