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

    // MARK: - Body -

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router[.settings]) {
            Background(color: .backgroundMain) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 6) {
                        HStack(spacing: 12) {
                            Button("Add Money") {
                                router.presentAddMoney(.general)
                            }
                            .buttonStyle(.card(icon: .deposit))

                            Button("Withdraw Money") {
                                router.push(.withdraw)
                            }
                            .buttonStyle(.card(icon: .withdraw))
                        }

                        VStack(alignment: .leading, spacing: 0) {
                            SettingsRow(asset: .myAccount, title: "My Account", insets: insets) {
                                router.push(.settingsMyAccount)
                            }

                            SettingsRow(asset: .settings, title: "App Settings", insets: insets) {
                                router.push(.settingsAppSettings)
                            }

                            SettingsRow(asset: .sliders, title: "Advanced", insets: insets) {
                                router.push(.settingsAdvancedFeatures)
                            }

                            if betaFlags.accessGranted {
                                SettingsRow(asset: .debug, title: "Beta Features", badge: .beta, insets: insets) {
                                    router.push(.settingsBetaFlags)
                                }

                                SettingsRow(asset: .switchAccounts, title: "Switch Accounts", badge: .beta, insets: insets) {
                                    router.push(.settingsAccountSelection)
                                }
                            }
                        }
                        .font(.appDisplayXS)
                        .foregroundStyle(Color.textMain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                }
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
            .appRouterDestinations()
        }
    }

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
