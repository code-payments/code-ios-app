//
//  MessagePayment.swift
//  Code
//
//  Created by Dima Bart on 2024-07-02.
//

import SwiftUI
import CodeUI
import CodeServices
import FlipchatServices

public struct MessagePayment: View {
    
    public let state: Chat.Message.State
    public let amount: KinAmount
    public let isReceived: Bool
    public let date: Date
    public let location: MessageSemanticLocation
    public let action: VoidAction
    
    private let font: Font = .appTextMedium
    
    @State private var isThanked: Bool = false
        
    public init(state: Chat.Message.State, amount: KinAmount, isReceived: Bool, date: Date, location: MessageSemanticLocation, action: @escaping VoidAction) {
        self.state = state
        self.amount = amount
        self.isReceived = isReceived
        self.date = date
        self.location = location
        self.action = action
    }
    
    public var body: some View {
        VStack(alignment: .center, spacing: 10) {
            VStack(spacing: 6) {
                Text("Payment")
                    .font(.appTextSmall)
                    .foregroundColor(.textMain)
                
                FiatField(size: .large, amount: amount)
            }
            .padding(.top, 16)
            .padding(.bottom, 6)
            .padding(.horizontal, 16)
            
//            if showAction {
//                HStack(spacing: 8) {
//                    CodeButton(style: .filledThin, title: "Message", action: action)
//                }
//                .padding(.horizontal, 4)
//            }
            
            HStack {
                Spacer()
                TimestampView(state: state, date: date, isReceived: isReceived)
                    .padding(.bottom, 2)
                    .padding(.trailing, 4)
            }
        }
        .fixedSize()
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .background(Color.backgroundMain)
        .clipShape(
            cornerClip(
                isReceived: isReceived,
                location: location
            )
        )
        .overlay {
            cornerClip(
                isReceived: isReceived,
                location: location
            )
            .stroke(isReceived ? Color.backgroundMessageReceived : Color.backgroundMessageSent, lineWidth: 4)
            .padding(2) // Line width * 0.5
        }
    }
}
