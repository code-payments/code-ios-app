//
//  SettingsMyAccountScreen.swift
//  Flipcash
//
//  Created by Raul Riera on 2026-04-27.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct SettingsMyAccountScreen: View {

    @Environment(AppRouter.self) private var router
    @State private var dialogItem: DialogItem?

    let container: Container
    let sessionContainer: SessionContainer

    private var sessionAuthenticator: SessionAuthenticator { container.sessionAuthenticator }

    private let insets = EdgeInsets(top: 25, leading: 0, bottom: 25, trailing: 0)

    var body: some View {
        Background(color: .backgroundMain) {
            ScrollView(showsIndicators: false) {
                list()
            }
            .padding(.horizontal, 20)
        }
        .navigationTitle("My Account")
        .navigationBarTitleDisplayMode(.inline)
        .dialog(item: $dialogItem)
    }

    @ViewBuilder
    private func list() -> some View {
        VStack(alignment: .leading, spacing: 0) {

            SettingsRow(asset: .key, title: "Access Key", insets: insets) {
                dialogItem = .init(
                    style: .destructive,
                    title: "View Your Access Key?",
                    subtitle: "Your Access Key will grant access to your Flipcash account. Keep it private and safe",
                    dismissable: true
                ) {
                    DialogAction.destructive("View Access Key") {
                        router.push(.accessKey)
                    }
                    DialogAction.cancel {}
                }
            }

            SettingsRow(asset: .delete, title: "Delete Account", insets: insets) {
                dialogItem = .init(
                    style: .destructive,
                    title: "Permanently Delete Account?",
                    subtitle: "This will permanently delete your Flipcash account",
                    dismissable: true
                ) {
                    DialogAction.destructive("Permanently Delete Account") {
                        deleteAccount()
                    }
                    DialogAction.cancel {}
                }
            }
        }
        .font(.appDisplayXS)
        .foregroundStyle(.textMain)
    }

    private func deleteAccount() {
        Task {
            router.dismissSheet()
            try await Task.delay(milliseconds: 250)
            sessionAuthenticator.logout()
        }
    }
}
