//
//  MessageList.swift
//  Code
//
//  Created by Dima Bart on 2023-10-06.
//

import SwiftUI
import CodeServices
import CodeUI

public struct MessageList: View {
    
    private let scrollViewBottomID = "com.code.scrollView.bottomID"
    
    private let chat: Chat
    private let messages: [MessageGroup]
    private let exchange: Exchange
    
    private let useV2: Bool
    private let showThank: Bool
    
    @Binding private var state: State
    
    // MARK: - Init -
    
    @MainActor
    init(chat: Chat, exchange: Exchange, state: Binding<State>, useV2: Bool = false, showThank: Bool = false) {
        self.chat = chat
        self.messages = chat.messages.groupByDay()
        self.exchange = exchange
        self._state = state
        self.useV2 = useV2
        self.showThank = showThank
    }
    
    // MARK: - Actions -
    
    // MARK: - Body -
    
    public var body: some View {
        ScrollBox(color: .backgroundMain, ignoreEdges: [.bottom]) {
            GeometryReader { g in
                ScrollViewReader { scrollProxy in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 20) {
                            
                            ForEach(messages) { group in
                                messageGroup(group: group, geometry: g)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.top, 15)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onAppear {
                            scrollProxy.scrollTo(scrollViewBottomID, anchor: nil)
                        }
                        
                        Rectangle()
                            .fill(.clear)
                            .frame(height: 1)
                            .frame(maxWidth: .infinity)
                            .id(scrollViewBottomID)
                    }
                    .onChange(of: state.scrollToBottom) { shouldScroll in
                        guard shouldScroll else { return }
                        
                        withAnimation {
                            scrollProxy.scrollTo(scrollViewBottomID, anchor: nil)
                        }
                        
                        state.scrollToBottom = false
                    }
                }
            }
        }
    }
    
    @MainActor
    @ViewBuilder private func messageGroup(group: MessageGroup, geometry: GeometryProxy) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MessageTitle(text: group.date.formattedRelatively())
            
            ForEach(group.messages) { message in
                let isReceived = !chat.isMessageFromSelf(message)
                
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(message.contents.enumerated()), id: \.element) { index, content in
                                                
                        MessageRow(width: geometry.messageWidth(for: content), isReceived: isReceived) {
                            switch content {
                            case .text(let content):
                                MessageText(
                                    state: message.state(for: chat.recipientPointers),
                                    text: content,
                                    date: message.date,
                                    isReceived: isReceived,
                                    location: .forIndex(index, count: message.contents.count)
                                )
                                
                            case .localized(let key):
                                MessageText(
                                    state: message.state(for: chat.recipientPointers),
                                    text: key.localizedStringByKey,
                                    date: message.date,
                                    isReceived: isReceived,
                                    location: .forIndex(index, count: message.contents.count)
                                )
                                
                            case .kin(let amount, let verb):
                                if let rate = rate(for: amount.currency) {
                                    let amount = amount.amountUsing(rate: rate)
                                    
                                    if useV2 {
                                        MessagePaymentV2(
                                            state: message.state(for: chat.recipientPointers),
                                            verb: verb,
                                            amount: amount,
                                            isReceived: isReceived,
                                            date: message.date,
                                            location: .forIndex(index, count: message.contents.count),
                                            showThank: showThank
                                        )
                                    } else {
                                        MessagePayment(
                                            state: message.state(for: chat.recipientPointers),
                                            verb: verb,
                                            amount: amount,
                                            isReceived: isReceived,
                                            date: message.date,
                                            location: .forIndex(index, count: message.contents.count),
                                            showThank: showThank
                                        )
                                    }
                                } else {
                                    // If a rate for this currency isn't found, we can't
                                    // represent the value so we fallback to a Kin amount
                                    MessagePayment(
                                        state: message.state(for: chat.recipientPointers),
                                        verb: .unknown,
                                        amount: KinAmount(kin: 0, rate: .oneToOne),
                                        isReceived: isReceived,
                                        date: message.date,
                                        location: .forIndex(index, count: message.contents.count),
                                        showThank: showThank
                                    )
                                }
                                
                            case .sodiumBox:
                                MessageEncrypted(
                                    date: message.date,
                                    isReceived: isReceived,
                                    location: .forIndex(index, count: message.contents.count)
                                )
                                
                            case .thankYou(let intentID):
                                MessageAction(text: content.localizedText)
                                
                            case .identityRevealed(let memberID, let identity):
                                MessageAction(text: "Identity Revealed")
                                
//                            case .tip(let direction, let amount):
//                                
//                                if let rate = rate(for: amount.currency) {
//                                    let amount = amount.amountUsing(rate: rate)
//                                    
//                                    if useV2 {
//                                        MessagePaymentV2(
//                                            verb: direction == .sent ? .tipSent : .tipReceived,
//                                            amount: amount,
//                                            isReceived: isReceived,
//                                            date: message.date,
//                                            location: .forIndex(index, count: message.contents.count),
//                                            showThank: showThank
//                                        )
//                                    } else {
//                                        MessagePayment(
//                                            verb: direction == .sent ? .tipSent : .tipReceived,
//                                            amount: amount,
//                                            isReceived: isReceived,
//                                            date: message.date,
//                                            location: .forIndex(index, count: message.contents.count),
//                                            showThank: showThank
//                                        )
//                                    }
//                                    
//                                } else {
//                                    MessagePayment(
//                                        verb: direction == .sent ? .tipSent : .tipReceived,
//                                        amount: KinAmount(kin: 0, rate: .oneToOne),
//                                        isReceived: isReceived,
//                                        date: message.date,
//                                        location: .forIndex(index, count: message.contents.count),
//                                        showThank: showThank
//                                    )
//                                }
                            }
                        }
                        .id(group.contentID(forMessage: message, contentIndex: index))
                    }
                }
            }
        }
    }
    
    @MainActor
    private func rate(for currency: CurrencyCode) -> Rate? {
        exchange.rate(for: currency)
    }
}

