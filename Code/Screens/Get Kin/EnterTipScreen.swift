//
//  EnterTipScreen.swift
//  Code
//
//  Created by Dima Bart on 2024-04-02.
//

import SwiftUI
import CodeUI
import CodeServices

@MainActor
class EnterTipViewModel: ObservableObject {
    
    @Published var amount: String = ""
    
    @Published var isPresentingCurrencySelection: Bool = false
    
    let session: Session
    let client: Client
    let exchange: Exchange
    let bannerController: BannerController
    let betaFlags: BetaFlags
    
    var isActionDisabled: Bool {
        enteredKinAmount == nil
    }
    
    var entryRate: Rate {
        exchange.entryRate
    }
    
    var enteredKinAmount: KinAmount? {
        KinAmount(stringAmount: amount, rate: entryRate)
    }
    
    // MARK: - Init -
    
    init(session: Session, client: Client, exchange: Exchange, bannerController: BannerController, betaFlags: BetaFlags) {
        self.session = session
        self.client = client
        self.exchange = exchange
        self.bannerController = bannerController
        self.betaFlags = betaFlags
    }
    
    // MARK: - Actions -
    
    func resetAmount() {
        amount = ""
    }
    
    func copy() {
        UIPasteboard.general.string = amount
    }
    
    func showTipConfirmation() {
        guard let amount = enteredKinAmount else {
            return
        }
        
        session.presentTipConfirmation(amount: amount)
        
    }
    
    // MARK: - Errors -
  
    
//    private func showTooLargeError() {
//        let fiat = Fiat(currency: kadoEntryRate.currency, amount: buyLimit.max)
//        let formatted = fiat.formatted(showOfKin: false)
//        
//        bannerController.show(
//            style: .error,
//            title: Localized.Error.Title.purchaseTooLarge,
//            description: Localized.Error.Description.purchaseTooLarge(formatted),
//            actions: [
//                .cancel(title: Localized.Action.ok)
//            ]
//        )
//    }
}

// MARK: - Limits -

extension EnterTipViewModel {
    
    var maxLimit: Kin {
        let limitKin = KinAmount(
            fiat: maxFiatLimit,
            rate: entryRate
        )
        
        return min(session.currentBalance, limitKin.kin)
    }
    
    var minLimit: Kin {
        let limitKin = KinAmount(
            fiat: minFiatLimit,
            rate: entryRate
        )
        
        return min(session.currentBalance, limitKin.kin)
    }
    
    var maxLimitFormatted: String {
        maxLimit.formattedFiat(
            rate: entryRate,
            truncated: true,
            showOfKin: true
        )
    }
    
    var minLimitFormatted: String {
        minLimit.formattedFiat(
            rate: entryRate,
            truncated: true,
            showOfKin: true
        )
    }
    
    var maxFiatLimit: Decimal {
        session.sendLimitFor(currency: entryRate.currency).nextTransaction
    }
    
    var minFiatLimit: Decimal {
        session.sendLimitFor(currency: entryRate.currency).maxPerTransaction / 250.0
    }
    
    func hasAvailableTransactionLimit(for amount: KinAmount) -> Bool {
        session.hasAvailableTransactionLimit(for: amount)
    }
    
    func hasSufficientFundsToSend(for amount: KinAmount) -> Bool {
        session.hasSufficientFunds(for: amount)
    }
}

// MARK: - Screen -

struct EnterTipScreen: View {
    
    @Binding public var isPresented: Bool
    @StateObject private var viewModel: EnterTipViewModel
    
    // MARK: - Init -
    
    init(isPresented: Binding<Bool>, viewModel: @autoclosure @escaping () -> EnterTipViewModel) {
        self._isPresented = isPresented
        self._viewModel = StateObject(wrappedValue: viewModel())
    }
    
    // MARK: - Appear -
    
    private func didAppear() {
        ErrorReporting.breadcrumb(.buyMoreKinScreen)
    }
    
    // MARK: - Body -
    
    var body: some View {
        NavigationView {
            Background(color: .backgroundMain) {
                VStack(spacing: 0) {
                    
                    Spacer()
                    
                    Button {
                        viewModel.isPresentingCurrencySelection.toggle()
                    } label: {
                        VStack(spacing: 10) {
                            HStack(spacing: 15) {
                                AmountField(
                                    content: $viewModel.amount,
                                    defaultValue: "0",
                                    flagStyle: viewModel.entryRate.currency.flagStyle,
                                    formatter: .fiat(currency: viewModel.entryRate.currency, minimumFractionDigits: 0),
                                    suffix: viewModel.entryRate.currency != .kin ? Localized.Core.ofKin : nil,
                                    showChevron: true
                                )
                                .foregroundColor(.textMain)
                            }
                            
                            Group {
                                if let kinAmount = viewModel.enteredKinAmount, viewModel.entryRate.currency != .kin {
                                    if viewModel.hasAvailableTransactionLimit(for: kinAmount) {
                                        KinText(kinAmount.kin.formattedTruncatedKin(), format: .large)
                                            .fixedSize()
                                            .foregroundColor(viewModel.hasSufficientFundsToSend(for: kinAmount) ? .textSecondary : .textError)
                                    } else {
                                        Text(Localized.Subtitle.canOnlyTipUpTo(viewModel.maxLimitFormatted))
                                            .fixedSize()
                                            .foregroundColor(.textError)
                                    }
                                } else {
                                    Text(Localized.Subtitle.enterUpTo(viewModel.maxLimitFormatted))
                                        .fixedSize()
                                }
                            }
                            .font(.appTextMedium)
                            .foregroundColor(.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .sheet(isPresented: $viewModel.isPresentingCurrencySelection) {
                        CurrencySelectionScreen(
                            viewModel: CurrencySelectionViewModel(
                                isPresented: $viewModel.isPresentingCurrencySelection,
                                exchange: viewModel.exchange
                            )
                        )
                        .environmentObject(viewModel.exchange)
                    }
                    
                    Spacer()
                    
                    KeyPadView(
                        content: $viewModel.amount,
                        configuration: .number(),
                        rules: KeyPadView.CurrencyRules.code(hasDecimals: false)
                    )
                    .padding([.leading, .trailing], -20)
                    
                    CodeButton(
                        style: .filled,
                        title: Localized.Action.next,
                        disabled: viewModel.isActionDisabled)
                    {
                        nextAction()
                    }
                    .padding(.top, 10)
                }
                .padding(20)
            }
            .navigationBarTitle(Text(Localized.Title.tipKin), displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ToolbarCloseButton(binding: $isPresented)
                }
            }
            .ignoresSafeArea(.keyboard)
            .onAppear {
                didAppear()
            }
            .onChange(of: viewModel.entryRate) { _ in
                viewModel.resetAmount()
            }
        }
    }
    
    private func nextAction() {
        viewModel.showTipConfirmation()
        isPresented = false
    }
}

// MARK: - Previews -

#Preview {
    NavigationView {
        BuyKinScreen(
            isPresented: .constant(true),
            viewModel: BuyKinViewModel(
                session: .mock,
                client: .mock,
                exchange: .mock,
                bannerController: .mock,
                betaFlags: .mock
            )
        )
    }
    .environmentObjectsForSession()
}
