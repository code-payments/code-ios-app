//
//  YouScreen.swift
//  Flipcash
//

import SwiftUI
import UIKit
import FlipcashCore
import FlipcashUI

/// The "You" tab (Figma node 9276:4634): the user's tip card, a "Full Screen"
/// affordance, the copyable public link, the Share/Download pair, and the
/// settings list — the tab-bar entry into My Account / Advanced.
///
/// Tapping the card (or "Full Screen") expands it here on the page: everything
/// under it slides out, the tab bar hides, and the card grows into the middle of
/// the screen with a close button at the bottom. The page owns that transition —
/// nothing is pushed or presented — so the card never leaves this screen.
/// Settings rows push onto the tab's `.you` stack, so they never touch the v1
/// scanner's Settings sheet.
struct YouScreen: View {

    @Environment(SessionContainer.self) private var sessionContainer
    @Environment(AppRouter.self) private var router
    @Environment(BetaFlags.self) private var betaFlags
    @Environment(TipCardPresentation.self) private var presentation

    /// Warms the share-sheet preview image ahead of the share tap so it never
    /// lands on the tap; keyed by user.
    @State private var previewCache = TipCodePreviewCache()
    @State private var debugTapCount: Int = 0
    @State private var isShowingDownloadOptions = false

    /// The card's slot in the page's layout, in global space — where the card
    /// sits before it travels to the middle of the screen.
    @State private var cardSlotFrame: CGRect = .zero

    /// The on-screen card width, from the Figma placement: node 9276:4641 draws
    /// the You card 241.6 wide.
    private static let cardWidth: CGFloat = 242
    /// The expanded card's width, per the full-screen frame (Figma node
    /// 9277:121410 — 302 of the 402pt frame).
    private static let maxExpandedCardWidth: CGFloat = 302
    /// The page's horizontal inset, also the expanded card's minimum margin.
    private static let horizontalInset: CGFloat = 20

    private static let expansion: Animation = .spring(response: 0.45, dampingFraction: 0.85)

    private let rowInsets = EdgeInsets(top: 25, leading: 0, bottom: 25, trailing: 0)

