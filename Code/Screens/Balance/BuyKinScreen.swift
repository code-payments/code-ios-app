//
//  BuyKinScreen.swift
//  Code
//
//  Created by Dima Bart on 2021-04-05.
//

import SwiftUI
import CodeUI
import CodeServices

@MainActor
class BuyKinViewModel: ObservableObject {
    
    @Published var amount: String = ""
    
//    @Published var isPresentingCurrencySelection = false
//    @Published var isPresentingSafari = false
    
    let session: Session
    let exchange: Exchange
    let bannerController: BannerController
    let betaFlags: BetaFlags
    
    var entryRate: Rate {
        exchange.localRate
    }
    
    var isSendDisabled: Bool {
        enteredKinAmount == nil
    }
    
    var kadoURL: URL? {
        guard let amount = enteredKinAmount else {
            return nil
        }
        
        guard
            let plist = Bundle.main.infoDictionary,
            let mixpanel = plist["kado"] as? [String: String],
            let apiKey = mixpanel["apiKey"]
        else {
            return nil
        }
        
        let route = isProduction ? "https://app.kado.money/" : "https://sandbox--kado.netlify.app/"
        var components = URLComponents(string: route)!
        
        components.queryItems = [
            URLQueryItem(name: "apiKey",         value: apiKey),
            URLQueryItem(name: "onPayAmount",    value: "\(amount.fiat)"),
            URLQueryItem(name: "onPayCurrency",  value: kadoEntryRate.currency.rawValue.uppercased()),
            URLQueryItem(name: "onRevCurrency",  value: "USDC"),
            URLQueryItem(name: "mode",           value: "minimal"),
            URLQueryItem(name: "network",        value: "SOLANA"),
            URLQueryItem(name: "fiatMethodList", value: "debit_only"),
            URLQueryItem(name: "phone",          value: session.user.phone?.e164 ?? ""),
            URLQueryItem(name: "onToAddress",    value: session.organizer.swapDepositAddress.base58),
        ]
        
        return components.url!
    }
    
    var kadoEntryRate: Rate {
        let kadoSupportedCurrencies: Set<CurrencyCode> = [
            .usd, .eur, .cad, .gbp, .mxn,
            .cop, .inr, .chf, .aud, .ars,
            .brl, .clp, .jpy, .krw, .pen,
            .php, .sgd, .try, .uyu, .twd,
            .vnd, .crc, .sek, .pln, .dkk,
            .nok, .nzd
        ]
        
        let entryRate = entryRate
        
        // If Kado doesn't support the local currency
        // of the user's locale, we'll need to fallback
        // to a reasonable default - .usd
        if kadoSupportedCurrencies.contains(entryRate.currency) {
            return entryRate
        } else {
            return exchange.rate(for: .usd)!
        }
    }
    
    var enteredKinAmount: KinAmount? {
        KinAmount(stringAmount: amount, rate: kadoEntryRate)
    }
    
    var maxPurchase: Kin {
        session.maxKinPurchase()
    }
    
    var minPurchase: Kin {
        session.minKinPurchase()
    }
    
    var isProduction: Bool {
        betaFlags.hasEnabled(.kadoProd)
    }
    
    // MARK: - Init -
    
