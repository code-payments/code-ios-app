//
//  GroupCardScreen.swift
//  Flipcash
//

import SwiftUI
import UIKit
import FlipcashCore
import FlipcashUI

/// A group's scan card, drawn over the invite sheet by its Show Group Card tile: the group's
/// picture and title over a QR of its invite link, with Download in the top corner and
/// Close pinned to the bottom. Behaves as ``ProfileCardScreen`` does.
struct GroupCardScreen: View {

    /// What the card shows, taken from the conversation the invite sheet already holds.
    nonisolated struct Card {
        let id: ConversationID
        let title: String?
        let avatar: Data?
        let blurhash: String?
        let memberCount: UInt64

        /// The invite link the QR encodes, from the same builder the Share and Copy tiles use.
        var url: URL { .groupChatInvite(for: id) }

        /// The title, or `Group Chat` for a group that has none.
        var displayTitle: String {
            let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? Self.untitled : trimmed
        }

        static let untitled = "Group Chat"
    }

    let card: Card

    /// Called by Close. The presenter animates the card away with ``fade``.
    let onClose: () -> Void

    @State private var geometry: GroupQRGeometry?
    @State private var isShowingDownloadOptions = false

    /// The format tapped in the download sheet, held until the sheet is gone so the share sheet has
    /// a settled controller to present on.
    @State private var pendingDownload: TipCardDownloadFormat?
    @State private var errorDialog: DialogItem?

    /// The brightness to put back on close — set only when this screen raised it.
    @State private var previousBrightness: CGFloat?

    @State private var isRevealed = false
    @State private var isCardShown = false

    private static let maxCardWidth: CGFloat = 302
    private static let horizontalInset: CGFloat = 20

    private static let minimumScanBrightness: CGFloat = 0.4
    private static let boostedBrightness: CGFloat = 0.6

    /// The profile card's reveal: 0.55 scale, 0.4s at 0.4 damping.
    private static let revealScale: CGFloat = 0.55
    private static let revealSpring: Animation = .spring(duration: 0.4, bounce: 0.6)

    /// The open and close fade.
    static let fade: Animation = .easeOut(duration: 0.25)

    /// Fractions of the card's width.
    private static let avatarFraction: CGFloat = 0.2
    private static let avatarRingFraction: CGFloat = 0.012
    private static let contentTopFraction: CGFloat = 0.12
    private static let tileFraction: CGFloat = 0.68
    private static let textInsetFraction: CGFloat = 0.06
    private static let tileGapFraction: CGFloat = 0.06
    private static let bottomInsetFraction: CGFloat = 0.06

    init(card: Card, onClose: @escaping () -> Void) {
        self.card = card
        self.onClose = onClose
        self._geometry = State(initialValue: QRModules.encode(card.url.absoluteString).map(GroupQRGeometry.init))
    }

    var body: some View {
        ZStack {
            Color.backgroundMain
                .ignoresSafeArea()
                .opacity(isRevealed ? 1 : 0)

            ScrollView(showsIndicators: false) {
                cardView
                    // The avatar rises above the card, so the card sits half an avatar lower to keep
                    // the group centred.
                    .offset(y: avatarDiameter / 2)
                    .scaleEffect(isCardShown ? 1 : Self.revealScale)
                    .opacity(isRevealed ? 1 : 0)
                    .padding(.horizontal, Self.horizontalInset)
                    .containerRelativeFrame(.vertical, alignment: .center)
            }
        }
        .overlay(alignment: .topTrailing) {
            downloadButton
                .opacity(isRevealed ? 1 : 0)
                .padding(16)
        }
        .safeAreaInset(edge: .bottom) {
            Button("Close", action: onClose)
                .buttonStyle(.subtle)
                .opacity(isRevealed ? 1 : 0)
                .accessibilityIdentifier("group-card-close")
                .padding(.horizontal, Self.horizontalInset)
        }
        .sheet(isPresented: $isShowingDownloadOptions, onDismiss: exportPendingDownload) {
            TipCardDownloadSheet(
                onSelect: { pendingDownload = $0; isShowingDownloadOptions = false },
                onCancel: { isShowingDownloadOptions = false }
            )
        }
        .dialog(item: $errorDialog)
        .onAppear {
            Analytics.groupCardShown(memberCount: card.memberCount)
            boostBrightness()
            reveal()
        }
        .onDisappear(perform: restoreBrightness)
    }

