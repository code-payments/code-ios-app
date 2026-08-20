//
//  ActivityRow.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// The single activity row used across every surface — the Wallet and Currency
/// Info "Recent" previews, the cross-token Activity history, and the per-token
/// Transaction history (Figma 8966:1910, ported from Android's `ActivityFeedRow`):
/// a 40pt avatar, the title + relative time, and a signed amount. The avatar is
/// the counterparty's profile photo for peer activity (tips/sends), the token
/// image for token activity (deposits, buys), or a monogram fallback. A sent tip
/// reads "Tipped <name>" once the counterparty resolves, and a swap reads
/// "<From> → <To>" once both token names resolve.
struct ActivityRow: View {

    let activity: Activity

    @Environment(SessionContainer.self) private var sessionContainer
    private var session: Session { sessionContainer.session }

    /// The counterparty's resolved display name (cached profile / contact).
    @State private var counterpartyName: String?
    /// The counterparty's resolved avatar bytes + blurhash.
    @State private var avatarData: Data?
    @State private var avatarBlurhash: String?

    /// Swap coin metadata resolved beyond the held-balance cache (local mint
    /// store, then a server fetch) so a swapped-away token still shows its real
    /// name and logo.
    @State private var swapFromMint: StoredMintMetadata?
    @State private var swapToMint: StoredMintMetadata?

    var body: some View {
        HStack(spacing: 12) {
            avatar

            VStack(alignment: .leading, spacing: 4) {
                Text(displayTitle)
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textMain)
                    .lineLimit(1)
                Text(activity.date.formattedRelatively(useTimeForToday: true))
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer(minLength: 8)

            amount
        }
        .padding(.vertical, 12)
        .task(id: activity.id) {
            await resolveCounterparty()
            if let swap = activity.swapMetadata {
                await resolveSwapMints(swap)
            }
        }
    }

    // MARK: - Amount

    /// A swap shows the converted (From) fiat amount over its fee; every other
    /// row shows the single signed amount.
    @ViewBuilder private var amount: some View {
        if let swap = activity.swapMetadata {
            VStack(alignment: .trailing, spacing: 2) {
                Text(swap.fromFiat.formatted())
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textMain)
                    .lineLimit(1)
                Text("-\(swap.fee.formatted()) Fee")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }
        } else {
            Text(signedAmount)
                .font(.appTextMedium)
                .foregroundStyle(Color.textMain)
                .lineLimit(1)
        }
    }

    // MARK: - Title

    /// Peer tips render with the resolved counterparty name — "Tipped <name>"
    /// for a sent tip, "Tip from <name>" for a received one — and a swap renders
    /// its two token names, once they resolve; every other row uses the
    /// server-rendered title.
    private var displayTitle: String {
        if let swap = activity.swapMetadata {
            return Self.swapTitle(
                from: mintName(for: swap.fromMint, resolved: swapFromMint),
                to: mintName(for: swap.toMint, resolved: swapToMint)
            ) ?? activity.title
        }

        if let name = counterpartyName, !name.isEmpty {
            switch activity.kind {
            case .gave:     return "Tipped \(name)"
            case .received: return "Tip from \(name)"
            default:        break
            }
        }
        return activity.title
    }

    /// The conversion pair a swap row is titled with, or `nil` when either leg's
    /// token name is still unresolved — the caller falls back to the
    /// server-rendered title rather than showing a half-empty pair.
    static func swapTitle(from: String?, to: String?) -> String? {
        guard let from, !from.isEmpty, let to, !to.isEmpty else { return nil }
        return "\(from) \u{2192} \(to)"
    }

    /// The token's display name: the held balance (instant, from cache) or the
    /// async-resolved metadata.
    private func mintName(for mint: PublicKey, resolved: StoredMintMetadata?) -> String? {
        session.balance(for: mint)?.name ?? resolved?.name
    }

    // MARK: - Avatar

    @ViewBuilder private var avatar: some View {
        if let swap = activity.swapMetadata {
            swapAvatar(swap)
        } else {
            singleAvatar
                .frame(width: 40, height: 40)
                .clipShape(Circle())
        }
    }

    @ViewBuilder private var singleAvatar: some View {
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

    /// The two swapped tokens as overlapping coins — the destination (To) sits on
    /// top of the source (From), per the Recent design. Each coin shows its mint
    /// logo (held balance first, then the async-resolved fallback).
    private func swapAvatar(_ swap: Activity.SwapMetadata) -> some View {
        ZStack {
            tokenCoin(url: coinURL(for: swap.fromMint, fallback: swapFromMint), monogramID: swap.fromMint.base58, size: 26)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            tokenCoin(url: coinURL(for: swap.toMint, fallback: swapToMint), monogramID: swap.toMint.base58, size: 26)
                .overlay(Circle().stroke(Color.backgroundMain, lineWidth: 2))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .frame(width: 40, height: 40)
    }

    /// The held-balance logo (instant, from cache) or the async-resolved fallback.
    private func coinURL(for mint: PublicKey, fallback: StoredMintMetadata?) -> URL? {
        session.balance(for: mint)?.imageURL ?? fallback?.imageURL
    }

    @ViewBuilder private func tokenCoin(url: URL?, monogramID: String, size: CGFloat) -> some View {
        Group {
            if let url {
                RemoteImage(url: url)
            } else {
                ContactAvatarView(id: monogramID, displayName: "", size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    /// Resolves both coins beyond the held-balance cache: the local mint store,
    /// then a server fetch, so a swapped-away token still shows its name + logo.
    private func resolveSwapMints(_ swap: Activity.SwapMetadata) async {
        swapFromMint = await resolveMintMetadata(swap.fromMint)
        swapToMint   = await resolveMintMetadata(swap.toMint)
    }

    private func resolveMintMetadata(_ mint: PublicKey) async -> StoredMintMetadata? {
        if let stored = session.storedMintMetadata(for: mint) {
            return stored
        }
        return try? await session.fetchMintMetadata(mint: mint)
    }

    // MARK: - Amount

    private var signedAmount: String {
        let formatted = activity.exchangedFiat.nativeAmount.formatted()
        switch activity.kind {
        case .received, .deposited, .bought, .distributed, .sold:
            return "+\(formatted)"
        case .gave, .withdrew, .cashLink, .paid:
            return "-\(formatted)"
        case .swapped, .unknown:
            // A swap's net effect on the wallet isn't inherently in or out, so it
            // renders unsigned until the swap notification is modelled richly.
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
