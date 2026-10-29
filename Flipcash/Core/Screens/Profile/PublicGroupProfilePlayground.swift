//
//  PublicGroupProfilePlayground.swift
//  Flipcash
//

#if DEBUG // LOCAL-TUNER: the public group profile playground, a local feel tool
import SwiftUI
import FlipcashCore
import FlipcashUI

/// The Beta Features entry that opens the public group profile playground.
struct PublicGroupProfilePlaygroundEntry: View {

    var body: some View {
        VStack(spacing: 0) {
            SettingsSectionHeader("Profile Playground")
            NavigationLink {
                PublicGroupProfilePlayground()
            } label: {
                PlaygroundRow(title: "Public group profile playground")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("public-group-profile-playground")
        }
    }
}

/// Every state of the public group profile, from sample data with no network. Each one pushes the
/// full screen, whose ⋯ menu swaps the state in place so the tuner panel can stay open. No control
/// on the profile does anything.
struct PublicGroupProfilePlayground: View {

    var body: some View {
        Background(color: .backgroundMain) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(PublicGroupProfilePlaygroundState.allCases) { state in
                        NavigationLink {
                            PublicGroupProfilePlaygroundPage(state: state)
                        } label: {
                            PlaygroundRow(title: state.title)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("profile-playground-\(state.rawValue)")
                    }
                }
            }
        }
        .navigationTitle("Profile Playground")
        .toolbarTitleDisplayMode(.inline)
    }
}

/// One state of the profile, drawn full screen.
struct PublicGroupProfilePlaygroundPage: View {

    @State var state: PublicGroupProfilePlaygroundState

    var body: some View {
        let sample = state.sample
        PublicGroupProfileView(
            content: sample.content,
            hasPinned: true,
            portraitData: { _ in nil },
            loadPortrait: { _ in },
            onSelectPerson: { _ in },
            onToken: { _ in },
            accessory: { EmptyView() },
            actions: {
                if sample.isHost {
                    Button("Edit Group") {}
                        .buttonStyle(PublicGroupOutlineButtonStyle())
                }
                Button("Share") {}
                    .buttonStyle(PublicGroupOutlineButtonStyle())
            },
            hasFooter: sample.isMember,
            footer: {
                if sample.isMember {
                    Button {} label: {
                        ButtonStateLabel("Leave Chat", state: .normal)
                    }
                    .buttonStyle(PublicGroupClosingButtonStyle())
                }
            },
            pinned: {
                Button("Open Chat") {}
                    .buttonStyle(PublicGroupCapsuleButtonStyle())
                    .padding(.horizontal, PublicGroupCapsuleButtonStyle.sideInset)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
            }
        )
        .bleedPalette(key: sample.bleedKey, image: sample.bleedImage, settings: PublicGroupLook.settings)
        // A fresh page per state, so the palette the last one held doesn't color one with no image.
        .id(state)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("State", selection: $state) {
                        ForEach(PublicGroupProfilePlaygroundState.allCases) { state in
                            Text(state.title).tag(state)
                        }
                    }
                } label: {
                    Image.system(.ellipsis)
                }
                .accessibilityIdentifier("profile-playground-states")
            }
        }
    }
}

/// A plain Beta Features row: a title and a chevron over a hairline.
private struct PlaygroundRow: View {

    let title: String

    var body: some View {
        HStack {
            Text(title)
                .font(.appTextMedium)
                .foregroundStyle(Color.textMain)
                .padding(.vertical, 10)
            Spacer()
            Image.icon(.chevronRightMedium)
                .iconSize(16)
                .foregroundStyle(Color.textSecondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .vSeparator(color: .rowSeparator, position: .bottom)
        .contentShape(Rectangle())
    }
}

// MARK: - States -

enum PublicGroupProfilePlaygroundState: String, CaseIterable, Identifiable, Hashable {
    case standard
    case busy
    case quiet
    case nobody
    case split
    case noCover
    case noPicture
    case member
    case nonMember
    case host
    case longTitle
    case loading

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard:  "Default: cover, 6 chatting"
        case .busy:      "Busy: 84, +79, long bio"
        case .quiet:     "Quiet: 1 chatting"
        case .nobody:    "Nobody this week"
        case .split:     "Join ≠ chat (split tiles)"
        case .noCover:   "No cover (avatar colour)"
        case .noPicture: "No avatar or picture"
        case .member:    "Member (Leave)"
        case .nonMember: "Non-member (no Leave)"
        case .host:      "Host (Edit Group)"
        case .longTitle: "Long title"
        case .loading:   "Requirements loading"
        }
    }

