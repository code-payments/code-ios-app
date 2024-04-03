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
    
    private var relationshipEstablished: Bool = false
    
    let session: Session
    let client: Client
    let exchange: Exchange
    let bannerController: BannerController
    let betaFlags: BetaFlags
    
    var entryRate: Rate {
        exchange.localRate
    }
    
    var isSendDisabled: Bool {
        enteredKinAmount == nil
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
    
    var buyLimit: BuyLimit {
        session.buyLimit(for: kadoEntryRate.currency) ?? .zero
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
    
    func initiatePurchase() -> Bool {
        guard let enteredKinAmount else {
            return false
        }
        
        let nonce = UUID()
        let kadoURL = buildKadoURL(for: enteredKinAmount, nonce: nonce)
        
        guard let kadoURL else {
            return false
        }
        
        let limit = buyLimit
        
        guard enteredKinAmount.fiat >= limit.min else {
            showTooSmallError()
            return false
        }
        
        guard enteredKinAmount.fiat <= limit.max else {
            showTooLargeError()
            return false
        }
        
        Task {
            try await client.declareFiatPurchase(
                owner: session.organizer.ownerKeyPair,
                amount: enteredKinAmount,
                nonce: nonce
            )
        }
        
        kadoURL.openWithApplication()
        return true
    }
    
    func establishSwapRelationshipIfNeeded() async throws {
        guard session.organizer.info(for: .swap) == nil else {
            relationshipEstablished = true
            return
        }
        
        do {
            try await session.linkUSDCAccount()
            relationshipEstablished = true
            
        } catch {
            bannerController.show(
                style: .error,
                title: "Account Error",
                description: "Failed to create a USDC deposit account."
            )
        }
    }
    
    func buildKadoURL(for amount: KinAmount, nonce: UUID) -> URL? {
        let apiKey = try? InfoPlist.value(for: "kado").value(for: "apiKey").string()
        
        guard let apiKey else {
            return nil
        }
        
        let encodedPhone = session.user.phone?.e164.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        
        let route = "https://app.kado.money/"
        var components = URLComponents(string: route)!
        
        components.percentEncodedQueryItems = [
            URLQueryItem(name: "apiKey",         value: apiKey),
            URLQueryItem(name: "onPayAmount",    value: "\(amount.fiat)"),
            URLQueryItem(name: "onPayCurrency",  value: kadoEntryRate.currency.rawValue.uppercased()),
            URLQueryItem(name: "onRevCurrency",  value: "USDC"),
            URLQueryItem(name: "mode",           value: "minimal"),
            URLQueryItem(name: "network",        value: "SOLANA"),
            URLQueryItem(name: "fiatMethodList", value: "debit_only"),
            URLQueryItem(name: "phone",          value: encodedPhone),
            URLQueryItem(name: "onToAddress",    value: session.organizer.swapDepositAddress.base58),
            URLQueryItem(name: "memo",           value: nonce.generateBlockchainMemo()),
        ]
        
        trace(.warning, components: "Navigatin to Kado URL: \(components.url!)")
        
        return components.url!
    }
    
    // MARK: - Errors -
    
    private func showTooSmallError() {
        let fiat = Fiat(currency: kadoEntryRate.currency, amount: buyLimit.min)
        let formatted = fiat.formatted(showOfKin: false)
        
        bannerController.show(
            style: .error,
            title: Localized.Error.Title.purchaseTooSmall,
            description: Localized.Error.Description.purchaseTooSmall(formatted),
            actions: [
                .cancel(title: Localized.Action.ok)
            ]
        )
    }
    
    private func showTooLargeError() {
        let fiat = Fiat(currency: kadoEntryRate.currency, amount: buyLimit.max)
        let formatted = fiat.formatted(showOfKin: false)
        
        bannerController.show(
            style: .error,
            title: Localized.Error.Title.purchaseTooLarge,
            description: Localized.Error.Description.purchaseTooLarge(formatted),
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
    
    // MARK: - Appear -
    
    private func didAppear() {
        ErrorReporting.breadcrumb(.buyMoreKinScreen)
        
        Task {
            try await viewModel.establishSwapRelationshipIfNeeded()
        }
    }
    
    // MARK: - Body -
    
    var body: some View {
        NavigationView {
            Background(color: .backgroundMain) {
                VStack(spacing: 0) {
                    
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
                            Text("\(Localized.Subtitle.poweredBy) ")
                                .fixedSize()
                                .font(.appTextMedium)
                                .foregroundColor(.textSecondary)
                            
                            Image.asset(.kado)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    
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
                        nextAction()
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
                didAppear()
            }
        }
    }
    
    private func nextAction() {
        let isInitiated = viewModel.initiatePurchase()
        if isInitiated {
            Task {
                try await Task.delay(milliseconds: 200)
                isPresented = false
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
                client: .mock,
                exchange: .mock,
                bannerController: .mock,
                betaFlags: .mock
            )
        )
    }
    .environmentObjectsForSession()
}
