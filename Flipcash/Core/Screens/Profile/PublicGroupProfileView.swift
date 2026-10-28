//
//  PublicGroupProfileView.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// Everything a public group's profile draws, as plain values.
struct PublicGroupProfileContent {

    /// Identifies the group for its monogram.
    let id: String
    let title: String
    let memberCount: UInt64?
    /// The group's bio; it isn't persisted locally, so it can arrive after the rest.
    let description: String?
    let avatarImageData: Data?
    let avatarBlurhash: String?
    /// The cover drawn at the top; `nil` when the page is colored from the avatar instead.
    let cover: UIImage?
    /// The requirements card's tiles; empty hides the section.
    let requirements: [PublicGroupRequirementTile]
    /// What the viewer holds toward the rule, stated for the card's footer.
    let yourBalance: String?
    /// The pulse card; `nil` hides the section.
    let pulse: PublicGroupPulse?
    /// The group's host, when the chatter sample names them.
    let host: GroupPortrait?
}

/// A public group's profile: its cover melting into a page of the cover's own color, the group's
/// identity and actions, what it takes to join and chat, and who has been chatting.
///
/// Reads `\.bleedPalette`, so the caller provides it with `.bleedPalette(key:image:settings:)` on
/// this view. The view paints the page, the navigation container and the pinned bar's fade itself.
struct PublicGroupProfileView<Accessory: View, Actions: View, Footer: View, Pinned: View>: View {

    let content: PublicGroupProfileContent
    /// Whether the pinned bar has anything in it, which is when its fade belongs.
    let hasPinned: Bool
    let portraitData: (UserID) -> Data?
    let loadPortrait: (GroupPortrait) async -> Void
    let onSelectPerson: (UserID) -> Void
    let onToken: (PublicGroupToken) -> Void
    /// Sits beside the avatar, such as the chat's mute status.
    @ViewBuilder let accessory: () -> Accessory
    /// The outline pills under the bio.
    @ViewBuilder let actions: () -> Actions
    /// Ends the scroll, such as Leave Chat.
    @ViewBuilder let footer: () -> Footer
    /// The bar pinned under the scroll.
    @ViewBuilder let pinned: () -> Pinned

    @Environment(\.bleedPalette) private var palette

    /// The status and navigation bars' height, which the cover runs under.
    @State private var topInset: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                identity

                if !content.requirements.isEmpty {
                    section("Requirements") {
                        PublicGroupRequirementsView(
                            tiles: content.requirements,
                            yourBalance: content.yourBalance,
                            onToken: onToken
                        )
                    }
                }

                if let pulse = content.pulse {
                    section("Chatting recently") {
                        PublicGroupPulseCard(
                            pulse: pulse,
                            host: content.host,
                            memberCount: content.memberCount,
                            portraitData: portraitData,
                            loadPortrait: loadPortrait,
                            onSelect: onSelectPerson
                        )
                    }
                }

                footer()
                    .padding(.top, 8)
            }
            .padding(.top, 4)
            .padding(.bottom, 24)
            .background(alignment: .top) { cover }
        }
        .scrollIndicators(.hidden)
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { topInset = $0 }
        .background { palette.background.ignoresSafeArea() }
        // The cover runs under the bar, so the edge effect only belongs once it has scrolled away.
        .hidesTopScrollEdge(untilOffset: PublicGroupLook.coverHeight / 2)
        .scrollEdgeBar(.bottom) {
            pinned()
                .background { pinnedFade }
        }
        .containerBackground(palette.background, for: .navigation)
        .toolbarColorScheme(palette.colorScheme, for: .navigationBar)
    }

    // MARK: - Cover -

    private var cover: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: PublicGroupLook.coverHeight)
            .overlay { coverImage }
            .clipped()
            // After the clip, so the color runs a little past the cover's edges and no hairline of
            // the cover shows at the seam.
            .overlay(alignment: .bottom) {
                BleedFade(color: palette.background, height: min(PublicGroupLook.fadeHeight, PublicGroupLook.coverHeight))
            }
            .offset(y: -topInset)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("profile-cover")
    }

    @ViewBuilder
    private var coverImage: some View {
        if let cover = content.cover {
            Image(uiImage: cover)
                .resizable()
                .scaledToFill()
        } else if palette.isResolved {
            RadialGradient(
                colors: [palette.controlTint, palette.controlTint.opacity(0)],
                center: PublicGroupLook.glowCenter,
                startRadius: 0,
                endRadius: PublicGroupLook.glowRadius
            )
        }
    }

    /// On iOS 26 the system's edge effect fades the content; before it, the page's color does.
    @ViewBuilder
    private var pinnedFade: some View {
        if #unavailable(iOS 26.0), hasPinned {
            LinearGradient(
                gradient: ChatFade.gradient(palette.background),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
        }
    }

    // MARK: - Identity -

    private var identity: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 12) {
                ContactAvatarView(
                    id: content.id,
                    displayName: content.title,
                    imageData: content.avatarImageData,
                    blurhash: content.avatarBlurhash,
                    size: Self.avatarSize
                )
                .padding(Self.avatarRing)
                .background(palette.background, in: Circle())

                accessory()

                Spacer(minLength: 0)
            }

            Text(content.title)
                .font(.appTitleLarge)
                .foregroundStyle(palette.primaryText)
                .multilineTextAlignment(.leading)
                .padding(.top, 12)
                .accessibilityIdentifier("profile-name")

            Text(PublicGroupCopy.summary(memberCount: content.memberCount))
                .font(.appTextSmall)
                .foregroundStyle(palette.secondaryStyle)
                .padding(.top, 4)

            if let description = content.description, !description.isEmpty {
                Text(description)
                    .font(.appTextMessage)
                    .foregroundStyle(palette.primaryText)
                    .multilineTextAlignment(.leading)
                    .padding(.top, 8)
                    .transition(.opacity)
                    .accessibilityIdentifier("profile-bio")
            }

            HStack(spacing: 12) {
                actions()
            }
            .padding(.top, 16)
        }
        .animation(.easeOut(duration: 0.2), value: content.description)
        .padding(.horizontal, Self.inset)
    }

    private func section(_ title: String, @ViewBuilder card: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.appTextSmall)
                .foregroundStyle(palette.secondaryStyle)
                .accessibilityAddTraits(.isHeader)
            card()
        }
        .padding(.horizontal, Self.inset)
        .padding(.top, 16)
    }

    /// The side inset the page sits on.
    static var inset: CGFloat { 20 }
    private static var avatarSize: CGFloat { 72 }
    private static var avatarRing: CGFloat { 3 }
}

