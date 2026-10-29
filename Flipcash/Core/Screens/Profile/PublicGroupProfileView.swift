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
    /// The group's name.
    let title: String
    /// How many members the group has, when known.
    let memberCount: UInt64?
    /// The group's bio; it isn't persisted locally, so it can arrive after the rest.
    let description: String?
    /// The avatar's bytes, once loaded.
    let avatarImageData: Data?
    /// The avatar's placeholder while its bytes load.
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
/// identity and actions, then a stack of boxes: what it takes to join and chat, who has been
/// chatting, and the footer.
///
/// Reads `\.bleedPalette`, so the caller provides it with `.bleedPalette(key:image:settings:)` on
/// this view. The view paints the page, the navigation container and the pinned bar's fade itself.
struct PublicGroupProfileView<Accessory: View, Actions: View, Footer: View, Pinned: View>: View {

    let content: PublicGroupProfileContent
    /// Whether the pinned bar has anything in it, which is when its fade belongs.
    let hasPinned: Bool
    /// The loaded avatar bytes of a person, if any.
    let portraitData: (UserID) -> Data?
    /// Loads a person's avatar.
    let loadPortrait: (GroupPortrait) async -> Void
    /// Opens a person's profile.
    let onSelectPerson: (UserID) -> Void
    /// Opens a token's info page.
    let onToken: (PublicGroupToken) -> Void
    /// Sits beside the avatar, such as the chat's mute status.
    @ViewBuilder let accessory: () -> Accessory
    /// The outline pills under the bio.
    @ViewBuilder let actions: () -> Actions
    /// Whether ``footer`` has anything in it, which is when its box and the gap above it belong.
    let hasFooter: Bool
    /// The action under the boxes that closes the stack, such as Leave Chat.
    @ViewBuilder let footer: () -> Footer
    /// The bar pinned under the scroll.
    @ViewBuilder let pinned: () -> Pinned

    @Environment(\.bleedPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The status and navigation bars' height, which the cover runs under.
    @State private var topInset: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                identity

                if hasBoxes {
                    VStack(spacing: 0) {
                        if hasCards {
                            VStack(spacing: PublicGroupLook.cardGap) {
                                if !content.requirements.isEmpty {
                                    PublicGroupRequirementsView(
                                        tiles: content.requirements,
                                        yourBalance: content.yourBalance,
                                        onToken: onToken
                                    )
                                }

                                if let pulse = content.pulse {
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
                        }

                        if hasFooter {
                            footer()
                                .padding(.top, hasCards ? PublicGroupLook.leaveGap : 0)
                        }
                    }
                    .padding(.horizontal, PublicGroupLook.sideMargin)
                    .padding(.top, PublicGroupLook.identityToCards)
                }
            }
            // Negative pulls the identity up under the bar; the cover hangs from the scroll's top,
            // so it stays put either way.
            .padding(.top, PublicGroupLook.contentOffset)
            .padding(.bottom, 24)
            // On the whole column, so a bio that arrives late moves the sections with the pills.
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: content.description)
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

    private var hasBoxes: Bool {
        hasCards || hasFooter
    }

    /// Whether the requirements or the pulse card show, the boxes ``footer`` sits under.
    private var hasCards: Bool {
        !content.requirements.isEmpty || content.pulse != nil
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
            // Grows upward from its bottom edge when the scroll view is pulled past its top, as
            // `ProfileCoverBanner` does, the fade riding along. The lift under the bars is in the
            // same effect: an `.offset` after it stops the effect following the scroll.
            .visualEffect { [topInset] content, proxy in
                let overscroll = max(0, proxy.frame(in: .scrollView).minY)
                let height = max(proxy.size.height, 1)
                return content
                    .scaleEffect((height + overscroll) / height, anchor: .bottom)
                    .offset(y: -topInset)
            }
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
                .padding(avatarRing)
                .background(palette.background, in: Circle())

                accessory()

                Spacer(minLength: 0)
            }

            Text(content.title)
                .font(.appTitleLarge)
                .foregroundStyle(palette.primaryText)
                .multilineTextAlignment(.leading)
                .padding(.top, PublicGroupLook.avatarToName)
                .accessibilityIdentifier("profile-name")

            Text(PublicGroupCopy.summary(memberCount: content.memberCount))
                .font(.appTextSmall)
                .foregroundStyle(palette.secondaryStyle)
                .padding(.top, PublicGroupLook.nameToMeta)

            if let description = content.description, !description.isEmpty {
                Text(description)
                    .font(.appTextMessage)
                    .foregroundStyle(palette.primaryText)
                    .multilineTextAlignment(.leading)
                    .padding(.top, PublicGroupLook.metaToBio)
                    .transition(.opacity)
                    .accessibilityIdentifier("profile-bio")
            }

            HStack(spacing: 12) {
                actions()
            }
            .padding(.top, PublicGroupLook.bioToActions)
        }
        .padding(.horizontal, PublicGroupLook.sideMargin)
    }

    private static var avatarSize: CGFloat { 72 }
    /// The ring of page color around the avatar, which keeps it apart from the cover behind it.
    private var avatarRing: CGFloat {
        PublicGroupLook.avatarStroke ? PublicGroupLook.avatarStrokeWidth : 0
    }
}

