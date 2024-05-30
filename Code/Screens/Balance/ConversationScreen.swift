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
    
    let chatID: ID
    let owner: KeyPair
    
    @EnvironmentObject private var client: Client
    @EnvironmentObject private var exchange: Exchange
    @EnvironmentObject private var betaFlags: BetaFlags
    
    @State private var input: String = ""
    @State private var messages: [Chat.Message] = []
    
    @State private var showingTips: Bool = false
    
    @State private var isShowingRevealIdentity: Bool = false
    
    @State private var stream: ChatMessageStreamReference?
    
    // MARK: - Init -
    
    init(chatID: ID, owner: KeyPair) {
        self.chatID = ID(data: Data(fromHexEncodedString: "468f158662880905e966f7c27f36b39e368837887aa5cf889cb55d91537d1a76")!)
        self.owner = owner
    }
    
    private func didAppear() {
        stream = client.openChatStream(chatID: chatID, owner: owner) { result in
            switch result {
            case .success(let messages):
                streamUpdate(messages: messages)
            case .failure(let failure):
                break
            }
        }
    }
    
    private func didDisappear() {
        stream?.destroy()
    }
    
    private func streamUpdate(messages: [Chat.Message]) {
        print("Messages: \(messages)")
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 0) {
                if isShowingRevealIdentity {
                    RevealIdentityBanner {
                        isShowingRevealIdentity.toggle()
                    }
                }
                
                MessageList(
                    messages: messages,
                    exchange: exchange,
                    useV2: betaFlags.hasEnabled(.alternativeBubbles),
                    showThank: true
                )
                
                HStack(alignment: .bottom) {
                    conversationTextView()
                        .font(.appTextMessage)
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
        .onAppear(perform: didAppear)
        .onDisappear(perform: didDisappear)
        .interactiveDismissDisabled()
        .navigationBarHidden(false)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingTips.toggle()
                } label: {
                    Image(systemName: "ellipsis.message.fill")
                }
            }
            ToolbarItem(placement: .principal) {
                title()
            }
        }
        .confirmationDialog("Select a color", isPresented: $showingTips, titleVisibility: .visible) {
            Button("\(isShowingRevealIdentity ? "Hide" : "Show") Reveal") {
                isShowingRevealIdentity.toggle()
            }
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
    
    @ViewBuilder private func title() -> some View {
        HStack(spacing: 10) {
            AvatarView(value: .placeholder, diameter: 30)
            
            VStack(alignment: .leading, spacing: 0) {
                Text("TontonTwitch")
                    .font(.appTextMedium)
                    .foregroundColor(.textMain)
                Text("Last seen today")
                    .font(.appTextHeading)
                    .foregroundColor(.textSecondary)
            }
            
            Spacer()
        }
    }
    
    @ViewBuilder private func conversationTextView() -> some View {
        if #available(iOS 16.0, *) {
            TextEditor(text: $input)
                .backportScrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.never)
        } else {
            TextEditor(text: $input)
                .backportScrollContentBackground(.hidden)
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

struct RevealIdentityBanner: View {
    
    var action: VoidAction
    
    init(action: @escaping VoidAction) {
        self.action = action
    }
    
    var body: some View {
        HStack {
            Text("Your messages are showing up anonymously.\nWould you like to reveal your identity?")
                .font(.appTextSmall)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.leading)
            
            Spacer()
            
            Button {
                action()
            } label: {
                TextBubble(
                    style: .filled,
                    text: "Reveal",
                    paddingVertical: 2,
                    paddingHorizontal: 6
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }
}

#Preview {
    ConversationScreen(chatID: .mock, owner: .mock)
        .environmentObjectsForSession()
}