    var body: some View {
        Background(color: .backgroundMain) {
            ZStack {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        cardSection
                            .padding(.top, 64)

                        pageContent
                            // The expanded card owns the screen: everything under
                            // it slides down and out — as the tab bar does, which
                            // `HomeTabView` hides on the same state. Opacity and
                            // offset (not removal) keep the layout stable so
                            // nothing reflows on the way back.
                            .opacity(isExpanded ? 0 : 1)
                            .offset(y: isExpanded ? 60 : 0)
                            .allowsHitTesting(!isExpanded)
                    }
                    .padding(.horizontal, Self.horizontalInset)
                }
                .scrollDisabled(isExpanded)

                if isExpanded {
                    closeButton
                        .transition(.opacity)
                }
            }
        }
        .sheet(isPresented: $isShowingDownloadOptions) {
            TipCardDownloadSheet(
                onSelect: download(as:),
                onCancel: { isShowingDownloadOptions = false }
            )
        }
        .task(id: profilePicture?.thumbnailBlobID) {
            previewCache.warm(TipCode.Payload(userID: sessionContainer.session.userID))
        }
    }

    // MARK: - Card -

    /// The card plus its "Full Screen" caption. Tapping either expands the card;
    /// tapping the expanded card puts it back.
    @ViewBuilder
    private var cardSection: some View {
        if let name = displayName {
            VStack(spacing: 24) {
                // The slot holds the card's place in the page while the card
                // itself is offset into the middle of the screen — measuring the
                // slot rather than the card keeps the measurement free of the
                // offset it feeds.
                //
                // It keeps its collapsed size throughout: a slot that grew with
                // the card would move its own centre mid-flight, and that centre
                // is what `cardOffset` measures from, so the card would jump
                // against its own travel. Fixed, the card grows about a still
                // centre and the page below never reflows.
                Color.clear
                    .frame(width: Self.collapsedCardSize.width, height: Self.collapsedCardSize.height)
                    .overlay {
                        TipcardView(
                            size: cardSize,
                            name: name,
                            avatar: nil,
                            codeData: codeData,
                            tintOpacity: 0.36
                        )
                        .offset(y: cardOffset)
                    }
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { cardSlotFrame = $0 }

                Self.caption("Full Screen", pointsUp: false)
                    .opacity(isExpanded ? 0 : 1)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: toggleExpanded)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(isExpanded ? "Close tip card" : "View tip card full screen")
            .accessibilityIdentifier("you-fullscreen-button")
        }
    }

    /// The expanded card's collapse control (Figma node 9276:4601): the same
    /// caption as "Full Screen", chevron flipped, sitting at the bottom of the
    /// screen where the tab bar was.
    private var closeButton: some View {
        VStack {
            Spacer()

            Button(action: toggleExpanded) {
                Self.caption("Close", pointsUp: true)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            .accessibilityIdentifier("you-close-fullscreen-button")
        }
        .padding(.bottom, 8)
    }

    /// The dimmed caption-and-chevron pair used both to expand the card and to
    /// put it back.
    private static func caption(_ title: String, pointsUp: Bool) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.appTextSmall)
            Image.system(.chevronDown)
                .renderingMode(.template)
                .frame(width: 16, height: 16)
                .rotationEffect(.degrees(pointsUp ? 180 : 0))
        }
        .foregroundStyle(Color.textMain)
        .opacity(0.5)
    }

    // MARK: - Page -

    /// Everything below the card — the part that clears out when the card expands.
    private var pageContent: some View {
        VStack(spacing: 0) {
            TipCardLinkRow(url: url)
                .padding(.top, 70)

            HStack(spacing: 10) {
                TipCardActionButton(asset: .shareOS, title: "Share", action: shareTipCard)
                    .accessibilityIdentifier("you-share-button")

                TipCardActionButton(asset: .fileDownload, title: "Download") {
                    isShowingDownloadOptions = true
                }
                .accessibilityIdentifier("you-download-button")
            }
            .padding(.top, 11)

            settingsList
                .padding(.top, 19)

            // v2 scrolls the version string with the content rather than
            // pinning it above the tab bar (the v1 Settings sheet pinned it).
            versionFooter
                .padding(.top, 32)
        }
    }

    // MARK: - Settings list -

    private var settingsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsRow(asset: .myAccount, title: "My Account", insets: rowInsets) {
                router.push(.settingsMyAccount)
            }
            SettingsRow(asset: .sliders, title: "Advanced", insets: rowInsets) {
                router.push(.settingsAdvancedFeatures)
            }
        }
        .font(.appDisplayXS)
        .foregroundStyle(Color.textMain)
    }

    private var versionFooter: some View {
        Button {
            handleVersionTap()
        } label: {
            Text("Version \(AppMeta.version) • Build \(AppMeta.build)")
                .lineLimit(1)
                .font(.appTextHeading)
                .foregroundStyle(Color.textSecondary)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content -

    private var isExpanded: Bool { presentation.isExpanded }

    private var profile: Profile? { sessionContainer.session.profile }
    private var profilePicture: ProfilePicture? { profile?.profilePicture }

    private var displayName: String? {
        guard let name = profile?.displayName, !name.isEmpty else { return nil }
        return name
    }

    private var codeData: Data {
        TipCode.Payload(userID: sessionContainer.session.userID).codeData()
    }

    private var url: URL { .tipcard(for: sessionContainer.session.userID) }

    // MARK: - Card geometry -

    /// The card's size in the page — also the slot's size at every point in the
    /// expansion, so the page's layout is the same expanded as collapsed.
    private static let collapsedCardSize = CGSize(
        width: cardWidth,
        height: cardWidth * TipcardView.aspectRatio
    )

    private var cardSize: CGSize {
        let width = isExpanded ? expandedCardWidth : Self.cardWidth
        return CGSize(width: width, height: width * TipcardView.aspectRatio)
    }

    /// The expanded width: the design's 302, narrowed only if the screen can't
    /// hold it inside the page's margins.
    private var expandedCardWidth: CGFloat {
        guard screenBounds.width > 0 else { return Self.maxExpandedCardWidth }
        return min(Self.maxExpandedCardWidth, screenBounds.width - Self.horizontalInset * 2)
    }

    /// The whole screen, safe areas included — what the design centres the
    /// expanded card in. Read from the window rather than a geometry proxy,
    /// which reports the safe-area rect instead; `BillOverlayView` centres the
    /// full-screen bill the same way.
    private var screenBounds: CGRect {
        UIApplication.shared.firstWindowScene?.screen.bounds ?? .zero
    }

    /// How far the card moves to sit in the middle of the screen — the gap
    /// between its slot's centre and the screen's.
    private var cardOffset: CGFloat {
        guard isExpanded, !cardSlotFrame.isEmpty, !screenBounds.isEmpty else { return 0 }
        return screenBounds.midY - cardSlotFrame.midY
    }

    // MARK: - Actions -

    private func toggleExpanded() {
        withAnimation(Self.expansion) {
            if isExpanded {
                presentation.collapse()
            } else {
                presentation.expand()
            }
        }
    }

    private var shareTitle: String {
        if let displayName { "Tip \(displayName)" } else { "My Tip Card" }
    }

    private func shareTipCard() {
        let item = TipCodeShareItem(
            url: url,
            title: shareTitle,
            preview: previewCache.preview(for: sessionContainer.session.userID)
        )
        ShareSheet.present(activityItem: item) { _ in }
    }

    /// Exports the code in `format` and hands the file to the share sheet,
    /// which is where iOS puts "Save to Files" and every other destination.
    private func download(as format: TipCardDownloadFormat) {
        isShowingDownloadOptions = false

        guard let file = TipCardExport.file(for: format, codeData: codeData, name: displayName) else {
            return
        }

        ShareSheet.present(activityItems: [file]) { _ in
            // The sheet has taken its copy by now, whether or not the user went
            // through with it.
            TipCardExport.discard(file)
        }
    }

    private func handleVersionTap() {
        if debugTapCount >= 9 {
            betaFlags.setAccessGranted(!betaFlags.accessGranted)
            debugTapCount = 0
        } else {
            debugTapCount += 1
        }
    }
}
