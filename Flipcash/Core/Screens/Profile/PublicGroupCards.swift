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
        if tiles.count == 1, let tile = tiles.first {
            VStack(alignment: .leading, spacing: 0) {
                tileContent(tile, isWide: true)
                if let yourBalance {
                    Rectangle()
                        .fill(palette.hairline)
                        .frame(height: 1)
                        .padding(.vertical, 8)
                    footer(yourBalance)
                }
            }
            .padding(Self.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.controlTint, in: surface)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(tiles) { tile in
                        tileContent(tile, isWide: false)
                            .padding(Self.padding)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(palette.controlTint, in: surface)
                    }
                }
                if let yourBalance {
                    footer(yourBalance)
                        .padding(.horizontal, Self.padding)
                }
            }
        }
    }

    private func tileContent(_ tile: PublicGroupRequirementTile, isWide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if isWide {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    amount(tile)
                    tokenButton(tile.token)
                }
            } else {
                amount(tile)
                tokenButton(tile.token)
            }
            Text(tile.purpose.caption)
                .font(.appTextSmall)
                .foregroundStyle(palette.secondaryStyle)
        }
    }

    private func amount(_ tile: PublicGroupRequirementTile) -> some View {
        Text(tile.amount)
            .font(.appDisplayMedium)
            .foregroundStyle(palette.primaryText)
            .accessibilityLabel("\(tile.amount) \(tile.purpose.caption)")
            .accessibilityIdentifier(tile.purpose == .chat ? "group-profile-chat-minimum" : "group-profile-join-minimum")
    }

    @ViewBuilder
    private func tokenButton(_ token: PublicGroupToken?) -> some View {
        if let token {
            Button {
                onToken(token)
            } label: {
                HStack(spacing: 6) {
                    Text("of")
                        .font(.appTextMedium)
                        .foregroundStyle(palette.secondaryStyle)
                    TokenIconWithName(
                        url: token.imageURL,
                        monogramID: token.mint.base58,
                        name: token.name,
                        iconSize: 16
                    )
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PublicGroupDimButtonStyle())
            .accessibilityIdentifier("group-profile-token")
        }
    }

    private func footer(_ yourBalance: String) -> some View {
        HStack {
            Text("Your Balance")
            Spacer()
            Text(yourBalance)
        }
        .font(.appTextSmall)
        .foregroundStyle(palette.secondaryStyle)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("group-profile-your-balance")
    }

    private var surface: RoundedRectangle {
        RoundedRectangle(cornerRadius: Metrics.boxRadius, style: .continuous)
    }

    private static var padding: CGFloat { 16 }
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
                    .padding(.bottom, 12)
            }

            Text(PublicGroupCopy.chatting(count: pulse.chattingCount))
                .font(.appTextMedium)
                .foregroundStyle(palette.primaryText)

            if let meta = PublicGroupCopy.pulseMeta(lastMessageAt: pulse.lastMessageAt, memberCount: memberCount, now: .now) {
                Text(meta)
                    .font(.appTextCaption)
                    .foregroundStyle(palette.secondaryStyle)
                    .padding(.top, 2)
            }

            if let host {
                Rectangle()
                    .fill(palette.hairline)
                    .frame(height: 1)
                    .padding(.top, 12)
                    .padding(.bottom, 12)
                hostRow(host)
            }
        }
        .padding(.top, Self.padding)
        .padding(.horizontal, Self.padding)
        .padding(.bottom, host == nil ? Self.padding : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.controlTint, in: RoundedRectangle(cornerRadius: Metrics.boxRadius, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("group-profile-chatting")
    }

    // MARK: - Facepile -

    private var facepile: some View {
        HStack(spacing: -Self.faceOverlap) {
            ForEach(pulse.faces, id: \.userID) { portrait in
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
            HStack(spacing: 12) {
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
                        .foregroundStyle(palette.secondaryStyle)
                    Text(host.name)
                        .foregroundStyle(palette.primaryText)
                        .lineLimit(1)
                }
                .font(.appTextSmall)

                Spacer(minLength: 8)

                Image.icon(.chevronRightMedium)
                    .iconSize(16)
                    .foregroundStyle(palette.secondaryStyle)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
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

    private static var padding: CGFloat { 16 }
    private static var faceSize: CGFloat { 36 }
    private static var faceOverlap: CGFloat { 10 }
    private static var hostSize: CGFloat { 28 }
}
