//
//  TipcardScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

private let logger = Logger(label: "flipcash.tipcard")

struct TipcardScreen: View {

    @Environment(SessionContainer.self) private var sessionContainer

    @State private var avatar: UIImage?
    @State private var exportImage: Image?

    /// The card's on-screen width; the export renders the same view at @3x.
    private static let cardWidth: CGFloat = 300
    private static let cardAspectRatio: CGFloat = 1.16

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

                if let card {
                    card
                        .accessibilityIdentifier("tipcard")
                }

                Spacer()

                HStack(spacing: 40) {
                    if let url {
                        ShareLink(item: url) {
                            TipcardAction(systemName: "square.and.arrow.up", title: "Share")
                        }
                        .accessibilityIdentifier("tipcard-share-button")
                    }

                    if let exportImage {
                        ShareLink(
                            item: exportImage,
                            preview: SharePreview("My Tipcard", image: exportImage)
                        ) {
                            TipcardAction(systemName: "rectangle.portrait.and.arrow.right", title: "Export")
                        }
                        .accessibilityIdentifier("tipcard-export-button")
                    }
                }
                .padding(.bottom, 40)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("My Tipcard")
        .toolbarTitleDisplayMode(.inline)
        // Renders the export only once the avatar is in hand: `ImageRenderer`
        // is synchronous, so a URL-backed image would export as a placeholder.
        .task(id: profilePicture?.blobID) {
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

    private var url: URL? {
        URL.tipcard(for: sessionContainer.session.userID)
    }

    private var card: TipcardView? {
        guard let name = profile?.displayName, !name.isEmpty else { return nil }

        return TipcardView(
            size: CGSize(width: Self.cardWidth, height: Self.cardWidth * Self.cardAspectRatio),
            name: name,
            avatar: avatar,
            codeData: TipCode.Payload(userID: sessionContainer.session.userID).codeData()
        )
    }

    // MARK: - Loading -

    private func loadAvatar() async {
        guard let picture = profilePicture, let url = picture.thumbnailURL else { return }

        do {
            avatar = try await RemoteImageLoader.image(at: url, cacheKey: picture.blobID.description)
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

    let systemName: String
    let title: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemName)
                .font(.system(size: 22, weight: .regular))
                .frame(width: 64, height: 64)
                .background(Color(white: 0.16))
                .clipShape(Circle())

            Text(title)
                .font(.appTextSmall)
        }
        .foregroundStyle(Color.textMain)
    }
}
