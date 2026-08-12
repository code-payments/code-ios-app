//
//  WalletActivityRow.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// A single row in the v2 Wallet's "Recent" activity preview (Figma 8966:1910,
/// ported from Android's `ActivityFeedRow`): a 40pt avatar, the title + relative
/// time, and a signed amount. The avatar is the counterparty's profile photo for
/// peer activity (tips/sends), the token image for token activity (deposits,
/// buys), or a monogram fallback. A sent tip reads "Tipped <name>" once the
/// counterparty resolves.
struct WalletActivityRow: View {

    let activity: Activity

    @Environment(SessionContainer.self) private var sessionContainer
    private var session: Session { sessionContainer.session }

    /// The counterparty's resolved display name (cached profile / contact).
    @State private var counterpartyName: String?
    /// The counterparty's resolved avatar bytes + blurhash.
    @State private var avatarData: Data?
    @State private var avatarBlurhash: String?

    var body: some View {
        HStack(spacing: 12) {
            avatar
                .frame(width: 40, height: 40)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(displayTitle)
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textMain)
                    .lineLimit(1)
                Text(activity.date.formattedRelatively(useTimeForToday: true))
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer(minLength: 8)

            Text(signedAmount)
                .font(.appTextMedium)
                .foregroundStyle(Color.textMain)
                .lineLimit(1)
        }
        .padding(.vertical, 10)
        .task(id: activity.id) { await resolveCounterparty() }
    }

    // MARK: - Title

    /// Peer tips render with the resolved counterparty name — "Tipped <name>"
    /// for a sent tip, "Tip from <name>" for a received one — once it resolves;
    /// every other row uses the server-rendered title.
    private var displayTitle: String {
        if let name = counterpartyName, !name.isEmpty {
            switch activity.kind {
            case .gave:     return "Tipped \(name)"
            case .received: return "Tip from \(name)"
            default:        break
            }
        }
        return activity.title
    }

    // MARK: - Avatar

    @ViewBuilder private var avatar: some View {
        switch activity.counterparty {
        case .user(let userID):
            ContactAvatarView(
                id: userID.uuidString,
                displayName: counterpartyName ?? "",
                imageData: avatarData,
                blurhash: avatarBlurhash,
                size: 40
            )
        case .phone(let e164):
            ContactAvatarView(
                id: e164,
                displayName: counterpartyName ?? "",
                imageData: avatarData,
                size: 40
            )
        case .none:
            tokenOrGenericAvatar()
        }
    }

    @ViewBuilder private func tokenOrGenericAvatar() -> some View {
        if let token = session.balance(for: activity.exchangedFiat.mint), let url = token.imageURL {
            RemoteImage(url: url)
        } else {
            ContactAvatarView(id: activity.id.base58, displayName: "", size: 40)
        }
    }

    // MARK: - Amount

    private var signedAmount: String {
        let formatted = activity.exchangedFiat.nativeAmount.formatted()
        switch activity.kind {
        case .received, .deposited, .bought, .distributed, .sold:
            return "+\(formatted)"
        case .gave, .withdrew, .cashLink, .paid:
            return "-\(formatted)"
        case .unknown:
            return formatted
        }
    }

    // MARK: - Resolution

    /// Resolves the counterparty's name and avatar: a cached profile (+ fetched
    /// thumbnail) for a user, or an address-book contact for a phone number.
    /// Uncached counterparties fall back to the server title + a monogram.
    private func resolveCounterparty() async {
        switch activity.counterparty {
        case .user(let userID):
            await resolveUser(userID)
        case .phone(let e164):
            let contact = sessionContainer.contactSyncController.resolvedContacts.onFlipcash.first { $0.phoneE164 == e164 }
            counterpartyName = contact?.displayName
            avatarData = contact?.imageData
        case .none:
            break
        }
    }

    /// A cached full profile (someone you've viewed or tipped) is authoritative;
    /// otherwise fall back to the tip conversation's member, which carries the
    /// name + picture for counterparties you've only *received* tips from (those
    /// are never written to the profile cache). Without this, received tips show
    /// the server title and a monogram instead of "Tip from <name>".
    private func resolveUser(_ userID: UserID) async {
        let picture: ProfilePicture?

        if let profile = session.cachedUserProfile(for: userID) {
            counterpartyName = profile.displayName
            picture = profile.profilePicture
        } else if let member = sessionContainer.conversationController.conversations
            .flatMap(\.members)
            .first(where: { $0.userID == userID }) {
            counterpartyName = member.displayName.isEmpty ? nil : member.displayName
            picture = member.profilePicture
        } else {
            picture = nil
        }

        avatarBlurhash = picture?.thumbnailBlurhash
        guard let picture else { return }
        await sessionContainer.tipAvatars.load(userID: userID, picture: picture)
        avatarData = sessionContainer.tipAvatars.data(for: userID)
    }
}
