//
//  YouScreen.swift
//  Flipcash
//

import SwiftUI
import UIKit
import FlipcashCore
import FlipcashUI

/// The "You" tab: the user's own profile — cover, avatar, name, handle and bio — with the stats
/// card.
///
/// The navigation bar carries the gear that pushes Settings; the action row beside the
/// avatar carries Edit Profile and Share, whose sheet shares the profile link, presents the tip card
/// full screen (`ProfileCardScreen`), or copies the link. Settings pushes onto the tab's `.you`
/// stack, so it never touches the v1 scanner's Settings sheet.
///
/// A profile with no display name has no card: the page then shows the add-your-name invitation
/// in place of the name block and drops Share, but still renders — the gear is this account's only
/// way to reach Settings, and with it Log Out.
struct YouScreen: View {

    @Environment(SessionContainer.self) private var sessionContainer
    @Environment(AppRouter.self) private var router
    @Environment(RatesController.self) private var ratesController
    @Environment(ToastController.self) private var toasts

    /// Warms the share-sheet preview image ahead of the share tap so it never
    /// lands on the tap; keyed by user.
    @State private var previewCache = TipCodePreviewCache()

    /// The balance gate, raised when the claim row is tapped below the minimum.
    @State private var usernameDialog: DialogItem?

    @State private var isShowingShare = false
    @State private var shareChoice: ProfileShareChoice?

    /// The gap the page keeps between its last row and the tab bar.
    private static let tabBarGap: CGFloat = 24