// MARK: - Buttons -

/// The press every public-group control shares: a small scale, or a dim under Reduce Motion, with
/// the haptic on touch-down.
private struct PublicGroupPress: ViewModifier {

    let isPressed: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            // Scoped to the press itself, so a state change that lands as the finger lifts snaps.
            .animation(.spring(duration: 0.2, bounce: 0)) { content in
                content
                    .scaleEffect(!reduceMotion && isPressed ? Self.scale : 1)
                    .opacity(reduceMotion && isPressed ? 0.7 : 1)
            }
            .onChange(of: isPressed) { _, isPressed in
                if isPressed { Haptics.soft() }
            }
    }

    /// How far a pressed control shrinks.
    private static let scale: CGFloat = 0.96
}

/// The outline pill under the bio: a rounded rectangle, a capsule at its default radius, stroked in
/// the palette's secondary color.
struct PublicGroupOutlineButtonStyle: ButtonStyle {

    private static var shape: RoundedRectangle { .rect(cornerRadius: PublicGroupLook.pillRadius) }

    @Environment(\.bleedPalette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.appTextMedium)
            .foregroundStyle(palette.secondaryStyle)
            .padding(.horizontal, 24)
            .frame(minHeight: Metrics.buttonHeightThin)
            .overlay { Self.shape.strokeBorder(palette.secondaryStyle, lineWidth: 1.5) }
            .contentShape(Self.shape)
            .modifier(PublicGroupPress(isPressed: configuration.isPressed))
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
            .modifier(PublicGroupPress(isPressed: configuration.isPressed))
    }

    /// The capsule's height, matching the amount screen's action button.
    static var height: CGFloat { 54 }

    /// The side inset of the pinned bar, matching the amount screen's action button.
    static var sideInset: CGFloat { 32 }
}

/// The action that closes the stack, such as Leave Chat: a full-width capsule on the cards'
/// surface, as tall as Open Chat, its label in the palette's own control color.
struct PublicGroupClosingButtonStyle: ButtonStyle {

    @Environment(\.bleedPalette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.appTextMedium)
            .foregroundStyle(labelStyle)
            .tint(labelStyle)
            .frame(maxWidth: .infinity)
            .frame(height: PublicGroupCapsuleButtonStyle.height)
            .background(palette.controlTint, in: Capsule())
            .contentShape(Capsule())
            .modifier(PublicGroupPress(isPressed: configuration.isPressed))
    }

    private var labelStyle: AnyShapeStyle {
        PublicGroupLook.leaveLabelIsWhite ? AnyShapeStyle(palette.controlLabel) : palette.controlSecondaryStyle
    }
}

/// The press of a tappable row or face with no chrome of its own.
struct PublicGroupDimButtonStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(PublicGroupPress(isPressed: configuration.isPressed))
    }
}

/// A hairline in the palette's divider color, one device pixel thick.
struct PublicGroupHairline: View {

    @Environment(\.bleedPalette) private var palette
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(palette.hairline)
            .frame(height: 1 / displayScale)
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
                hasFooter: true,
                footer: {
                    Button("Leave Chat") {}
                        .buttonStyle(PublicGroupClosingButtonStyle())
                },
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
