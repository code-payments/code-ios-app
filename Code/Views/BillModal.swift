//
//  BillModal.swift
//  Code
//
//  Created by Dima Bart on 2023-08-01.
//

import SwiftUI
import CodeServices
import CodeUI

/// Modal that displays received amount of Kin at local fiat rates
///
/// - parameters:
///   - title: Title of the modal
///   - amount: A KinAmount that was received
///   - dismissAction: A dismiss handler
///
struct ModalCashReceived: View {
    
    let title: String
    let amount: KinAmount
    let dismissAction: VoidAction
    
    // MARK: - Init -
    
    init(title: String, amount: KinAmount, dismissAction: @escaping VoidAction) {
        self.title = title
        self.amount = amount
        self.dismissAction = dismissAction
    }
    
    // MARK: - Body -
    
    var body: some View {
        SheetView(edge: .bottom, backgroundColor: .backgroundMain) {
            VStack(spacing: 10) {
                Text(title)
                    .font(.appTitle)
                
                AmountText(
                    flagStyle: amount.rate.currency.flagStyle,
                    content: amount.kin.formattedFiat(rate: amount.rate, showOfKin: true)
                )
                .font(.appDisplayMedium)
                
                VStack {
                    CodeButton(
                        style: .filled,
                        title: Localized.Action.putInWallet,
                        action: dismissAction
                    )
                }
                .padding(.top, 10)
            }
            .padding(20)
            .foregroundColor(.textMain)
            .font(.appTextMedium)
        }
    }
}

/// Modal to confirm and execute a payment request card
///
/// - parameters:
///   - amount: A KinAmount for the payment
///   - paymentAction: An async payment action. The dismiss handler `VoidAction` will be automatically called after this closure returns.
///   - dismissAction: A dismiss handler
///   - cancelAction: A cancel handler that is only called when the user rejects the payment request
///
struct ModalPaymentConfirmation: View {
    
    let amount: KinAmount
    let paymentAction: ThrowingAction
    let dismissAction: VoidAction
    let cancelAction: VoidAction
    
    // MARK: - Init -
    
    init(amount: KinAmount, paymentAction: @escaping ThrowingAction, dismissAction: @escaping VoidAction, cancelAction: @escaping VoidAction) {
        self.amount = amount
        self.paymentAction = paymentAction
        self.dismissAction = dismissAction
        self.cancelAction = cancelAction
    }
    
    // MARK: - Body -
    
    var body: some View {
        SheetView(edge: .bottom, backgroundColor: .backgroundMain) {
            VStack(spacing: 10) {
                
                AmountText(
                    flagStyle: amount.rate.currency.flagStyle,
                    content: amount.kin.formattedFiat(rate: amount.rate, showOfKin: true)
                )
                .font(.appDisplayMedium)
                
                VStack {
                    SwipeControl(
                        style: .blue,
                        text: Localized.Action.swipeToPay,
                        action: {
                            try await paymentAction()
                        },
                        completion: {
                            try await Task.delay(seconds: 1) // Checkmark delay
                            dismissAction()
                        }
                    )
                    
                    CodeButton(
                        style: .subtle,
                        title: Localized.Action.cancel,
                        action: {
                            cancelAction()
                        }
                    )
                    .padding(.bottom, -20)
                }
                .padding(.top, 10)
            }
            .padding(20)
            .padding(.top, 5)
            .foregroundColor(.textMain)
            .font(.appTextMedium)
        }
    }
}

/// Modal to confirm a login
///
/// - parameters:
///   - domain: A domain into which the user will log in
///   - successAction: An async payment action. The dismiss handler `VoidAction` will be automatically called after this closure returns.
///   - dismissAction: A dismiss handler
///   - cancelAction: A cancel handler that is only called when the user rejects the payment request
///
struct ModalLoginConfirmation: View {
    
