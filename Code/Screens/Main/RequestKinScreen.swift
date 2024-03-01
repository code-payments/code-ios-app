//
//  RequestKinScreen.swift
//  Code
//
//  Created by Dima Bart on 2021-01-18.
//

import SwiftUI
import CodeServices
import CodeUI

struct RequestKinScreen: View {
    
    @EnvironmentObject private var bannerController: BannerController
    @EnvironmentObject private var exchange: Exchange
    @EnvironmentObject private var reachability: Reachability
    
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
        let limitFiat = session.buyLimit(for: entryRate.currency)?.max ?? 0
        let limitKin  = KinAmount(fiat: limitFiat, rate: entryRate)
        
        return limitKin.kin.formattedFiat(
            rate: entryRate,
            truncated: true,
            showOfKin: true
        )
    }
    
    private var title: String {
        Localized.Title.requestKin
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
                                        if canRequest(amount: kinAmount) {
                                            KinText(kinAmount.kin.formattedTruncatedKin(), format: .large)
                                                .fixedSize()
                                                .foregroundColor(.textSecondary)
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
                    .sheet(isPresented: $isPresentingCurrencySelection) {
                        CurrencySelectionScreen(
                            viewModel: CurrencySelectionViewModel(
                                isPresented: $isPresentingCurrencySelection,
                                exchange: exchange
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
                    
                    CodeButton(style: .filled, title: Localized.Action.next, disabled: isDisabled()) {
                        if initiateSendOperation() {
                            isPresented.toggle()
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
                ErrorReporting.breadcrumb(.requestKinScreen)
            }
        }
    }
    
    private func isDisabled() -> Bool {
        enteredKinAmount() == nil
    }
    
    // MARK: - Actions -
    
    private func canRequest(amount: KinAmount) -> Bool {
        (session.buyLimit(for: amount.rate.currency)?.max ?? 0) >= amount.fiat
    }
    
    private func enteredKinAmount() -> KinAmount? {
        let amount = KinAmount(
            stringAmount: amount,
            rate: entryRate
        )?.truncatingQuarks()
        
        return amount
    }
    
    private func initiateSendOperation() -> Bool {
        guard let amount = enteredKinAmount() else {
            trace(.failure, components: "Failed to initiate an operation. Amount invalid: \(self.amount)")
            return false
        }
        
        guard reachability.status == .online else {
            showConnectivityError()
            return false
        }
        
        session.presentRequest(
            amount: amount,
            payload: nil,
            request: nil
        )
        
        return true
    }
    
    // MARK: - Errors -
    
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

#Preview {
    GiveKinScreen(
        session: .mock,
        isPresented: .constant(true)
    )
    .environmentObjectsForSession()
}