    /// Bottom inset for the scrolling content. Mirrors `WalletScreen`: the iOS 26
    /// tab bar sits in the safe area, so the gap is the whole inset there; the
    /// legacy pill floats over the content and has to be cleared on top of it,
    /// or the footer's last scroll position lands underneath it.
    private var bottomContentInset: CGFloat {
        if #available(iOS 26, *) {
            return Self.tabBarGap
        }
        return Self.tabBarGap + HomeTabView.legacyPillClearance
    }

    var body: some View {
        Background(color: .backgroundMain) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    header

                    if displayName == nil {
                        setupPrompt
                            .padding(.top, 24)
                            .padding(.horizontal, ProfileHeaderView<EmptyView, EmptyView, EmptyView>.inset)
                    } else {
                        ProfileStatsCard(
                            minimumToChat: StartChattingFee.amount(
                                for: profile,
                                session: sessionContainer.session,
                                ratesController: ratesController
                            ),
                            joinedAt: profile?.joinedAt
                        )
                        .padding(.top, 19)
                    }
                }
                .padding(.bottom, bottomContentInset)
            }
            // The banner runs under the status bar.
            .ignoresSafeArea(edges: .top)
            // The blur only belongs once the banner has scrolled up under the bar.
            .hidesTopScrollEdge(untilOffset: ProfileCoverBanner<EmptyView>.height / 2)
        }
        // The system bar carries the gear and, on iOS 26, the soft edge the banner scrolls under.
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                settingsGear
            }
        }
        .fullScreenCover(isPresented: Bindable(router).isShowingProfileCard) {
            ProfileCardScreen()
        }
        .task(id: profilePicture?.thumbnailBlobID) {
            // There is no card to share, and so no preview worth rendering, until
            // the profile has a name. Warmed before the avatar download so a slow
            // network cannot hold it back.
            if displayName != nil {
                previewCache.warm(TipCode.Payload(userID: sessionContainer.session.userID))
            }
            await sessionContainer.profileAvatars.load(userID: sessionContainer.session.userID, picture: profilePicture)
        }
        // A cash link raises the bill without touching the router, and it would draw under the card.
        .onChange(of: sessionContainer.session.isShowingBill) { _, isShowing in
            if isShowing { router.isShowingProfileCard = false }
        }
        .dialog(item: $usernameDialog)
        .sheet(isPresented: $isShowingShare, onDismiss: handleShareChoice) {
            ProfileShareSheet(subtitle: shareSubtitle, offersCard: true) { shareChoice = $0 }
        }
    }

    // MARK: - Header -

    private var header: some View {
        ProfileHeaderView(
            userID: sessionContainer.session.userID,
            displayName: displayName,
            handle: username.map(\.handle),
            bio: profile?.bio,
            avatarData: sessionContainer.profileAvatars.data(for: sessionContainer.session.userID),
            avatarBlurhash: profilePicture?.thumbnailBlurhash,
            coverPicture: profile?.coverPicture,
            bannerControls: { EmptyView() },
            rowActions: {
                ProfileEditCapsule {
                    router.push(.editProfile)
                }
                .accessibilityIdentifier("you-edit-profile")

                if displayName != nil {
                    shareButton
                }
            },
            underHandle: {
                if shouldPromptForUsername {
                    Button(action: claimUsername) {
                        Text("Claim your username ›")
                            .font(.appTextSmall)
                            .foregroundStyle(Color.textMain)
                            .frame(minHeight: 22)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("you-claim-username")
                }
            }
        )
    }

    private var shareButton: some View {
        ProfileActionCircle(image: Image.asset(.shareOS)) {
            isShowingShare = true
        }
        .accessibilityLabel("Share")
        .accessibilityIdentifier("you-share")
    }

    private var settingsGear: some View {
        Button {
            router.push(.settings)
        } label: {
            Image(systemName: "gearshape")
        }
        .accessibilityLabel("Settings")
        .accessibilityIdentifier("you-settings")
    }

    // MARK: - No name -

    /// Stands in for the name block until the profile has a display name: the card the
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
                size: Self.placeholderCardSize,
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
            .frame(maxWidth: Self.placeholderCardSize.width - 16)
        }
    }

    /// Fills the blurred placeholder card's name line. Long enough to occupy the
    /// line the real name will, short enough not to wrap.
    private static let placeholderName = "Your Name"

    /// The placeholder card's outline, matching `TipcardView`'s own corner
    /// rounding — which it derives from the card's width.
    private static let placeholderShape = RoundedRectangle(
        cornerRadius: placeholderCardSize.width * 0.08,
        style: .continuous
    )

    /// The placeholder card's size, which gives the blur a card shaped like the one the user gets.
    private static let placeholderCardSize = CGSize(
        width: 242,
        height: 242 * TipcardView.aspectRatio
    )

    // MARK: - Username claim -

    /// The balance's standing against the username minimum. Read once per
    /// render and switched on here rather than re-derived at tap time.
    private var usernameProgress: UsernameGate {
        usernameGate(
            session: sessionContainer.session,
            minimum: sessionContainer.session.userFlags?.usernameMinBalance
        )
    }

    // MARK: - Content -

    private var profile: Profile? { sessionContainer.session.profile }
    private var profilePicture: ProfilePicture? { profile?.profilePicture }

    private var displayName: String? {
        guard let name = profile?.displayName, !name.isEmpty else { return nil }
        return name
    }

    private var username: Username? { profile?.username }

    /// Whether to offer the handle: the user has none, or the one they have was
    /// auto-assigned by the server and they haven't picked their own. Re-derived
    /// from the profile on every render, so a handle that disappears across a
    /// refresh puts the offer back on its own.
    private var shouldPromptForUsername: Bool {
        usernameNeedsClaim(
            username: username,
            isAutoAssigned: profile?.isUsernameAutoAssigned == true
        )
    }

    private var codeData: Data {
        TipCode.Payload(userID: sessionContainer.session.userID).codeData()
    }

    private var shareSubtitle: String? {
        guard let displayName else { return nil }
        return [displayName, username?.handle].compactMap { $0 }.joined(separator: " · ")
    }

    private var url: URL { .tipcard(for: sessionContainer.session.userID, username: username) }

    // MARK: - Actions -

    private func shareTipCard() {
        let item = TipCodeShareItem.profile(
            url: url,
            displayName: displayName,
            preview: previewCache.preview(for: sessionContainer.session.userID)
        )
        ShareSheet.present(activityItem: item) { _ in }
    }

    private func handleShareChoice() {
        defer { shareChoice = nil }
        switch shareChoice {
        case .share:    shareTipCard()
        case .showCard: router.isShowingProfileCard = true
        case .copyLink: copyLink()
        case nil:       break
        }
    }

    private func copyLink() {
        UIPasteboard.general.string = url.absoluteString
        toasts.show(.init("Copied", systemImage: "checkmark.circle.fill", duration: .seconds(2)))
    }

    /// Opens the claim screen once the balance clears the minimum, and the
    /// balance gate until then.
    private func claimUsername() {
        switch usernameProgress {
        case .proceed:
            router.push(.username(username))
        case .addMoney(let minimum, _, _):
            presentBalanceGate(minimum: minimum)
        }
    }

    /// Names the minimum and offers the way to meet it. The row draws no
    /// shortfall, so the dialog is where the squatting rule gets stated.
    private func presentBalanceGate(minimum: FiatAmount) {
        usernameDialog = .usernameMinimumBalance(minimum: minimum) {
            router.presentAddMoney(.general, source: .usernameShortfall)
        }
    }
}
