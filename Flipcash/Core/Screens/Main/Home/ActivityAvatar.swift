//
//  ActivityAvatar.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI
import FlipcashCore
import FlipcashStore

/// The avatar an activity draws — the counterparty's profile photo for peer
/// activity (tips/sends), the token image for token activity (deposits, buys),
/// two overlapping coins for a conversion, or a monogram fallback. A peer avatar
/// shows a face rather than a token, so it carries the transacted token as a coin
/// badge (Figma 8966:1910, 9717:14215) unless the caller turns it off.
///
/// Shared by the activity row and the transaction details header at different
/// sizes, so the details screen opens on exactly the avatar that was tapped. Every
/// metric derives from `size`, which is what keeps the two in proportion.
struct ActivityAvatar: View {

    let activity: Activity
    let resolution: ActivityResolution
    var size: CGFloat = 40

    /// Whether a peer avatar carries its token badge. The details header names the
    /// token in full under the amount, so it turns the badge off rather than
    /// saying the same thing twice at two sizes.
    var showsTokenBadge: Bool = true

    @Environment(SessionContainer.self) private var sessionContainer
    private var session: Session { sessionContainer.session }

    /// The token badge, and the ring that separates a coin from what's behind it,
    /// as fractions of the avatar: a 40pt row avatar carries a 20pt badge on a 2pt
    /// ring, and the details header's larger avatar keeps the same proportions.
    private var badgeSize: CGFloat { size / 2 }
    private var ringWidth: CGFloat { size / 20 }
    private var badgeOverhang: CGFloat { size / 10 }
    private var swapCoinSize: CGFloat { size * 0.65 }

    var body: some View {
        if let swap = activity.swapMetadata {
            swapAvatar(swap)
        } else {
            singleAvatar
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(alignment: .bottomTrailing) {
                    if drawsTokenBadge {
                        tokenBadge.offset(x: badgeOverhang, y: badgeOverhang)
                    }
                }
                // Reserves the badge's overhang so it doesn't eat into the gap
                // before whatever sits beside the avatar.
                .padding(.trailing, drawsTokenBadge ? badgeOverhang : 0)
        }
    }

    /// Whether this avatar draws a badge: one the activity calls for, that the
    /// caller hasn't turned off.
    private var drawsTokenBadge: Bool {
        showsTokenBadge && Self.showsTokenBadge(for: activity)
    }

    /// Whether the activity's avatar calls for a token badge: only a peer
    /// activity, whose avatar is the counterparty rather than the token itself.
    static func showsTokenBadge(for activity: Activity) -> Bool {
        activity.swapMetadata == nil && activity.counterparty != nil
    }

    /// The token the payment moved in, as a coin badge over the counterparty's
    /// avatar (Figma 9717:14140) — a peer row shows *who*, so in a row this badge
    /// is the only place the token reads.
    @ViewBuilder private var tokenBadge: some View {
        tokenCoin(
            url: resolution.imageURL(for: activity.exchangedFiat.mint, fallback: resolution.entryMint, session: session),
            monogramID: activity.exchangedFiat.mint.base58,
            size: badgeSize
        )
        .overlay(Circle().stroke(Color.backgroundMain, lineWidth: ringWidth))
    }

    @ViewBuilder private var singleAvatar: some View {
        switch activity.counterparty {
        case .user(let userID):
            ContactAvatarView(
                id: userID.uuidString,
                displayName: resolution.counterpartyName ?? "",
                imageData: resolution.avatarData,
                blurhash: resolution.avatarBlurhash,
                size: size
            )
        case .phone(let e164):
            ContactAvatarView(
                id: e164,
                displayName: resolution.counterpartyName ?? "",
                imageData: resolution.avatarData,
                size: size
            )
        case .none:
            tokenOrGenericAvatar()
        }
    }

    @ViewBuilder private func tokenOrGenericAvatar() -> some View {
        if let url = resolution.imageURL(for: activity.exchangedFiat.mint, fallback: resolution.entryMint, session: session) {
            RemoteImage(url: url)
        } else {
            ContactAvatarView(id: activity.id.base58, displayName: "", size: size)
        }
    }