    let domain: Domain
    let successAction: ThrowingAction
    let dismissAction: VoidAction
    let cancelAction: VoidAction
    
    // MARK: - Init -
    
    init(domain: Domain, successAction: @escaping ThrowingAction, dismissAction: @escaping VoidAction, cancelAction: @escaping VoidAction) {
        self.domain = domain
        self.successAction = successAction
        self.dismissAction = dismissAction
        self.cancelAction = cancelAction
    }
    
    // MARK: - Body -
    
    var body: some View {
        SheetView(edge: .bottom, backgroundColor: .black) {
            VStack(spacing: 10) {
                
                Text(domain.displayTitle)
                    .font(.appDisplaySmall)
                
                VStack {
                    SwipeControl(
                        style: .black,
                        text: Localized.Action.swipeToLogin,
                        action: {
                            try await successAction()
                        },
                        completion: {
                            try await Task.delay(seconds: 1) // Checkmark delay
                            dismissAction()
                        }
                    )
                    
                    CodeButton(
                        style: .subtle,
                        title: Localized.Action.cancel,
                        action: {
                            cancelAction()
                        }
                    )
                    .padding(.bottom, -20)
                }
                .padding(.top, 10)
            }
            .padding(20)
            .padding(.top, 5)
            .foregroundColor(.textMain)
            .font(.appTextMedium)
        }
    }
}

/// Modal to confirm and execute a payment request card
///
/// - parameters:
///   - title: Title of the modal
///   - getMoreKinAction: A handler for get more Kin action
///   - dismissAction: A dismiss handler
///
struct ModalInsufficientFunds: View {
    
    let title: String
    let subtitle: String
    let getMoreKinAction: VoidAction
    let dismissAction: VoidAction
    
    // MARK: - Init -
    
    init(title: String, subtitle: String, getMoreKinAction: @escaping VoidAction, dismissAction: @escaping VoidAction) {
        self.title = title
        self.subtitle = subtitle
        self.getMoreKinAction = getMoreKinAction
        self.dismissAction = dismissAction
    }
    
    // MARK: - Body -
    
    var body: some View {
        SheetView(edge: .bottom, backgroundColor: .backgroundMain) {
            VStack(spacing: 10) {
                
                VStack(spacing: 10) {
                    Text(title)
                        .font(.appDisplaySmall)
                    
                    Text(subtitle)
                        .font(.appTextSmall)
                }
                .multilineTextAlignment(.center)
                
                VStack {
                    CodeButton(
                        style: .filled,
                        title: Localized.Title.getMoreKin,
                        action: {
                            getMoreKinAction()
                        }
                    )
                    
                    CodeButton(
                        style: .subtle,
                        title: Localized.Action.cancel,
                        action: {
                            dismissAction()
                        }
                    )
                    .padding(.bottom, -20)
                }
                .padding(.top, 15)
            }
            .padding(20)
            .padding(.top, 5)
            .foregroundColor(.textMain)
            .font(.appTextMedium)
        }
    }
}

// MARK: - Previews -

struct BillModal_Previews: PreviewProvider {
    static var previews: some View {
            Group {
                Background(color: .gray) {
                    ModalCashReceived(
                        title: "Received",
                        amount: KinAmount(fiat: 5.00, rate: Rate(fx: 0.000018, currency: .usd)),
                        dismissAction: {}
                    )
                }
                Background(color: .gray) {
                    ModalPaymentConfirmation(
                        amount: KinAmount(fiat: 5.00, rate: Rate(fx: 0.000018, currency: .usd)),
                        paymentAction: { try await Task.delay(seconds: 1) },
                        dismissAction: {},
                        cancelAction: {}
                    )
                }
                Background(color: .gray) {
                    ModalInsufficientFunds(
                        title: "Insufficient Funds",
                        subtitle: "Please get more Kin and then try paying again.",
                        getMoreKinAction: {},
                        dismissAction: {}
                    )
                }
            }
    }
}
