//
//  GiveKinScreen.swift
//  Code
//
//  Created by Dima Bart on 2021-01-18.
//

import SwiftUI
import CodeServices
import CodeUI

struct GiveKinScreen: View {
    
    @EnvironmentObject private var bannerController: BannerController
    @EnvironmentObject private var exchange: Exchange
    @EnvironmentObject private var reachability: Reachability
    @EnvironmentObject private var biometrics: Biometrics
    
    @Binding public var isPresented: Bool
    
    @ObservedObject private var session: Session
    
    @State private var amount: String = ""
    @State private var isPresentingCurrencySelection = false
    
    private var supportsDecimalEntry: Bool {
        entryRate.currency != .kin
    }
    
    private var entryRate: Rate {
        exchange.entryRate
    }
    
    private var maxFiatAmount: String {
        let limitFiat = session.sendLimitFor(currency: entryRate.currency).nextTransaction
        let limitKin  = KinAmount(fiat: limitFiat, rate: entryRate)
        
        return min(session.currentBalance, limitKin.kin).formattedFiat(
            rate: entryRate,
            truncated: true,
            showOfKin: true
        )
    }
    
    private var title: String {
        return Localized.Title.giveKin
    }
    
    // MARK: - Init -
    
    public init(session: Session, isPresented: Binding<Bool>) {
        self.session = session
        self._isPresented = isPresented
    }
    
    // MARK: - Body -
    