    /// The two swapped tokens as overlapping coins — the destination (To) sits on
    /// top of the source (From), per the Recent design. Each coin shows its mint
    /// logo (held balance first, then the async-resolved fallback).
    private func swapAvatar(_ swap: Activity.SwapMetadata) -> some View {
        ZStack {
            tokenCoin(
                url: resolution.imageURL(for: swap.fromMint, fallback: resolution.swapFromMint, session: session),
                monogramID: swap.fromMint.base58,
                size: swapCoinSize
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            tokenCoin(
                url: resolution.imageURL(for: swap.toMint, fallback: resolution.swapToMint, session: session),
                monogramID: swap.toMint.base58,
                size: swapCoinSize
            )
            .overlay(Circle().stroke(Color.backgroundMain, lineWidth: ringWidth))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .frame(width: size, height: size)
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
}

// MARK: - Resolution -

/// The asynchronously resolved parts of an activity — the counterparty's name and
/// picture, and the mint metadata behind the avatar's coins — held together rather
/// than as loose fields on every view that draws one.
///
/// Everything here is a fallback for something the caches already answer
/// instantly: a held balance names and illustrates its own mint, and an
/// unresolvable counterparty falls back to the server-rendered title and a
/// monogram. Views therefore render correctly before any of this lands.
@MainActor
@Observable
final class ActivityResolution {

    /// The counterparty's resolved display name (cached profile / contact).
    private(set) var counterpartyName: String?
    /// The counterparty's resolved avatar bytes + blurhash.
    private(set) var avatarData: Data?
    private(set) var avatarBlurhash: String?

    /// Conversion coin metadata resolved beyond the held-balance cache (local mint
    /// store, then a server fetch) so a swapped-away token still shows its real
    /// name and logo.
    private(set) var swapFromMint: StoredMintMetadata?
    private(set) var swapToMint: StoredMintMetadata?

    /// The transacted token's metadata, resolved the same way when it isn't a held
    /// balance.
    private(set) var entryMint: StoredMintMetadata?

    /// Resolves everything an activity's avatar and title need.
    ///
    /// A row only needs the entry's mint when it draws a badge over a face; the
    /// details screen names the token under the amount whatever the kind, so it
    /// asks for it with `resolvingEntryToken`.
    func resolve(
        activity: Activity,
        in sessionContainer: SessionContainer,
        resolvingEntryToken: Bool = false
    ) async {
        await resolveCounterparty(activity: activity, in: sessionContainer)

        let session = sessionContainer.session
        if let swap = activity.swapMetadata {
            swapFromMint = await resolveMintMetadata(swap.fromMint, session: session)
            swapToMint   = await resolveMintMetadata(swap.toMint, session: session)
        } else if resolvingEntryToken || ActivityAvatar.showsTokenBadge(for: activity) {
            let mint = activity.exchangedFiat.mint
            guard session.balance(for: mint) == nil else { return }
            entryMint = await resolveMintMetadata(mint, session: session)
        }
    }

    /// The token's display name: the held balance (instant, from cache) or the
    /// async-resolved metadata.
    func name(for mint: PublicKey, fallback: StoredMintMetadata?, session: Session) -> String? {
        session.balance(for: mint)?.name ?? fallback?.name
    }

    /// The token's logo, resolved the same way as ``name(for:fallback:session:)``.
    func imageURL(for mint: PublicKey, fallback: StoredMintMetadata?, session: Session) -> URL? {
        session.balance(for: mint)?.imageURL ?? fallback?.imageURL
    }

    /// Resolves the counterparty's name and avatar: a cached profile (+ fetched
    /// thumbnail) for a user, or an address-book contact for a phone number.
    /// Uncached counterparties fall back to the server title + a monogram.
    private func resolveCounterparty(activity: Activity, in sessionContainer: SessionContainer) async {
        switch activity.counterparty {
        case .user(let userID):
            await resolveUser(userID, in: sessionContainer)
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
    /// are never written to the profile cache). Without this, received payments
    /// show the server title and a monogram instead of a named row.
    private func resolveUser(_ userID: UserID, in sessionContainer: SessionContainer) async {
        let picture: ProfilePicture?

        if let profile = sessionContainer.session.cachedUserProfile(for: userID) {
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

    private func resolveMintMetadata(_ mint: PublicKey, session: Session) async -> StoredMintMetadata? {
        if let stored = session.storedMintMetadata(for: mint) {
            return stored
        }
        return try? await session.fetchMintMetadata(mint: mint)
    }
}