// MARK: - Buttons -

/// The outline pill under the bio: a capsule stroked in the palette's secondary color.
struct PublicGroupOutlineButtonStyle: ButtonStyle {

    @Environment(\.bleedPalette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.appTextMedium)
            .foregroundStyle(palette.secondaryStyle)
            .padding(.horizontal, 24)
            .frame(height: Metrics.buttonHeightThin)
            .overlay { Capsule().strokeBorder(palette.secondaryStyle, lineWidth: 1.5) }
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// The pinned Open Chat button: a full-width white capsule.
struct PublicGroupCapsuleButtonStyle: ButtonStyle {

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.appTextMedium)
            .foregroundStyle(isEnabled ? Color.textAction : Color.textMain.opacity(0.2))
            .frame(maxWidth: .infinity)
            .frame(height: Self.height)
            .background(isEnabled ? Color.action : Color.action.opacity(0.1), in: Capsule())
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }

    /// The capsule's height, matching the amount screen's action button.
    static var height: CGFloat { 54 }

    /// The side inset of the pinned bar, matching the amount screen's action button.
    static var sideInset: CGFloat { 32 }
}

/// A press that dims its label, for a tappable row or face with no chrome of its own.
struct PublicGroupDimButtonStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Preview -

#if DEBUG
private extension PublicGroupProfileContent {

    static let blurhash = "LGF5]+Yk^6#M@-5c,1J5@[or[Q6."

    static func sample(cover: UIImage?, split: Bool, quiet: Bool) -> PublicGroupProfileContent {
        let now = Date.now
        let jeffy = PublicGroupToken(mint: .usdf, name: "Jeffy", imageURL: nil)
        let names = ["Ted Livingston", "Brandon", "Ben", "Grampa", "Telzénar", "WanliGold", "Mia"]
        let chatters = names.enumerated().map { index, name in
            SampledChatter(
                userID: UUID(),
                profile: Profile(displayName: name, phone: Phone?.none, email: nil),
                lastSentAt: quiet ? now.addingTimeInterval(-12 * 24 * 60 * 60) : now.addingTimeInterval(-Double(index + 1) * 120),
                isCreator: index == 0
            )
        }
        return PublicGroupProfileContent(
            id: "preview",
            title: "Flipcash Product Feedback",
            memberCount: 22,
            description: "Something look off? Not work? Crash? Post it here for the team to be aware.",
            avatarImageData: nil,
            avatarBlurhash: blurhash,
            cover: cover,
            requirements: split
                ? [
                    PublicGroupRequirementTile(purpose: .join, amount: "$50", token: jeffy),
                    PublicGroupRequirementTile(purpose: .chat, amount: "$100", token: jeffy),
                ]
                : [PublicGroupRequirementTile(purpose: .joinAndChat, amount: "$100", token: jeffy)],
            yourBalance: "$382.84 of Jeffy",
            pulse: PublicGroupPulse(chatters: chatters, now: now),
            host: chatters.first.map(GroupPortrait.init)
        )
    }
}

private struct PublicGroupProfilePreview: View {

    let hasCover: Bool
    let split: Bool
    let quiet: Bool

    var body: some View {
        let image = BlurHashCache.shared.image(for: PublicGroupProfileContent.blurhash, width: 32, height: 32)
        NavigationStack {
            PublicGroupProfileView(
                content: .sample(cover: hasCover ? image : nil, split: split, quiet: quiet),
                hasPinned: true,
                portraitData: { _ in nil },
                loadPortrait: { _ in },
                onSelectPerson: { _ in },
                onToken: { _ in },
                accessory: { EmptyView() },
                actions: {
                    Button("Share") {}
                        .buttonStyle(PublicGroupOutlineButtonStyle())
                },
                footer: { EmptyView() },
                pinned: {
                    Button("Open Chat") {}
                        .buttonStyle(PublicGroupCapsuleButtonStyle())
                        .padding(.horizontal, PublicGroupCapsuleButtonStyle.sideInset)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                }
            )
            .bleedPalette(key: "preview-\(hasCover)", image: image, settings: PublicGroupLook.settings)
        }
        .preferredColorScheme(.dark)
    }
}

#Preview("Cover, busy") {
    PublicGroupProfilePreview(hasCover: true, split: false, quiet: false)
}

#Preview("Avatar colored, split, quiet") {
    PublicGroupProfilePreview(hasCover: false, split: true, quiet: true)
}
#endif
