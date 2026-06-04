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

    @State private var debugTapCount: Int = 0

    private let insets = EdgeInsets(top: 25, leading: 0, bottom: 25, trailing: 0)

    private let container: Container
    private let sessionContainer: SessionContainer

    // MARK: - Init -

    init(container: Container, sessionContainer: SessionContainer) {
        self.container = container
        self.sessionContainer = sessionContainer
    }

    // MARK: - Body -

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router[.settings]) {
            Background(color: .backgroundMain) {
                List {
                    HStack(spacing: 12) {
                        Button("Deposit") {
                            router.push(.deposit)
                        }
                        .buttonStyle(.card(icon: .deposit))

                        Button("Withdraw") {
                            router.push(.withdraw)
                        }
                        .buttonStyle(.card(icon: .withdraw))
                    }
                    .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 6, trailing: 20))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    SettingsRow(asset: .myAccount, title: "My Account", insets: insets) {
                        router.push(.settingsMyAccount)
                    }

                    SettingsRow(asset: .settings, title: "App Settings", insets: insets) {
                        router.push(.settingsAppSettings)
                    }

                    SettingsRow(asset: .sliders, title: "Advanced Features", insets: insets) {
                        router.push(.settingsAdvancedFeatures)
                    }

                    if betaFlags.accessGranted {
                        SettingsRow(asset: .debug, title: "Beta Features", badge: betaBadge, insets: insets) {
                            router.push(.settingsBetaFlags)
                        }

                        SettingsRow(asset: .switchAccounts, title: "Switch Accounts", badge: betaBadge, insets: insets) {
                            router.push(.settingsAccountSelection)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .font(.appDisplayXS)
                .foregroundStyle(Color.textMain)
                .safeAreaInset(edge: .bottom) {
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
                    .padding(.horizontal, 20)
                }
            }
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    CloseButton(action: router.dismissSheet)
                }
            }
            .navigationTitle("Settings")
            .appRouterDestinations(container: container, sessionContainer: sessionContainer)
        }
    }

    // MARK: - Helpers -

    private let betaBadge = Badge(decoration: .circle(.textWarning), text: "Beta")

    // MARK: - Actions -

    private func handleVersionTap() {
        if debugTapCount >= 9 {
            betaFlags.setAccessGranted(!betaFlags.accessGranted)
            debugTapCount = 0
        } else {
            debugTapCount += 1
        }
    }
}