    init(session: Session, exchange: Exchange, bannerController: BannerController, betaFlags: BetaFlags) {
        self.session = session
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
    
    func initiatePurchase() {
        guard let enteredKinAmount else {
            return
        }
        
        guard let kadoURL else {
            return
        }
        
        guard enteredKinAmount.kin > minPurchase else {
            showTooSmallError()
            return
        }
        
        guard enteredKinAmount.kin < maxPurchase else {
            showTooLargeError()
            return
        }
        
        kadoURL.openWithApplication()
    }
    
    // MARK: - Errors -
    
    private func showTooSmallError() {
        let formatted = minPurchase.formattedFiat(
            rate: kadoEntryRate,
            truncated: true,
            showOfKin: true
        )
        
        bannerController.show(
            style: .error,
            title: "Amount is too small",
            description: "Amount should be greater than \(formatted)",
            actions: [
                .cancel(title: Localized.Action.ok)
            ]
        )
    }
    
    private func showTooLargeError() {
        let formatted = maxPurchase.formattedFiat(
            rate: kadoEntryRate,
            truncated: true,
            showOfKin: true
        )
        
        bannerController.show(
            style: .error,
            title: "Amount is too large",
            description: "Amount should be greater than \(formatted)",
            actions: [
                .cancel(title: Localized.Action.ok)
            ]
        )
    }
}

// MARK: - Screen -

struct BuyKinScreen: View {
    
    @Binding public var isPresented: Bool
    @StateObject private var viewModel: BuyKinViewModel
    
    // MARK: - Init -
    
    init(isPresented: Binding<Bool>, viewModel: @autoclosure @escaping () -> BuyKinViewModel) {
        self._isPresented = isPresented
        self._viewModel = StateObject(wrappedValue: viewModel())
    }
    
    // MARK: - Body -
    
    var body: some View {
        NavigationView {
            Background(color: .backgroundMain) {
                VStack(spacing: 0) {
//                    Flow(isActive: $viewModel.isPresentingSafari) {
//                        LazyView(
//                            SafariView(
//                                url: viewModel.kadoURL!,
//                                entersReaderIfAvailable: false
//                            )
//                            .ignoresSafeArea()
//                            .navigationBarHidden(true)
//                        )
//                    }
                    
                    Spacer()
                    
                    VStack(spacing: 10) {
                        HStack(spacing: 15) {
                            AmountField(
                                content: $viewModel.amount,
                                defaultValue: "0",
                                flagStyle: viewModel.kadoEntryRate.currency.flagStyle,
                                formatter: .fiat(currency: viewModel.kadoEntryRate.currency, minimumFractionDigits: 0),
                                suffix: viewModel.kadoEntryRate.currency != .kin ? Localized.Core.ofKin : nil,
                                showChevron: false
                            )
                            .foregroundColor(.textMain)
                        }
                        
                        HStack(spacing: 0) {
                            Text("Powered by ")
                                .fixedSize()
                                .font(.appTextMedium)
                                .foregroundColor(.textSecondary)
                            
                            Image.asset(.kado)
                            
                            if !viewModel.isProduction {
                                Text("(sandbox)")
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
//                    .contextMenu(ContextMenu {
//                        Button {
//                            viewModel.copy()
//                        } label: {
//                            Label(Localized.Action.copy, systemImage: SystemSymbol.doc.rawValue)
//                        }
//                    })
//                    .sheet(isPresented: $viewModel.isPresentingCurrencySelection) {
//                        CurrencySelectionScreen(
//                            viewModel: CurrencySelectionViewModel(
//                                isPresented: $viewModel.isPresentingCurrencySelection,
//                                exchange: viewModel.exchange
//                            )
//                        )
//                        .environmentObject(viewModel.exchange)
//                    }
                    
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
                        disabled: viewModel.isSendDisabled)
                    {
                        viewModel.initiatePurchase()
                    }
                    .padding(.top, 10)
                }
                .padding(20)
            }
            .navigationBarTitle(Text(Localized.Action.buyMoreKin), displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ToolbarCloseButton(binding: $isPresented)
                }
            }
            .ignoresSafeArea(.keyboard)
            .onAppear {
                ErrorReporting.breadcrumb(.buyMoreKinScreen)
            }
        }
    }
}

// MARK: - Previews -

#Preview {
    NavigationView {
        BuyKinScreen(
            isPresented: .constant(true),
            viewModel: BuyKinViewModel(
                session: .mock,
                exchange: .mock,
                bannerController: .mock,
                betaFlags: .mock
            )
        )
    }
    .environmentObjectsForSession()
}