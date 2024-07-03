//
//  MessagePayment.swift
//  Code
//
//  Created by Dima Bart on 2024-07-02.
//

import SwiftUI
import CodeUI
import CodeServices

public struct MessagePayment: View {
    
    public let state: Chat.Message.State
    public let verb: Chat.Verb
    public let amount: KinAmount
    public let isReceived: Bool
    public let date: Date
    public let location: MessageSemanticLocation
    public let showThank: Bool
    
    private let font: Font = .appTextMedium
    
    @State private var isThanked: Bool = false
        
    public init(state: Chat.Message.State, verb: Chat.Verb, amount: KinAmount, isReceived: Bool, date: Date, location: MessageSemanticLocation, showThank: Bool) {
        self.state = state
        self.verb = verb
        self.amount = amount
        self.isReceived = isReceived
        self.date = date
        self.location = location
        self.showThank = showThank
    }
    
    public var body: some View {
        let showButtons = showThank && verb == .tipReceived
        
        VStack(alignment: .trailing, spacing: 10) {
            VStack(spacing: 6) {
                if verb == .returned {
                    FiatField(size: .large, amount: amount)
                    
                    Text(verb.localizedText)
                        .font(.appTextSmall)
                        .foregroundColor(.textMain)
                    
                } else {
                    Text(verb.localizedText)
                        .font(.appTextSmall)
                        .foregroundColor(.textMain)
                    
                    FiatField(size: .large, amount: amount)
                }
            }
//            .if(showButtons) { $0
//                .frame(maxWidth: .infinity)
//            }
            .padding(.top, 16)
            .padding(.bottom, 6)
            .padding(.horizontal, 16)
            
            if showButtons {
                HStack(spacing: 8) {
//                    CodeButton(style: .filledThin, title: "🙏  Thank", disabled: isThanked) {
//                        isThanked.toggle()
//                    }
                    CodeButton(style: .filledThin, title: "Message") {
                        // Nothing for now
                    }
                }
                .padding(.horizontal, 4)
            }
            
            TimestampView(state: state, date: date, isReceived: isReceived)
                .padding(.bottom, 2)
                .padding(.trailing, 4)
        }
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

// MARK: - V2 -

public struct MessagePaymentV2: View {
    
    public let state: Chat.Message.State
    public let verb: Chat.Verb
    public let amount: KinAmount
    public let isReceived: Bool
    public let date: Date
    public let location: MessageSemanticLocation
    public let showThank: Bool
    
    private let font: Font = .appTextMedium
    
    @State private var isThanked: Bool = false
        
    public init(state: Chat.Message.State, verb: Chat.Verb, amount: KinAmount, isReceived: Bool, date: Date, location: MessageSemanticLocation, showThank: Bool) {
        self.state = state
        self.verb = verb
        self.amount = amount
        self.isReceived = isReceived
        self.date = date
        self.location = location
        self.showThank = showThank
    }
    
    public var body: some View {
        let showButtons = showThank && verb == .tipReceived
        
        VStack(alignment: .trailing, spacing: 4) {
            VStack(spacing: 6) {
                if verb == .returned {
                    FiatField(size: .large, amount: amount)
                    
                    Text(verb.localizedText)
                        .font(.appTextSmall)
                        .foregroundColor(.textMain)
                    
                } else {
                    Text(verb.localizedText)
                        .font(.appTextSmall)
                        .foregroundColor(.textMain)
                    
                    FiatField(size: .large, amount: amount)
                }
            }
            .if(showButtons) { $0
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 16)
            .background(Color.backgroundMain)
            .clipShape(
                cornerClip(
                    isReceived: isReceived,
                    smaller: true,
                    location: location
                )
            )
            
            if showButtons {
                HStack(spacing: 8) {
                    CodeButton(style: .filledThin, title: "🙏  Thank", disabled: isThanked) {
                        isThanked.toggle()
                    }
                    CodeButton(style: .filledThin, title: "Message") {
                        // Nothing for now
                    }
                }
                .padding(.top, 6)
                .padding(.horizontal, 2)
                .padding(.bottom, 2)
            }
            
            TimestampView(state: state, date: date, isReceived: isReceived)
                .padding(.vertical, 2)
                .padding(.trailing, 4)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .background(isReceived ? Color.backgroundMessageReceived : Color.backgroundMessageSent)
        .clipShape(
            cornerClip(
                isReceived: isReceived,
                location: location
            )
        )
    }
}