extension MessageList {
    public struct State {
        
        var scrollToBottom: Bool
        
        init(scrollToBottom: Bool = false) {
            self.scrollToBottom = scrollToBottom
        }
    }
}

struct MessageGroup: Identifiable {
    
    var id: Date {
        date
    }
    
    var date: Date
    var messages: [Chat.Message]
    
    init(date: Date, messages: [Chat.Message]) {
        self.date = date
        self.messages = messages
    }
    
    func contentID(forMessage message: Chat.Message, contentIndex: Int) -> String {
        let lastContent = message.contents[contentIndex]
        return "\(message.id.data.hexEncodedString()):\(lastContent.id)"
    }
    
    func lastMessageContentID() -> String {
        let messageIndex = messages.count - 1
        let message = messages[messageIndex]
        return contentID(forMessage: message, contentIndex: message.contents.count - 1)
    }
}

extension Array where Element == Chat.Message {
    func groupByDay() -> [MessageGroup] {
        
        let calendar = Calendar.current
        var container: [Date: [Chat.Message]] = [:]

        forEach { message in
            let components = calendar.dateComponents([.year, .month, .day], from: message.date)
            if let date = calendar.date(from: components) {
                if container[date] == nil {
                    container[date] = [message]
                } else {
                    container[date]?.append(message)
                }
            }
        }
        
        let sortedKeys = container.keys.sorted()
        let groupedMessages = sortedKeys.map {
            MessageGroup(date: $0, messages: container[$0] ?? [])
        }

        return groupedMessages
    }
}

extension Chat.Content: Identifiable {
    public var id: String {
        localizedText
    }
}

private extension GeometryProxy {
    func messageWidth(for content: Chat.Content) -> CGFloat {
        switch content {
        case .localized, .kin, .sodiumBox, .text:
            return size.width * 0.70
        case .thankYou, .identityRevealed:
            return size.width
        }
    }
}

// MARK: - MessageRow -

public struct MessageRow<Content>: View where Content: View {
    
    private let width: CGFloat
    private let isReceived: Bool
    private let content: () -> Content
    
    private var vAlignment: HorizontalAlignment {
        isReceived ? .leading : .trailing
    }
    
