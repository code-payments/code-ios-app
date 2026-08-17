//
//  YouScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// The "You" tab (Figma 9217:114237): the user's tip card, a share button, and
/// the settings list — the tab-bar entry into My Account / App Settings /
/// Advanced. Tapping the card presents it full screen via the app-root bill
/// overlay (`Session.presentOwnTipcard`). Settings rows push onto the tab's
/// `.you` stack, so they never touch the v1 scanner's Settings sheet.
struct YouScreen: View {

    @Environment(SessionContainer.self) private var sessionContainer
    @Environment(AppRouter.self) private var router
    @Environment(BetaFlags.self) private var betaFlags

    /// Warms the share-sheet preview image ahead of the share tap so it never
    /// lands on the tap; keyed by user.
    @State private var previewCache = TipCodePreviewCache()
    @State private var debugTapCount: Int = 0

    /// The on-screen card width; tuned to the Figma placement (card near the top).
    private static let cardWidth: CGFloat = 230
    private let rowInsets = EdgeInsets(top: 25, leading: 0, bottom: 25, trailing: 0)

    var body: some View {
        Background(color: .backgroundMain) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    card?
                        .contentShape(Rectangle())
                        .onTapGesture(perform: presentFullScreen)
                        // Hide the in-page card while its expanded copy is up in the
                        // app-root bill overlay, so it doesn't ghost through the
                        // overlay's scrim. Opacity (not removal) keeps the layout
                        // stable so nothing reflows on dismiss.
                        .opacity(sessionContainer.session.isShowingBill ? 0 : 1)
                        .animation(.easeInOut(duration: 0.2), value: sessionContainer.session.isShowingBill)
                        .padding(.top, 24)

                    Button(action: shareTipCard) {
                        Text("Share as a Link")
                            .font(.appTextMedium)
                            .foregroundStyle(Color.textMain)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 24)
                            .background(Color.backgroundRow, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 24)
                    .accessibilityIdentifier("you-share-button")

                    settingsList
                        .padding(.top, 32)

                    // v2 scrolls the version string with the content rather than
                    // pinning it above the tab bar (the v1 Settings sheet pinned it).
                    versionFooter
                        .padding(.top, 32)
                }
                .padding(.horizontal, 20)
            }
        }
        .task(id: profilePicture?.thumbnailBlobID) {
            previewCache.warm(TipCode.Payload(userID: sessionContainer.session.userID))
        }
    }

    // MARK: - Settings list -

    private var settingsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsRow(asset: .myAccount, title: "My Account", insets: rowInsets) {
                router.push(.settingsMyAccount)
            }
            SettingsRow(asset: .settings, title: "App Settings", insets: rowInsets) {
                router.push(.settingsAppSettings)
            }
            SettingsRow(asset: .sliders, title: "Advanced", insets: rowInsets) {
                router.push(.settingsAdvancedFeatures)
            }
            if betaFlags.accessGranted {
                SettingsRow(asset: .debug, title: "Beta Features", badge: .beta, insets: rowInsets) {
                    router.push(.settingsBetaFlags)
                }
                SettingsRow(asset: .switchAccounts, title: "Switch Accounts", badge: .beta, insets: rowInsets) {
                    router.push(.settingsAccountSelection)
                }
            }
        }
        .font(.appDisplayXS)
        .foregroundStyle(Color.textMain)
    }

    private var versionFooter: some View {
        Button {
            handleVersionTap()
        } label: {
            Text("Version \(AppMeta.version) • Build \(AppMeta.build)")
                .lineLimit(1)
                .font(.appTextHeading)
                .foregroundStyle(Color.textSecondary)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content -

    private var profile: Profile? { sessionContainer.session.profile }
    private var profilePicture: ProfilePicture? { profile?.profilePicture }

    private var codeData: Data {
        TipCode.Payload(userID: sessionContainer.session.userID).codeData()
    }

    private var url: URL { .tipcard(for: sessionContainer.session.userID) }

    private var card: TipcardView? {
        guard let name = profile?.displayName, !name.isEmpty else { return nil }
        return TipcardView(
            size: CGSize(width: Self.cardWidth, height: Self.cardWidth * TipcardView.aspectRatio),
            name: name,
            avatar: nil,
            codeData: codeData,
            tintOpacity: 0.36
        )
    }

    // MARK: - Actions -

    private func presentFullScreen() {
        guard let name = profile?.displayName, !name.isEmpty else { return }
        sessionContainer.session.presentOwnTipcard(codeData: codeData, name: name, avatar: nil)
    }

    private var shareTitle: String {
        if let name = profile?.displayName, !name.isEmpty { "Tip \(name)" } else { "My Tip Card" }
    }

    private func shareTipCard() {
        let item = TipCodeShareItem(
            url: url,
            title: shareTitle,
            preview: previewCache.preview(for: sessionContainer.session.userID)
        )
        ShareSheet.present(activityItem: item) { _ in }
    }

    private func handleVersionTap() {
        if debugTapCount >= 9 {
            betaFlags.setAccessGranted(!betaFlags.accessGranted)
            debugTapCount = 0
        } else {
            debugTapCount += 1
        }
    }
}
