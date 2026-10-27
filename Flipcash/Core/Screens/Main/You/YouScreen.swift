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
/// avatar carries Edit Profile and Share. Share opens the ``ShareToChatsSheet`` every profile shares
/// through, whose Show Profile Card tile draws the tip card over it. Settings pushes onto the tab's
/// `.you` stack, so it never touches the v1 scanner's Settings sheet.
///
/// A profile with no display name has no card: the page then shows the add-your-name invitation
/// in place of the name block and drops Share, but still renders — the gear is this account's only
/// way to reach Settings, and with it Log Out.
struct YouScreen: View {

    @Environment(SessionContainer.self) private var sessionContainer
    @Environment(AppRouter.self) private var router
    @Environment(UpdateAvailability.self) private var updateAvailability
    @Environment(RatesController.self) private var ratesController
    @Environment(ConversationController.self) private var conversationController

    /// Warms the share-sheet preview image ahead of the share tap so it never
    /// lands on the tap; keyed by user.
    @State private var previewCache = TipCodePreviewCache()

    @State private var isSharingToChats = false

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
                            .padding(.horizontal, ProfileHeaderMetrics.inset)
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

                        FeaturedGroupsSection(
                            groups: sessionContainer.featuredGroups.groups,
                            showsEmptyState: FeaturedGroupsSection.ownProfileShowsEmptyState(
                                hasUsername: username != nil,
                                isLoaded: sessionContainer.featuredGroups.isLoaded
                            )
                        ) { id in
                            if let group = sessionContainer.featuredGroups.group(withID: id) {
                                conversationController.hold(group)
                            }
                            router.push(.chatProfile(id, origin: .featuredGroup))
                        }
                        .padding(.top, 20)
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
        .task(id: profilePicture?.thumbnailBlobID) {
            // There is no card to share, and so no preview worth rendering, until
            // the profile has a name. Warmed before the avatar download so a slow
            // network cannot hold it back.
            if displayName != nil {
                previewCache.warm(TipCode.Payload(userID: sessionContainer.session.userID))
            }
            await sessionContainer.profileAvatars.load(userID: sessionContainer.session.userID, picture: profilePicture)
        }
        .task(id: username) {
            guard let username else { return }
            await sessionContainer.featuredGroups.load(username: username)
        }
        .fullScreenCover(isPresented: $isSharingToChats) {
            ShareToChatsSheet(
                subject: .user(
                    userID: sessionContainer.session.userID,
                    username: username,
                    displayName: displayName,
                    preview: previewCache.preview(for: sessionContainer.session.userID),
                    directChatID: nil
                ),
                isPresented: $isSharingToChats
            ) { chatID in
                router.openSharedChat(chatID)
            }
        }
    }

    // MARK: - Header -

    private var header: some View {
        ProfileHeaderView(
            cover: .user(sessionContainer.session.userID, picture: profile?.coverPicture),
            title: displayName,
            subtitle: username.map(\.handle),
            bodyText: profile?.bio,
            avatar: {
                ProfileHeaderAvatar(
                    id: sessionContainer.session.userID.uuidString,
                    displayName: displayName ?? "",
                    imageData: sessionContainer.profileAvatars.data(for: sessionContainer.session.userID),
                    blurhash: profilePicture?.thumbnailBlurhash
                )
            },
            bannerControls: { EmptyView() },
            coverAccessory: { EmptyView() },
            rowActions: {
                ProfileEditCapsule(
                    title: editButton.title,
                    isAccented: editButton.isAccented
                ) {
                    router.push(.editProfile)
                }
                .accessibilityIdentifier("you-edit-profile")

                if displayName != nil {
                    shareButton
                }
            },
            underSubtitle: { EmptyView() }
        )
    }

    private var editButton: EditProfileButtonState {
        EditProfileButtonState(isProfileComplete: profile?.isComplete == true)
    }

    private var shareButton: some View {
        ProfileActionCircle(image: Image.asset(.shareOS)) {
            isSharingToChats = true
        }
        .accessibilityLabel("Share")
        .accessibilityIdentifier("you-share")
    }

    private var showsUpdateDot: Bool {
        SettingsVersionCardState(
            newerVersion: updateAvailability.newerVersion,
            isDebugBuild: SettingsVersionCardState.isDebugBuild,
            channel: updateAvailability.channel,
            installedBuild: updateAvailability.installedBuild,
            latestTestFlightBuild: updateAvailability.latestTestFlightBuild,
            isStaff: sessionContainer.session.isStaff
        ).showsGearDot
    }

    private var settingsGear: some View {
        Button {
            router.push(.settings)
        } label: {
            Image(systemName: "gearshape")
                .notificationDot(showsUpdateDot)
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

    // MARK: - Content -

    private var profile: Profile? { sessionContainer.session.profile }
    private var profilePicture: ProfilePicture? { profile?.profilePicture }

    private var displayName: String? {
        guard let name = profile?.displayName, !name.isEmpty else { return nil }
        return name
    }

    private var username: Username? { profile?.username }

    private var codeData: Data {
        TipCode.Payload(userID: sessionContainer.session.userID).codeData()
    }
}

/// The label and style of the You tab's edit button for a profile's completeness.
struct EditProfileButtonState: Equatable {

    /// "Complete Your Profile" until the profile is complete, then "Edit Profile".
    let title: String
    /// Whether the button takes the accent fill rather than today's gray capsule.
    let isAccented: Bool

    /// The state for a profile that is, or is not yet, complete (see `Profile.isComplete`).
    init(isProfileComplete: Bool) {
        title = isProfileComplete ? "Edit Profile" : "Complete Your Profile"
        isAccented = !isProfileComplete
    }
}