    // MARK: - Card -

    private var cardWidth: CGFloat {
        let screenWidth = UIApplication.shared.firstWindowScene?.screen.bounds.width ?? Self.maxCardWidth
        return min(Self.maxCardWidth, screenWidth - Self.horizontalInset * 2)
    }

    private var avatarDiameter: CGFloat { cardWidth * Self.avatarFraction }

    private var cardView: some View {
        let width = cardWidth
        let fontSize = width * TipcardView.nameFraction

        return VStack(spacing: 0) {
            Text(card.displayTitle)
                .font(.default(size: fontSize, weight: .bold))
                .foregroundStyle(Color.textMain)
                .lineLimit(2)
                .truncationMode(.tail)
                .multilineTextAlignment(.center)
                .padding(.horizontal, width * Self.textInsetFraction)
                .accessibilityIdentifier("group-card-title")

            if let geometry {
                GroupQRTile(geometry: geometry)
                    .frame(width: width * Self.tileFraction, height: width * Self.tileFraction)
                    .padding(.top, width * Self.tileGapFraction)
                    .accessibilityHidden(false)
                    .accessibilityElement()
                    .accessibilityLabel("QR code for \(card.displayTitle)")
                    .accessibilityIdentifier("group-card-qr")
            }
        }
        .padding(.top, width * Self.contentTopFraction)
        .padding(.bottom, width * Self.bottomInsetFraction)
        .frame(width: width)
        .background(Color.black.opacity(0.36).background(BackdropBlur(radius: 20)))
        .clipShape(RoundedRectangle(cornerRadius: width * 0.08, style: .continuous))
        .overlay(alignment: .top) {
            avatar
                .offset(y: -avatarDiameter / 2)
        }
    }

    /// The group's picture, or its initial, centred on the card's top edge and ringed in the screen
    /// background so it reads as cut out of the card.
    private var avatar: some View {
        let ring = cardWidth * Self.avatarRingFraction
        return ContactAvatarView(
            id: card.id.description,
            displayName: card.displayTitle,
            imageData: card.avatar,
            blurhash: card.blurhash,
            size: avatarDiameter
        )
        .padding(ring)
        .background(Color.backgroundMain, in: Circle())
    }

    // MARK: - Download -

    /// Built as ``CloseButton``'s glass style so it reads as the sheet's close it covers.
    private var downloadButton: some View {
        Button {
            isShowingDownloadOptions = true
        } label: {
            Image.asset(.fileDownload)
                .foregroundStyle(Color.textMain)
                .frame(width: Self.platterDiameter, height: Self.platterDiameter)
        }
        .liquidGlassButtonStyle(shape: .circle)
        .accessibilityLabel("Download")
        .accessibilityIdentifier("group-card-download")
    }

    private static var platterDiameter: CGFloat {
        if #available(iOS 26, *) { 32 } else { 44 }
    }

    /// Exports the format the sheet picked and hands the file to the share sheet. Runs on the
    /// download sheet's dismissal, since the share sheet presents on the top-most view controller,
    /// which is the download sheet until then.
    private func exportPendingDownload() {
        guard let format = pendingDownload else { return }
        pendingDownload = nil

        guard let file = GroupCardExport.file(for: format, url: card.url, title: card.title) else {
            errorDialog = DialogItem.error(
                title: "Couldn't Export",
                subtitle: "We were unable to export your group code. Please try again"
            )
            return
        }

        Analytics.groupInviteDownloaded()
        ShareSheet.present(activityItems: [file]) { _ in
            GroupCardExport.discard(file)
        }
    }

    // MARK: - Reveal -

    private func reveal() {
        Haptics.vibrate()
        withAnimation(Self.fade) { isRevealed = true }
        withAnimation(Self.revealSpring) { isCardShown = true }
    }

    // MARK: - Brightness -

    private func boostBrightness() {
        guard let screen = UIApplication.shared.firstWindowScene?.screen,
              screen.brightness < Self.minimumScanBrightness else { return }
        previousBrightness = previousBrightness ?? screen.brightness
        screen.brightness = Self.boostedBrightness
    }

    private func restoreBrightness() {
        guard let previousBrightness, let screen = UIApplication.shared.firstWindowScene?.screen else { return }
        screen.brightness = previousBrightness
        self.previousBrightness = nil
    }
}