    /// The sample this state draws.
    @MainActor
    var sample: PublicGroupProfilePlaygroundSample {
        var sample = PublicGroupProfilePlaygroundSample(id: rawValue)
        switch self {
        case .standard, .member:
            break
        case .busy:
            sample.cover = .warm
            sample.chatting = 84
            sample.memberCount = 1_284
            sample.description = Self.longBio
        case .quiet:
            sample.cover = .navy
            sample.chatting = 1
            sample.memberCount = 3
        case .nobody:
            sample.cover = .green
            sample.chatting = 0
        case .split:
            sample.split = true
        case .noCover:
            sample.cover = nil
            sample.avatar = .warm
        case .noPicture:
            sample.cover = nil
            sample.avatar = nil
            sample.avatarBlurhash = nil
        case .nonMember:
            sample.isMember = false
        case .host:
            sample.isHost = true
        case .longTitle:
            sample.title = "The Extremely Long Named Flipcash Product Feedback and Bug Reports Group"
        case .loading:
            sample.isLoading = true
        }
        return sample
    }

    /// 160 characters.
    private static let longBio = "Weekly drops, honest feedback and the odd meme. Post bugs, ideas and wins here; the team reads everything and replies fast. Be kind, stay on topic and have fun."
}

/// What one playground state draws, built up from the default.
struct PublicGroupProfilePlaygroundSample {

    /// A generated image the page can be colored from.
    enum Swatch: String {
        case blurhash, navy, warm, green

        @MainActor
        var image: UIImage? {
            switch self {
            case .blurhash: BlurHashCache.shared.image(for: PublicGroupProfilePlaygroundSample.blurhash, width: 32, height: 32)
            case .navy:     Self.navyImage
            case .warm:     Self.warmImage
            case .green:    Self.greenImage
            }
        }

        private static let navyImage = gradient(UIColor(red: 0.08, green: 0.12, blue: 0.36, alpha: 1), UIColor(red: 0.20, green: 0.32, blue: 0.70, alpha: 1))
        private static let warmImage = gradient(UIColor(red: 0.85, green: 0.38, blue: 0.16, alpha: 1), UIColor(red: 0.95, green: 0.72, blue: 0.30, alpha: 1))
        private static let greenImage = gradient(UIColor(red: 0.06, green: 0.36, blue: 0.22, alpha: 1), UIColor(red: 0.42, green: 0.74, blue: 0.40, alpha: 1))

        private static func gradient(_ from: UIColor, _ to: UIColor) -> UIImage {
            let size = CGSize(width: 64, height: 64)
            return UIGraphicsImageRenderer(size: size).image { context in
                let colors = [from.cgColor, to.cgColor] as CFArray
                guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
                context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            }
        }
    }

    static let blurhash = "LGF5]+Yk^6#M@-5c,1J5@[or[Q6."

    let id: String
    var title = "Flipcash Product Feedback"
    var memberCount: UInt64 = 22
    var description = "Something look off? Not work? Crash? Post it here for the team to be aware."
    var cover: Swatch? = .blurhash
    var avatar: Swatch?
    var avatarBlurhash: String? = Self.blurhash
    var chatting = 6
    var split = false
    var isLoading = false
    var isMember = true
    var isHost = false

    /// The image the page is colored from: the cover, else the avatar, else none.
    @MainActor
    var bleedImage: UIImage? { (cover ?? avatar)?.image }

    /// Identifies ``bleedImage`` for the color cache.
    var bleedKey: String? { (cover ?? avatar).map { "playground-\($0.rawValue)" } }

    @MainActor
    var content: PublicGroupProfileContent {
        let now = Date.now
        let jeffy = PublicGroupToken(mint: .usdf, name: "Jeffy", imageURL: nil)
        let names = ["Ted Livingston", "Brandon", "Ben", "Grampa", "Telzénar", "WanliGold", "Mia"]
        let count = max(chatting, 1)
        let chatters = (0..<count).map { index in
            SampledChatter(
                // Stable, so the facepile keeps its identity as the tuner redraws the page.
                userID: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index)) ?? UUID(),
                profile: Profile(displayName: index < names.count ? names[index] : "Chatter \(index + 1)", phone: Phone?.none, email: nil),
                // Nobody this week: the one sampled chatter last spoke twelve days ago.
                lastSentAt: chatting == 0 ? now.addingTimeInterval(-12 * 24 * 60 * 60) : now.addingTimeInterval(-Double(index + 1) * 120),
                isCreator: index == 0
            )
        }
        let requirements = split
            ? [
                PublicGroupRequirementTile(purpose: .join, amount: "$50", token: jeffy),
                PublicGroupRequirementTile(purpose: .chat, amount: "$100", token: jeffy),
            ]
            : [PublicGroupRequirementTile(purpose: .joinAndChat, amount: "$100", token: jeffy)]
        let avatarData = avatar?.image?.pngData()
        return PublicGroupProfileContent(
            id: "playground-\(id)",
            title: title,
            memberCount: memberCount,
            description: description,
            avatarImageData: avatarData,
            avatarBlurhash: avatarData == nil ? avatarBlurhash : nil,
            cover: cover?.image,
            // Held back, as the real screen holds them until the token's name arrives.
            requirements: isLoading ? [] : requirements,
            yourBalance: isLoading ? nil : "$382.84 of Jeffy",
            pulse: isLoading ? nil : PublicGroupPulse(chatters: chatters, now: now),
            host: chatters.first.map(GroupPortrait.init)
        )
    }
}
#endif // LOCAL-TUNER
