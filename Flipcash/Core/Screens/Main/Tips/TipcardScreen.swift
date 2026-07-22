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

    /// The card's on-screen width; the export renders the same view at @3x.
    private static let cardWidth: CGFloat = 300

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 0) {
                Text("Share Your Tipcard to Get Tipped")
                    .font(.appTextLarge)
                    .foregroundStyle(Color.textMain)
                    .multilineTextAlignment(.center)
                    .padding(.top, 20)
                    .padding(.horizontal, 20)

                Spacer()

                card

                Spacer()

                HStack(spacing: 40) {
                    ShareLink(item: url) {
                        TipcardAction(icon: .Icons.share, title: "Share")
                    }
                    .accessibilityIdentifier("tipcard-share-button")

                    // Always present so the row never reflows; disabled until
                    // the card has rendered with the photo — `ImageRenderer`
                    // is synchronous, so an earlier export would bake in the
                    // placeholder.
                    if let exportImage {
                        ShareLink(
                            item: exportImage,
                            preview: SharePreview("My Tipcard", image: exportImage)
                        ) {
                            TipcardAction(icon: .Icons.export, title: "Export")
                        }
                        .accessibilityIdentifier("tipcard-export-button")
                    } else {
                        TipcardAction(icon: .Icons.export, title: "Export")
                            .opacity(0.4)
                            .accessibilityIdentifier("tipcard-export-button")
                            .accessibilityAddTraits(.isButton)
                            .accessibilityHint("Preparing the card image")
                    }
                }
                .padding(.bottom, 40)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("My Tipcard")
        .toolbarTitleDisplayMode(.inline)
        .task(id: profilePicture?.thumbnailBlobID) {
            await loadAvatar()
            renderExportImage()
        }
    }

    // MARK: - Content -

    private var profile: Profile? {
        sessionContainer.session.profile
    }

    private var profilePicture: ProfilePicture? {
        profile?.profilePicture
    }

    private var url: URL {
        .tipcard(for: sessionContainer.session.userID)
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
            codeData: codeData
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
