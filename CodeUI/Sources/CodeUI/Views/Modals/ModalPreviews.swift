//
//  BillModal.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI
import CodeServices

struct BillModal_Previews: PreviewProvider {
    static var previews: some View {
            Group {
                Background(color: .gray) {
                    ModalCashReceived(
                        title: "Received",
                        amount: "$5.00",
                        currency: .cad,
                        secondaryAction: "Cancel",
                        dismissAction: {}
                    )
                }
                Background(color: .gray) {
                    ModalPaymentConfirmation(
                        amount: "$5.00",
                        currency: .usd,
                        primaryAction: "Swipe to Pay",
                        secondaryAction: "Cancel",
                        paymentAction: { try await Task.delay(seconds: 1) },
                        dismissAction: {},
                        cancelAction: {}
                    )
                }
                Background(color: .gray) {
                    ModalInsufficientFunds(
                        title: "Insufficient Funds",
                        subtitle: "Please get more Kin and then try paying again.",
                        primaryAction: "Get More Kin",
                        secondaryAction: "Cancel",
                        getMoreKinAction: {},
                        dismissAction: {}
                    )
                }
                Background(color: .gray) {
                    ModalLoginConfirmation(
                        domain: Domain("google.com")!,
                        primaryAction: "Swipe to Login",
                        secondaryAction: "Cancel",
                        successAction: {},
                        dismissAction: {},
                        cancelAction: {}
                    )
                }
            }
    }
}
