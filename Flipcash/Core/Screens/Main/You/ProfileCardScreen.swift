//
//  ProfileCardScreen.swift
//  Flipcash
//

import SwiftUI
import UIKit
import FlipcashCore
import FlipcashUI

/// The user's tip card full screen (Figma node 9277:121410), with Download in the toolbar and Close
/// pinned to the bottom. Presented over the You tab from the profile's Share menu.
struct ProfileCardScreen: View {

    @Environment(SessionContainer.self) private var sessionContainer
    @Environment(\.dismiss) private var dismiss

    @State private var isShowingDownloadOptions = false

    /// The format tapped in the download sheet, held until the sheet is gone so
    /// the share sheet has a settled controller to present on.
    @State private var pendingDownload: TipCardDownloadFormat?

    /// The brightness to put back on close — set only when this screen raised it.
    @State private var previousBrightness: CGFloat?

    /// The card's width, from the full-screen frame (302 of the 402pt frame).
    private static let maxCardWidth: CGFloat = 302
    private static let horizontalInset: CGFloat = 20

    /// Below this a code is hard to scan, so the screen is raised to `boostedBrightness`.
    private static let minimumScanBrightness: CGFloat = 0.4
    private static let boostedBrightness: CGFloat = 0.6

    var body: some View {
        NavigationStack {
            Background(color: .backgroundMain) {
                ScrollView(showsIndicators: false) {
                    if let name = displayName {
                        TipcardView(
                            size: cardSize,
                            name: name,
                            avatar: nil,
                            codeData: codeData,
                            tintOpacity: 0.36,
                            subtitle: username.map(\.handle)
                        )
                        .padding(.horizontal, Self.horizontalInset)
                        .containerRelativeFrame(.vertical, alignment: .center)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button("Close") { dismiss() }
                    .buttonStyle(.subtle)
                    .accessibilityIdentifier("profile-card-close")
                    .padding(.horizontal, Self.horizontalInset)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingDownloadOptions = true
                    } label: {
                        Image.asset(.fileDownload)
                    }
                    .accessibilityLabel("Download")
                    .accessibilityIdentifier("you-download-button")
                }
            }
        }
        .sheet(isPresented: $isShowingDownloadOptions, onDismiss: exportPendingDownload) {
            TipCardDownloadSheet(
                onSelect: { pendingDownload = $0; isShowingDownloadOptions = false },
                onCancel: { isShowingDownloadOptions = false }
            )
        }
        .onAppear(perform: boostBrightness)
        .onDisappear(perform: restoreBrightness)
    }

    // MARK: - Content -

    private var profile: Profile? { sessionContainer.session.profile }

    private var displayName: String? {
        guard let name = profile?.displayName, !name.isEmpty else { return nil }
        return name
    }

    private var username: Username? { profile?.username }

    private var codeData: Data {
        TipCode.Payload(userID: sessionContainer.session.userID).codeData()
    }

    private var cardSize: CGSize {
        let screenWidth = UIApplication.shared.firstWindowScene?.screen.bounds.width ?? Self.maxCardWidth
        let width = min(Self.maxCardWidth, screenWidth - Self.horizontalInset * 2)
        return CGSize(width: width, height: width * TipcardView.aspectRatio)
    }

    // MARK: - Actions -

    /// Exports the format the sheet picked and hands the file to the share
    /// sheet, which is where iOS puts "Save to Files" and every other
    /// destination.
    ///
    /// Runs on the download sheet's dismissal rather than its tap: the share
    /// sheet presents on the top-most view controller, which is the download
    /// sheet itself until that dismissal finishes.
    private func exportPendingDownload() {
        guard let format = pendingDownload else { return }
        pendingDownload = nil

        guard let file = TipCardExport.file(for: format, codeData: codeData, name: displayName) else {
            return
        }

        ShareSheet.present(activityItems: [file]) { _ in
            // The sheet has taken its copy by now, whether or not the user went
            // through with it.
            TipCardExport.discard(file)
        }
    }

    // MARK: - Brightness -

    /// The card is a code someone is about to scan, so a dim screen is raised for as long as it is up.
    private func boostBrightness() {
        guard let screen = UIApplication.shared.firstWindowScene?.screen,
              screen.brightness < Self.minimumScanBrightness else { return }
        previousBrightness = previousBrightness ?? screen.brightness
        screen.brightness = Self.boostedBrightness
    }

    private func restoreBrightness() {
        guard let previousBrightness, let screen = UIApplication.shared.firstWindowScene?.screen else { return }
        screen.brightness = previousBrightness
        self.previousBrightness = nil
    }
}
