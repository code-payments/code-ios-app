//
//  WithdrawSummaryScreen.swift
//  Code
//
//  Created by Dima Bart on 2022-08-05.
//

import SwiftUI
import CodeUI
import CodeServices

struct WithdrawSummaryScreen: View {
    
    @EnvironmentObject private var bannerController: BannerController
    
    @ObservedObject private var viewModel: WithdrawViewModel
    
    // MARK: - Init -
    
    init(viewModel: WithdrawViewModel) {
        self.viewModel = viewModel
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            GeometryReader { geometry in
                VStack(alignment: .center, spacing: 20) {
                    Spacer()
                    
                    BorderedContainer {
                        VStack(spacing: 10) {
                            AmountText(
                                flagStyle: viewModel.entryRate.currency.flagStyle,
                                content: viewModel.formattedEnteredAmount
                            )
                            .font(.appDisplayMedium)
                            
                            if viewModel.entryRate.currency != .kin {
                                KinText((viewModel.amount?.kin ?? 0).formattedTruncatedKin(), format: .large)
                                    .fixedSize()
                                    .foregroundColor(.textSecondary)
                                    .font(.appTextMedium)
                            }
                        }
                        .padding(20)
                        .frame(height: geometry.size.height * 0.3)
                    }
                    
                    Image.system(.arrowDown)
                        .foregroundColor(.textSecondary)
                    
                    BorderedContainer {
                        Text(viewModel.address?.base58 ?? PublicKey.kinMint.base58)
                            .font(.appDisplayXS)
                            .multilineTextAlignment(.center)
                            .padding(20)
                    }
                    
                    Spacer()
                    
                    CodeButton(
                        state: viewModel.withdrawalButtonState,
                        style: .filled,
                        title: Localized.Action.withdrawKin)
                    {
                        bannerController.show(
                            style: .error,
                            title: Localized.Prompt.Title.confirmWithdrawal,
                            description: Localized.Prompt.Description.confirmWithdrawal,
                            position: .bottom,
                            actions: [
                                .destructive(title: Localized.Action.yesWithdrawConfirm, action: withdraw),
                                .cancel(title: Localized.Action.cancel),
                            ]
                        )
                    }
                }
                .padding(20)
            }
        }
        .navigationBarTitle(Text(Localized.Title.withdrawKin), displayMode: .inline)
        .onAppear {
            Analytics.open(screen: .withdrawSummary)
            ErrorReporting.breadcrumb(.withdrawSummaryScreen)
        }
    }
    
    private func withdraw() {
        Task {
            do {
                try await viewModel.withdraw()
                showSuccess()
            } catch {
                showError()
            }
        }
    }
    
    // MARK: - Errors -
    
    private func showError() {
        bannerController.show(
            style: .error,
            title: Localized.Error.Title.failedWithdrawal,
            description: Localized.Error.Description.failedWithdrawal,
            actions: [
                .cancel(title: Localized.Action.ok)
            ]
        )
    }
    
    private func showSuccess() {
        bannerController.show(
            style: .notification,
            title: Localized.Success.Title.withdrawalComplete,
            description: Localized.Success.Description.withdrawalComplete,
            actions: [
                .cancel(title: Localized.Action.ok)
            ]
        )
    }
}

// MARK: - Previews -

struct WithdrawSummaryScreen_Previews: PreviewProvider {
    static var previews: some View {
        Preview(devices: .iPhoneSE, .iPhoneMax) {
            NavigationView {
                WithdrawSummaryScreen(
                    viewModel: WithdrawViewModel(
                        session: .mock,
                        exchange: .mock,
                        biometrics: .mock
                    )
                )
            }
        }
        .environmentObjectsForSession()
    }
}