    var body: some View {
        NavigationView {
            Background(color: .backgroundMain) {
                VStack(spacing: 0) {
                    Spacer()
                    
                    Button {
                        isPresentingCurrencySelection.toggle()
                    } label: {
                        VStack(spacing: 10) {
                            HStack(spacing: 15) {
                                AmountField(
                                    content: $amount,
                                    defaultValue: "0",
                                    flagStyle: entryRate.currency.flagStyle,
                                    formatter: .fiat(currency: entryRate.currency, minimumFractionDigits: 0),
                                    suffix: entryRate.currency != .kin ? Localized.Core.ofKin : nil
                                )
                                .foregroundColor(.textMain)
                            }
                            
                            Group {
                                if reachability.status == .online {
                                    if let kinAmount = enteredKinAmount(), entryRate.currency != .kin {
                                        if hasAvailableTransactionLimit(for: kinAmount) {
                                            KinText(kinAmount.kin.formattedTruncatedKin(), format: .large)
                                                .fixedSize()
                                                .foregroundColor(hasSufficientFundsToSend(for: kinAmount) ? .textSecondary : .textError)
                                        } else {
                                            Text(Localized.Subtitle.canOnlyGiveUpTo(maxFiatAmount))
                                                .fixedSize()
                                                .foregroundColor(.textError)
                                        }
                                    } else {
                                        Text(Localized.Subtitle.enterUpTo(maxFiatAmount))
                                            .fixedSize()
                                    }
                                } else {
                                    Text(Localized.Subtitle.noNetworkConnection)
                                        .fixedSize()
                                        .foregroundColor(.textError)
                                }
                            }
                            .font(.appTextMedium)
                            .foregroundColor(.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .contextMenu(ContextMenu {
                        Button(action: copy) {
                            Label(Localized.Action.copy, systemImage: SystemSymbol.doc.rawValue)
                        }
                    })
                    .sheet(isPresented: $isPresentingCurrencySelection) {
                        CurrencySelectionScreen(
                            viewModel: CurrencySelectionViewModel(
                                isPresented: $isPresentingCurrencySelection,
                                exchange: exchange,
                                kind: .entry
                            )
                        )
                        .environmentObject(exchange)
                    }
                    
                    Spacer()
                    
                    KeyPadView(
                        content: $amount,
                        configuration: supportsDecimalEntry ? .decimal() : .number(),
                        rules: KeyPadView.CurrencyRules.code(hasDecimals: supportsDecimalEntry)
                    )
                    .padding([.leading, .trailing], -20)
                    
                    CodeButton(style: .filled, title: Localized.Action.next, disabled: isSendDisabled()) {
                        Task {
                            if await initiateSendOperation() {
                                isPresented.toggle()
                            }
                        }
                    }
                    .padding(.top, 10)
                }
                .padding(20)
            }
            .navigationBarTitle(Text(title), displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ToolbarCloseButton(binding: $isPresented)
                }
            }
            .ignoresSafeArea(.keyboard)
            .onChange(of: exchange.entryRate) { _ in
                amount = ""
            }
            .onAppear {
                session.receiveIfNeeded()
                Analytics.open(screen: .giveKin)
                ErrorReporting.breadcrumb(.giveKinScreen)
            }
        }
    }
    
    private func isSendDisabled() -> Bool {
        enteredKinAmount() == nil
    }
    
    // MARK: - Copy / Paste -
    
    private func copy() {
        UIPasteboard.general.string = amount
    }
    
    // MARK: - Actions -
    
    private func hasSufficientFundsToSend(for amount: KinAmount) -> Bool {
        session.hasSufficientFunds(for: amount)
    }
    
    private func hasAvailableDailyLimit() -> Bool {
        session.hasAvailableDailyLimit()
    }
    
    private func hasAvailableTransactionLimit(for amount: KinAmount) -> Bool {
        session.hasAvailableTransactionLimit(for: amount)
    }
    
    private func enteredKinAmount() -> KinAmount? {
        let amount = KinAmount(
            stringAmount: amount,
            rate: entryRate
        )?.truncatingQuarks()
        
        return amount
    }
    
    private func initiateSendOperation() async -> Bool {
        guard let amount = enteredKinAmount() else {
            trace(.failure, components: "Failed to initiate an operation. Amount invalid: \(self.amount)")
            return false
        }
        
        guard reachability.status == .online else {
            showConnectivityError()
            return false
        }
        
        guard hasSufficientFundsToSend(for: amount) else {
            showInsufficientError()
            return false
        }
        
        guard hasAvailableDailyLimit() else {
            showDailyLimitError()
            return false
        }
        
        guard hasAvailableTransactionLimit(for: amount) else {
            showTransactionLimitError()
            return false
        }
        
//        if let context = biometrics.verificationContext() {
//            let isVerified = await context.verify(reason: .giveKin)
//            guard isVerified else {
//                return false
//            }
//            try? await Task.delay(seconds: 1)
//        }
        
        session.attemptSend(bill: .init(
            kind: .cash,
            amount: amount,
            didReceive: false
        ))
        
        return true
    }
    
    // MARK: - Errors -
    
    private func showInsufficientError() {
        bannerController.show(
            style: .error,
            title: Localized.Error.Title.insuffiecientKin,
            description: Localized.Error.Description.insuffiecientKin,
            actions: [
                .cancel(title: Localized.Action.ok)
            ]
        )
    }
    
    private func showDailyLimitError() {
        bannerController.show(
            style: .error,
            title: Localized.Error.Title.giveLimitReached,
            description: Localized.Error.Description.giveLimitReached,
            actions: [
                .cancel(title: Localized.Action.ok)
            ]
        )
    }
    
    private func showTransactionLimitError() {
        bannerController.show(
            style: .error,
            title: Localized.Error.Title.giveAmountTooLarge,
            description: Localized.Error.Description.giveAmountTooLarge(maxFiatAmount),
            actions: [
                .cancel(title: Localized.Action.ok)
            ]
        )
    }
    
    private func showConnectivityError() {
        bannerController.show(
            style: .networkError,
            title: Localized.Error.Title.noInternet,
            description: Localized.Error.Description.noInternet,
            actions: [
                .cancel(title: Localized.Action.ok)
            ]
        )
    }
}

// MARK: - Previews -

struct GiveKinScreen_Previews: PreviewProvider {
    static var previews: some View {
        Preview(devices: .iPhoneMini) {
            GiveKinScreen(session: .mock, isPresented: .constant(true))
        }
        .environmentObjectsForSession()
    }
}