    private var alignment: Alignment {
        isReceived ? .leading : .trailing
    }
    
    public init(width: CGFloat, isReceived: Bool, @ViewBuilder content: @escaping () -> Content) {
        self.width = width
        self.isReceived = isReceived
        self.content = content
    }
    
    public var body: some View {
        VStack(alignment: vAlignment) {
            HStack {
                if isReceived {
                    content()
                    Spacer() // TODO: Creates unnecessary space in the MessageAction instances
                } else {
                    Spacer()
                    content()
                }
            }
            .frame(maxWidth: width, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: alignment)
    }
}

extension View {
    func cornerClip(isReceived: Bool, smaller: Bool = false, location: MessageSemanticLocation) -> some Shape {
        let m = (smaller ? 0.65 : 1.0)
        if isReceived {
            return UnevenRoundedCorners(
                tl: location.topLeftRadius * m,
                bl: location.bottomLeftRadius * m,
                br: Metrics.chatMessageRadiusLarge * m,
                tr: Metrics.chatMessageRadiusLarge * m
            )
        } else {
            return UnevenRoundedCorners(
                tl: Metrics.chatMessageRadiusLarge * m,
                bl: Metrics.chatMessageRadiusLarge * m,
                br: location.bottomRightRadius * m,
                tr: location.topRightRadius * m
            )
        }
    }
}

// MARK: - Previews -

struct MessageList_Previews: PreviewProvider {
    static var previews: some View {
        Background(color: .backgroundMain) {
            MessageList(
                chat: Chat(
                    id: .mock,
                    cursor: .mock,
                    kind: .notification,
                    title: "Test",
                    canMute: true,
                    canUnsubscribe: true,
                    members: [],
                    messages: [
//                        Chat.Message(
//                            id: .random,
//                            date: .now,
//                            isReceived: nil,
//                            contents: [
//                                .tip(.received, .exact(
//                                    KinAmount(
//                                        fiat: 100.00,
//                                        rate: Rate(
//                                            fx: 0.000016,
//                                            currency: .usd
//                                        )
//                                    )
//                                ))
//                            ]
//                        ),
//                        Chat.Message(
//                            id: .random,
//                            date: .now,
//                            isReceived: nil,
//                            contents: [
//                                .thankYou(.sent),
//                            ]
//                        ),
//                        
//                        Chat.Message(
//                            id: .random,
//                            date: .now,
//                            isReceived: nil,
//                            contents: [
//                                .localized("Hi")
//                            ]
//                        ),
//                        Chat.Message(
//                            id: .random,
//                            date: .now,
//                            isReceived: false,
//                            contents: [
//                                .localized("Hello"),
//                            ]
//                        ),
//                        Chat.Message(
//                            id: .random,
//                            date: .now,
//                            isReceived: false,
//                            contents: [
//                                .localized("I'm sending you some Kin to pay you back for lunch earlier."),
//                                .kin(
//                                    .partial(Fiat(
//                                        currency: .cny,
//                                        amount: 35.75
//                                    )), .sent
//                                ),
//                            ]
//                        ),
//                        Chat.Message(
//                            id: .random,
//                            date: .now,
//                            isReceived: nil,
//                            contents: [
//                                .localized("Oh, thanks! I think you sent me too much, I'll send some back."),
//                            ]
//                        ),
//                        Chat.Message(
//                            id: .random,
//                            date: .now,
//                            isReceived: nil,
//                            contents: [
//                                .kin(
//                                    .partial(Fiat(
//                                        currency: .cad,
//                                        amount: 1.00
//                                    )), .tipReceived
//                                ),
//                            ]
//                        ),
//                        
//                        Chat.Message(
//                            id: .random,
//                            date: .now,
//                            isReceived: nil,
//                            contents: [
//                                .sodiumBox(
//                                    EncryptedData(
//                                        peerPublicKey: .mock,
//                                        nonce: .init(),
//                                        encryptedData: .init()
//                                    )
//                                )
//                            ]
//                        ),                
                    ]
                ),
                exchange: .mock,
                state: .constant(.init())
            )
        }
    }
}
