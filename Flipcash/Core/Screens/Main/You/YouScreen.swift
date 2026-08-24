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
///
/// A profile with no display name has no card: the page then shows the
/// add-your-name invitation in the card's place and drops the link and share
/// affordances, but still renders — the settings rows are this account's only
/// way to reach My Account, and with it Log Out.
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

    /// The format tapped in the download sheet, held until the sheet is gone so
    /// the share sheet has a settled controller to present on.
    @State private var pendingDownload: TipCardDownloadFormat?

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
        .sheet(isPresented: $isShowingDownloadOptions, onDismiss: exportPendingDownload) {
            TipCardDownloadSheet(
                onSelect: { pendingDownload = $0; isShowingDownloadOptions = false },
                onCancel: { isShowingDownloadOptions = false }
            )
        }
        .task(id: profilePicture?.thumbnailBlobID) {
            // There is no card to share, and so no preview worth rendering, until
            // the profile has a name.
            guard displayName != nil else { return }
            previewCache.warm(TipCode.Payload(userID: sessionContainer.session.userID))
        }
    }

    // MARK: - Card -

    /// The card plus its "Full Screen" caption. Tapping either expands the card;
    /// tapping the expanded card puts it back.
    ///
    /// A profile without a display name has no card to draw, so the slot carries
    /// the invitation to add one instead. The rest of the page stays where it is
    /// either way — settings included, which is the only route to logging out.
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
                            size: Self.drawnCardSize,
                            name: name,
                            avatar: nil,
                            codeData: codeData,
                            tintOpacity: 0.36
                        )
                        .scaleEffect(cardScale)
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
        } else {
            setupPrompt
        }
    }

    /// Stands in for the card until the profile has a display name: the card the
    /// user is about to get, blurred out behind the invitation to claim it, so
    /// the slot shows what is on offer rather than sitting empty.
    ///
    /// "Get Started" opens the name editor, which pops back here on save — by
    /// which point the profile is tippable and the real card has taken this slot.
    private var setupPrompt: some View {
        ZStack {
            // A stand-in name, never read: it only has to give the blur a card
            // shaped like the one the user gets.
            TipcardView(
                size: Self.collapsedCardSize,
                name: Self.placeholderName,
                avatar: nil,
                codeData: codeData,
                // The card's own tint is black over a frosted backdrop, which
                // on this black page paints black on black — it can only take
                // brightness away from the base below, so it takes none.
                tintOpacity: 0
            )
            // The base the card is missing: without it the stand-in has no
            // surface, just a code glowing in the dark.
            .background(Self.placeholderShape.fill(Color.white.opacity(0.08)))
            .blur(radius: 12)
            // Blur bleeds past the card's edge and, on a black page, a card
            // whose edge has dissolved is just a smudge — so clip the softened
            // content back to the card's own outline and draw that outline.
            .clipShape(Self.placeholderShape)
            .overlay {
                Self.placeholderShape.strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            }
            .accessibilityHidden(true)

            // Word for word the Chats tab's own name-less state
            // (`TipsScreen.TipsIntroScreen`): the same account hits both, and
            // two different asks for the one thing read as two different jobs.
            VStack(spacing: 0) {
                Text("Receive Tips From Everyone")
                    .font(.appTextLarge)
                    .foregroundStyle(Color.textMain)
                    .multilineTextAlignment(.center)

                // Full strength where the Chats tab uses secondary grey: this
                // copy sits over the blurred code's brightest patch, and grey
                // on that glow is the one line you can't read.
                Text("Add your name to receive tips")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textMain)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)

                BubbleButton(text: "Start Receiving Tips") {
                    router.push(.changeDisplayName)
                }
                .padding(.top, 20)
                .accessibilityIdentifier("you-start-receiving-tips-button")
            }
            // Held inside the card it sits on, so the copy reads as part of the
            // card rather than spilling past its edges.
            .frame(maxWidth: Self.collapsedCardSize.width - 16)
        }
    }

    /// Fills the blurred placeholder card's name line. Long enough to occupy the
    /// line the real name will, short enough not to wrap.
    private static let placeholderName = "Your Name"

    /// The placeholder card's outline, matching `TipcardView`'s own corner
    /// rounding — which it derives from the card's width.
    private static let placeholderShape = RoundedRectangle(
        cornerRadius: collapsedCardSize.width * 0.08,
        style: .continuous
    )

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
    ///
    /// The link and the Share/Download pair all address a card that a name-less
    /// profile does not have, so they sit out until it does; the settings rows
    /// take up the slack.
    private var pageContent: some View {
        VStack(spacing: 0) {
            if displayName != nil {
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
            }

            settingsList
                .padding(.top, displayName == nil ? 48 : 19)

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

    /// The size the card is always drawn at, whatever it currently measures on
    /// screen — the widest it ever gets, so scaling it to size only ever
    /// samples the drawing down.
    private static let drawnCardSize = CGSize(
        width: maxExpandedCardWidth,
        height: maxExpandedCardWidth * TipcardView.aspectRatio
    )

    /// The expansion runs as one scale on the drawn card rather than a new size
    /// for it to lay itself out at. Laid out, each of the card's metrics is a
    /// separate animatable value — and the name's font size is not animatable
    /// at all — so the parts arrived at their new sizes at different moments
    /// and overlapped mid-flight. Scaled, the card travels as one figure.
    private var cardScale: CGFloat {
        (isExpanded ? expandedCardWidth : Self.cardWidth) / Self.drawnCardSize.width
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
