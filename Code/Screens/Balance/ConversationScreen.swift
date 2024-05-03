//
//  ConversationScreen.swift
//  Code
//
//  Created by Dima Bart on 2024-04-30.
//

import SwiftUI
import CodeUI
import CodeServices

struct ConversationScreen: View {
    
    @EnvironmentObject private var exchange: Exchange
    
    @State private var input: String = ""
    @State private var messages: [Chat.Message] = []
    
    @State private var showingTips: Bool = false
    
    // MARK: - Init -
    
    init() {
        
    }
    
    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 0) {
                MessageList(messages: messages, exchange: exchange)
                
                HStack {
                    TextEditor(text: $input)
                        .backportScrollContentBackground(.hidden)
                        .font(.appTextMedium)
                        .foregroundColor(.backgroundMain)
                        .tint(.backgroundMain)
                        .multilineTextAlignment(.leading)
                        .frame(minHeight: 35, maxHeight: 95, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 5)
                        .background(.white)
                        .cornerRadius(20)
                    
                    Button {
                        send(content: input)
                    } label: {
                        Image.asset(.paperplane)
                            .resizable()
                            .frame(width: 36, height: 36, alignment: .center)
                            .padding(2)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 5)
                .padding(.bottom, 8)
            }
        }
        .navigationBarHidden(false)
        .navigationBarTitle(Text("Conversation"))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingTips.toggle()
                } label: {
                    Image(systemName: "ellipsis.message.fill")
                }
            }
        }
        .confirmationDialog("Select a color", isPresented: $showingTips, titleVisibility: .visible) {
            Button("Send Message") {
                input = "/stext Hey, how's it going?"
            }
            Button("Receive Message") {
                input = "/rtext Pretty good, how are you?"
            }
            
            Button("Send Payment") {
                input = "/s 5.00 usd"
            }
            Button("Receive Payment") {
                input = "/r 5.00 usd"
            }
            
            Button("Send Tip") {
                input = "/stip 10.00 usd"
            }
            Button("Receive Tip") {
                input = "/rtip 10.00 usd"
            }
            
            Button("Send Thanks") {
                input = "/sthanks"
            }
            Button("Receive Thanks") {
                input = "/rthanks"
            }
        }
    }
    
    // MARK: - Actions -
    
    private func send(content: String) {
        guard !input.isEmpty else {
            return
        }
        
        let m = generateMessages(for: content)
        
        guard !m.isEmpty else {
            return
        }
        
        messages.append(m[0])
        
        if m.count > 1 {
            Task {
                try await Task.delay(seconds: 1)
                messages.append(contentsOf: m.suffix(from: 1))
            }
        }
        
        input = ""
    }
    
    private func generateMessages(for input: String) -> [Chat.Message] {
        var messages: [Chat.Message] = []
        
        if input.hasPrefix("/") {
            let c = input.components(separatedBy: " ")
            if !c.isEmpty {
                
                let arg1 = c.count > 1 ? c[1] : nil
                let arg2 = c.count > 2 ? c[2] : nil
                
                switch c[0] {
                case "/s":
                    
                    guard let amount = arg1?.decimalValue else {
                        return []
                    }
                    
                    let currency = CurrencyCode(currencyCode: arg2 ?? "") ?? .usd
                    
                    messages.append(
                        Chat.Message(
                            id: .random,
                            date: .now,
                            isReceived: false,
                            contents: [
                                .kin(.exact(.init(fiat: amount, rate: Rate(fx: 0.000016, currency: currency))), .gave)
                            ]
                        )
                    )
                    
                case "/r":
                    
                    guard let amount = arg1?.decimalValue else {
                        return []
                    }
                    
                    let currency = CurrencyCode(currencyCode: arg2 ?? "") ?? .usd
                    
                    messages.append(
                        Chat.Message(
                            id: .random,
                            date: .now,
                            isReceived: true,
                            contents: [
                                .kin(.exact(.init(fiat: amount, rate: Rate(fx: 0.000016, currency: currency))), .received)
                            ]
                        )
                    )
                    
                case "/sthanks":
                    messages.append(
                        Chat.Message(
                            id: .random,
                            date: .now,
                            isReceived: false,
                            contents: [
                                .thankYou(.sent)
                            ]
                        )
                    )
                    
                case "/rthanks":
                    messages.append(
                        Chat.Message(
                            id: .random,
                            date: .now,
                            isReceived: true,
                            contents: [
                                .thankYou(.received)
                            ]
                        )
                    )
                    
                case "/stip":
                    
                    guard let amount = arg1?.decimalValue else {
                        return []
                    }
                    
                    let currency = CurrencyCode(currencyCode: arg2 ?? "") ?? .usd
                    
                    messages.append(
                        Chat.Message(
                            id: .random,
                            date: .now,
                            isReceived: false,
                            contents: [
                                .tip(.sent, .exact(.init(fiat: amount, rate: Rate(fx: 0.000016, currency: currency))))
                            ]
                        )
                    )
                    
                case "/rtip":
                    
                    guard let amount = arg1?.decimalValue else {
                        return []
                    }
                    
                    let currency = CurrencyCode(currencyCode: arg2 ?? "") ?? .usd
                    
                    messages.append(
                        Chat.Message(
                            id: .random,
                            date: .now,
                            isReceived: true,
                            contents: [
                                .tip(.received, .exact(.init(fiat: amount, rate: Rate(fx: 0.000016, currency: currency))))
                            ]
                        )
                    )
                    
                case "/stext":
                    messages.append(
                        Chat.Message(
                            id: .random,
                            date: .now,
                            isReceived: false,
                            contents: [
                                .localized(input.replacingOccurrences(of: "/stext ", with: ""))
                            ]
                        )
                    )
                    
                case "/rtext":
                    messages.append(
                        Chat.Message(
                            id: .random,
                            date: .now,
                            isReceived: true,
                            contents: [
                                .localized(input.replacingOccurrences(of: "/rtext ", with: ""))
                            ]
                        )
                    )
                    
                default:
                    return []
                }
            }
        } else {
            messages.append(
                Chat.Message(
                    id: .random,
                    date: .now,
                    isReceived: false,
                    contents: [
                        .localized(input)
                    ]
                )
            )
            
            messages.append(
                Chat.Message(
                    id: .random,
                    date: .now,
                    isReceived: true,
                    contents: [
                        .localized(input)
                    ]
                )
            )
        }
        
        return messages
    }
}

#Preview {
    ConversationScreen()
        .environmentObjectsForSession()
}
