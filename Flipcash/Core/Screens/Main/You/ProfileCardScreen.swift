//
//  ProfileCardScreen.swift
//  Flipcash
//

import SwiftUI
import UIKit
import FlipcashCore
import FlipcashUI

/// A person's profile card, drawn over the share sheet by its Show Profile Card tile, with Download
/// in the top corner and Close pinned to the bottom.
struct ProfileCardScreen: View {

    /// Whose card this is.
    struct Card {
        let userID: UserID
        let displayName: String
        let username: Username?
    }

    let card: Card

    /// Called by Close. The presenter animates the card away with ``fade``.
    let onClose: () -> Void

    @State private var isShowingDownloadOptions = false

    /// The format tapped in the download sheet, held until the sheet is gone so
    /// the share sheet has a settled controller to present on.
    @State private var pendingDownload: TipCardDownloadFormat?

    /// The brightness to put back on close — set only when this screen raised it.
    @State private var previousBrightness: CGFloat?

    /// The backdrop and Close fade in on this; removal fades the whole overlay instead.
    @State private var isRevealed = false
    /// The card's scale springs on this, separately, so it can bounce while its opacity eases with the backdrop.
    @State private var isCardShown = false

    /// The card's width, from the full-screen frame (302 of the 402pt frame).
    private static let maxCardWidth: CGFloat = 302
    private static let horizontalInset: CGFloat = 20

    /// Below this a code is hard to scan, so the screen is raised to `boostedBrightness`.
    private static let minimumScanBrightness: CGFloat = 0.4
    private static let boostedBrightness: CGFloat = 0.6

    /// The scanned-card pop from `BillCanvas` (0.55 scale, 0.4s at 0.4 damping).
    private static let revealScale: CGFloat = 0.55
    private static let revealSpring: Animation = .spring(duration: 0.4, bounce: 0.6)

    /// The open and close fade.
    static let fade: Animation = .easeOut(duration: 0.25)

    var body: some View {
        ZStack {
            Color.backgroundMain
                .ignoresSafeArea()
                .opacity(isRevealed ? 1 : 0)

            ScrollView(showsIndicators: false) {
                TipcardView(
                    size: cardSize,
                    name: card.displayName,
                    avatar: nil,
                    codeData: codeData,
                    tintOpacity: 0.36,
                    subtitle: card.username.map(\.handle)
                )
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
                .accessibilityIdentifier("profile-card-close")
                .padding(.horizontal, Self.horizontalInset)
        }
        .sheet(isPresented: $isShowingDownloadOptions, onDismiss: exportPendingDownload) {
            TipCardDownloadSheet(
                onSelect: { pendingDownload = $0; isShowingDownloadOptions = false },
                onCancel: { isShowingDownloadOptions = false }
            )
        }
        .onAppear {
            boostBrightness()
            reveal()
        }
        .onDisappear(perform: restoreBrightness)
    }

    // MARK: - Content -

    private var codeData: Data {
        TipCode.Payload(userID: card.userID).codeData()
    }

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
        .accessibilityIdentifier("profile-card-download")
    }

    /// iOS 26's glass button style insets its own label; the material fallback draws its circle
    /// directly around the frame. Matches ``CloseButton``.
    private static var platterDiameter: CGFloat {
        if #available(iOS 26, *) { 32 } else { 44 }
    }

    private var cardSize: CGSize {
        let screenWidth = UIApplication.shared.firstWindowScene?.screen.bounds.width ?? Self.maxCardWidth
        let width = min(Self.maxCardWidth, screenWidth - Self.horizontalInset * 2)
        return CGSize(width: width, height: width * TipcardView.aspectRatio)
    }

    // MARK: - Actions -

    /// Exports the format the sheet picked and hands the file to the share
    /// sheet, which is where iOS puts "Save to Files" and every other
    /// destination.
    ///
    /// Runs on the download sheet's dismissal rather than its tap: the share
    /// sheet presents on the top-most view controller, which is the download
    /// sheet itself until that dismissal finishes.
    private func exportPendingDownload() {
        guard let format = pendingDownload else { return }
        pendingDownload = nil

        guard let file = TipCardExport.file(for: format, codeData: codeData, name: card.displayName) else {
            return
        }

        ShareSheet.present(activityItems: [file]) { _ in
            // The sheet has taken its copy by now, whether or not the user went
            // through with it.
            TipCardExport.discard(file)
        }
    }

    // MARK: - Reveal -

    private func reveal() {
        Haptics.vibrate()
        withAnimation(Self.fade) { isRevealed = true }
        withAnimation(Self.revealSpring) { isCardShown = true }
    }

    // MARK: - Brightness -

    /// The card is a code someone is about to scan, so a dim screen is raised for as long as it is up.
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
