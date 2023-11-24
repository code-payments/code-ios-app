//
//  WithdrawAmountScreen.swift
//  Code
//
//  Created by Dima Bart on 2021-04-05.
//

import SwiftUI
import CodeUI
import CodeServices

struct WithdrawAmountScreen: View {
    
    @EnvironmentObject private var exchange: Exchange
    
    @State private var isPresentingCurrencySelection = false
    @State private var isPresentingAddressEntry = false
    
    @StateObject private var viewModel: WithdrawViewModel
    
    // MARK: - Init -
    
    init(viewModel: @autoclosure @escaping () -> WithdrawViewModel) {
        self._viewModel = StateObject(wrappedValue: viewModel())
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            VStack(alignment: .center) {
                NavigationLink(isActive: $isPresentingAddressEntry) {
                    LazyView(
                        WithdrawAddressScreen(viewModel: viewModel)
                    )
                } label: {
                    EmptyView()
                }

                Spacer()
                
                Button {
                    isPresentingCurrencySelection.toggle()
                } label: {
                    VStack(spacing: 5) {
                        HStack(spacing: 15) {
                            AmountField(
                                content: $viewModel.enteredAmount,
                                defaultValue: "0",
                                flagStyle: viewModel.entryRate.currency.flagStyle,
                                formatter: .fiat(currency: viewModel.entryRate.currency, minimumFractionDigits: 0),
                                suffix: viewModel.entryRate.currency != .kin ? Localized.Core.ofKin : nil
                            )
                            .foregroundColor(.textMain)
                        }
                        if let amount = viewModel.shouldShowFormattedKinAmount {
                            KinText(amount.kin.formattedTruncatedKin(), format: .large)
                                .fixedSize()
                                .foregroundColor(viewModel.hasSufficientFundsToSend(amount: amount) ? .textSecondary : .textError)
                                .font(.appTextMedium)
                        } else {
                            Text(Localized.Subtitle.enterUpTo(viewModel.formattedMaxFiatAmount))
                                .fixedSize()
                                .foregroundColor(.textSecondary)
                                .font(.appTextMedium)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .contextMenu(ContextMenu {
                    Button(action: copy) {
                        Label(Localized.Action.copy, systemImage: SystemSymbol.doc.rawValue)
                    }
//                    if UIPasteboard.general.hasStrings {
//                        Button(action: attemptPaste) {
//                            Label(Localized.Action.paste, systemImage: SystemSymbol.clipboard.rawValue)
//                        }
//                    }
                })
                .sheet(isPresented: $isPresentingCurrencySelection) {
                    CurrencySelectionScreen(
                        viewModel: CurrencySelectionViewModel(
                            isPresented: $isPresentingCurrencySelection,
                            exchange: exchange
                        )
                    )
                    .environmentObject(exchange)
                }
                .padding(.top, -20)
                
                Spacer()
                
                KeyPadView(
                    content: $viewModel.enteredAmount,
                    configuration: viewModel.supportsDecimalEntry ? .decimal() : .number(),
                    rules: KeyPadView.CurrencyRules.code(hasDecimals: viewModel.supportsDecimalEntry)
                )
                .padding([.leading, .trailing], -20)
                
                CodeButton(
                    style: .filled,
                    title: Localized.Action.next,
                    disabled: !viewModel.hasValidAmount || !viewModel.hasSufficientFunds
                ) {
                    isPresentingAddressEntry = true
                    viewModel.resetAddress()
                }
                .padding(.top, 10)
            }
            .padding(20)
        }
        .navigationBarTitle(Text(Localized.Title.withdrawKin), displayMode: .inline)
        .onAppear {
            Analytics.open(screen: .withdrawAmount)
            ErrorReporting.breadcrumb(.withdrawAmountScreen)
        }
    }
    
    // MARK: - Copy / Paste -
    
    private func copy() {
        UIPasteboard.general.string = viewModel.enteredAmount
    }

//    private func attemptPaste() {
//        guard UIPasteboard.general.hasStrings else {
//            return
//        }
//
//        if
//            let clipboard = UIPasteboard.general.string,
//            let number = NumberFormatter.parse(amount: clipboard)
//        {
//            attempInsert(string: number.stringValue)
//        }
//    }
//
//    private func attempInsert(string: String) {
//        var content = ""
//
//        let binding = Binding {
//            content
//        } set: { newValue in
//            content = newValue
//        }
//
//        let actuator = KeyPadView.Actuator(
//            content: binding,
//            rules: KeyPadView.CurrencyRules.code(hasDecimals: viewModel.supportsDecimalEntry)
//        )
//
//        for char in string {
//            if !actuator.execute(action: .insert(String(char))) {
//                return
//            }
//        }
//
//        viewModel.enteredAmount = content
//    }
}

// MARK: - Previews -

struct WithdrawAmountScreen_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            WithdrawAmountScreen(
                viewModel: WithdrawViewModel(
                    session: .mock,
                    exchange: .mock,
                    biometrics: .mock
                )
            )
        }
        .environmentObjectsForSession()
    }
}
