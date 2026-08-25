//
//  TipcardScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

private let logger = Logger(label: "flipcash.tipcard")

struct TipcardScreen: View {

    @Environment(Container.self) private var container
    @Environment(SessionContainer.self) private var sessionContainer

    @State private var avatar: UIImage?
    @State private var exportImage: Image?

    /// Renders the share sheet preview image ahead of the share tap so it never
    /// lands on the tap; keyed by user, warmed when the card is displayed.
    @State private var previewCache = TipCodePreviewCache()

    /// The card's on-screen width; the export renders the same view at @3x.
    private static let cardWidth: CGFloat = 300

    var body: some View {
        Background(color: .backgroundMain) {
            legacyContent
        }
        .navigationTitle("My Tip Card")
        .toolbarTitleDisplayMode(.inline)
        .task(id: profilePicture?.thumbnailBlobID) {
            previewCache.warm(TipCode.Payload(userID: sessionContainer.session.userID))
            await loadAvatar()
            renderExportImage()
        }
    }

    private var legacyContent: some View {
        VStack(spacing: 0) {
            Text("Share Your Tip Card to Get Tipped")
                .font(.appTextLarge)
                .foregroundStyle(Color.textMain)
                .multilineTextAlignment(.center)
                .padding(.top, 20)
                .padding(.horizontal, 20)

            Spacer()

            card

            Spacer()

            HStack(spacing: 40) {
                Button {
                    shareTipCard()
                } label: {
                    TipcardAction(icon: .Icons.share, title: "Share")
                }
                .accessibilityIdentifier("tipcard-share-button")
            }
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Content -

    private var profile: Profile? {
        sessionContainer.session.profile
    }

    private var profilePicture: ProfilePicture? {
        profile?.profilePicture
    }

    private var url: URL {
        .tipcard(for: sessionContainer.session.userID, username: profile?.username)
    }

    private var codeData: Data {
        TipCode.Payload(userID: sessionContainer.session.userID).codeData()
    }

    private var card: TipcardView? {
        guard let name = profile?.displayName, !name.isEmpty else { return nil }

        return TipcardView(
            size: CGSize(width: Self.cardWidth, height: Self.cardWidth * TipcardView.aspectRatio),
            name: name,
            avatar: avatar,
            codeData: codeData,
            tintOpacity: 0.36,
            subtitle: profile?.username.map(\.handle)
        )
    }

    // MARK: - Loading -

    private func loadAvatar() async {
        // Cleared up front: a replaced picture must not leave the previous photo
        // on the card, least of all baked into the export.
        avatar = nil

        guard let blobID = profilePicture?.thumbnailBlobID else { return }

        do {
            // Download URLs expire, so one is minted per load and never stored.
            guard let url = try await container.flipClient.blobDownloadURL(
                blobID: blobID,
                owner: sessionContainer.session.ownerKeyPair
            ) else {
                logger.info("Profile picture blob has no download URL", metadata: ["blobId": "\(blobID)"])
                return
            }

            avatar = try await RemoteImageLoader.image(at: url, cacheKey: blobID.description)
        } catch {
            guard !Task.isCancelled else { return }
            // The card still renders and shares without the photo.
            logger.info("Failed to load profile picture for the tipcard", metadata: ["error": "\(error)"])
        }
    }

    private func renderExportImage() {
        guard let card else { return }

        let renderer = ImageRenderer(content: card.environment(\.colorScheme, .dark))
        renderer.scale = 3

        guard let rendered = renderer.uiImage else {
            logger.error("Failed to render the tipcard for export")
            return
        }

        exportImage = Image(uiImage: rendered)
    }

    // MARK: - Sharing -

    /// The label iOS shows beside the preview; the sharer's name, not the URL.
    private var shareTitle: String {
        if let name = profile?.displayName, !name.isEmpty {
            "Tip \(name)"
        } else {
            "My Tip Card"
        }
    }

    private func shareTipCard() {
        let item = TipCodeShareItem(
            url: url,
            title: shareTitle,
            preview: previewCache.preview(for: sessionContainer.session.userID)
        )

        ShareSheet.present(activityItem: item) { _ in }
    }
}

// MARK: - TipcardAction -

private struct TipcardAction: View {

    let icon: ImageResource
    let title: String

    var body: some View {
        VStack(spacing: 8) {
            Image(icon)
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
                .foregroundStyle(Color.textMain)
                .frame(width: 64, height: 64)
                .background(Color(white: 0.16))
                .clipShape(Circle())

            Text(title)
                .font(.appTextSmall)
                .foregroundStyle(Color.textSecondary)
        }
    }
}
