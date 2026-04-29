//
//  SettingsScreen.swift
//  Flipcash
//
//  Created by Dima Bart on 2021-03-02.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct SettingsScreen: View {

    @Environment(AppRouter.self) private var router
    @Environment(BetaFlags.self) private var betaFlags

    @State private var dialogItem: DialogItem?
    @State private var debugTapCount: Int = 0

    private let insets = EdgeInsets(top: 25, leading: 0, bottom: 25, trailing: 0)

    private let container: Container
    private let sessionAuthenticator: SessionAuthenticator
    private let sessionContainer: SessionContainer
    private let session: Session

    // MARK: - Init -

    init(container: Container, sessionContainer: SessionContainer) {
        self.container = container
        self.sessionAuthenticator = container.sessionAuthenticator
        self.sessionContainer = sessionContainer
        self.session = sessionContainer.session
    }

    // MARK: - Body -

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router[.settings]) {
            Background(color: .backgroundMain) {
                VStack(alignment: .center, spacing: 0) {
                    ScrollView(showsIndicators: false) {
                        list()
                    }
                    footer()
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ToolbarCloseButton {
                        router.dismissSheet()
                    }
                }
                ToolbarItem(placement: .principal) {
                    logoHeader()
                }
            }
            .navigationTitle("Settings")
            .appRouterDestinations(container: container, sessionContainer: sessionContainer)
        }
    }

    // MARK: - Header Components -

    @ViewBuilder private func logoHeader() -> some View {
        Button {
            handleLogoTap()
        } label: {
            Image.asset(.flipcashBrand)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 34)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Lists -

    @ViewBuilder private func list() -> some View {
        VStack(alignment: .leading, spacing: 0) {

            SettingsRow(asset: .myAccount, title: "My Account", insets: insets) {
                router.push(.settingsMyAccount)
            }

            SettingsRow(asset: .settings, title: "App Settings", insets: insets) {
                router.push(.settingsAppSettings)
            }

            SettingsRow(asset: .withdraw, title: "Withdraw Funds", insets: insets) {
                router.push(.withdraw)
            }

            SettingsRow(asset: .sliders, title: "Advanced Features", insets: insets) {
                router.push(.settingsAdvancedFeatures)
            }

            if betaFlags.accessGranted {
                SettingsRow(asset: .debug, title: "Beta Features", badge: betaBadge(), insets: insets) {
                    router.push(.settingsBetaFlags)
                }

                SettingsRow(asset: .switchAccounts, title: "Switch Accounts", badge: betaBadge(), insets: insets) {
                    router.push(.settingsAccountSelection)
                }
            }

            SettingsRow(asset: .logout, title: "Log Out", insets: insets) {
                dialogItem = .init(
                    style: .destructive,
                    title: "Are You Sure You Want To Log Out?",
                    subtitle: "You can get into this account using your Access Key",
                    dismissable: true
                ) {
                    DialogAction.destructive("Log Out") {
                        logout()
                    }
                    DialogAction.cancel {}
                }
            }

            Spacer()
        }
        .font(.appDisplayXS)
        .foregroundColor(.textMain)
        .dialog(item: $dialogItem)
    }

    @ViewBuilder private func footer() -> some View {
        VStack {
            Text("Version \(AppMeta.version) • Build \(AppMeta.build)")
                .lineLimit(1)
                .font(.appTextHeading)
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func betaBadge() -> Badge {
        Badge(decoration: .circle(.textWarning), text: "Beta")
    }

    // MARK: - Actions -

    private func handleLogoTap() {
        if debugTapCount >= 9 {
            betaFlags.setAccessGranted(!betaFlags.accessGranted)
            debugTapCount = 0
        } else {
            debugTapCount += 1
        }
    }

    private func logout() {
        Task {
            router.dismissSheet()
            try await Task.delay(milliseconds: 250)
            sessionAuthenticator.logout()
        }
    }
}
