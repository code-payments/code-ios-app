//
//  ModalButtons.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI
import CodeUI
import FlipchatServices

public struct ModalButtons: View {
    
    @Binding public var isPresented: Bool
    
    public let actions: [Action]
    
    // MARK: - Init -
    
    public init(isPresented: Binding<Bool>, actions: [Action]) {
        self._isPresented = isPresented
        self.actions = actions
    }
    
    // MARK: - Body -
    
    public var body: some View {
        VStack(spacing: 10) {
            VStack(spacing: 20) {
                ForEach(actions, id: \.title) {
                    CodeButton(
                        style: .filled,
                        title: $0.title,
                        action: $0.action
                    )
                }
            }
            
            CodeButton(
                style: .subtle,
                title: "Cancel",
                action: {
                    isPresented = false
                }
            )
        }
        .padding([.top, .leading, .trailing], 20)
        .foregroundColor(.textMain)
        .font(.appTextMedium)
        .background(Color.backgroundMain)
    }
}

extension ModalButtons {
    public struct Action {
        public var title: String
        public var action: VoidAction
    }
}

#Preview {
    Background(color: .backgroundMain) {}
    .sheet(isPresented: .constant(true)) {
        PartialSheet {
            ModalPaymentConfirmation(
                amount: "200",
                currency: .kin,
                primaryAction: "Swipe to Pay",
                secondaryAction: "Cancel",
                paymentAction: { try await Task.delay(seconds: 1) },
                dismissAction: {},
                cancelAction: {}
            )
        }
    }
}
