//
//  MessageList.swift
//  Code
//
//  Created by Dima Bart on 2023-10-06.
//

import SwiftUI
import FlipchatServices
import CodeServices
import CodeUI

public protocol MessageListDelegate: AnyObject {
    func didInteract(chat: Chat, message: Chat.Message)
}

public struct MessageList: View {
    
    public weak var delegate: MessageListDelegate?
    
    private let scrollViewBottomID = "com.code.scrollView.bottomID"
    
    private let chat: Chat
    private let messages: [MessageGroup]
    private let exchange: Exchange
    
    @Binding private var state: State
    
    // MARK: - Init -
    
    @MainActor
    init(chat: Chat, exchange: Exchange, state: Binding<State>, delegate: MessageListDelegate? = nil) {
        self.chat = chat
        self.messages = chat.messages.groupByDay()
        self.exchange = exchange
        self._state = state
        self.delegate = delegate
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
                    .onChange(of: state.scrollToBottom) { _, shouldScroll in
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
                let isReceived = chat.isMessageReceived(message.senderID)
                
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(message.contents.enumerated()), id: \.element) { index, content in
                                                
                        MessageRow(width: geometry.messageWidth(for: content), isReceived: isReceived) {
                            switch content {
                            case .text(let content):
                                MessageText(
                                    state: .delivered,
                                    text: content,
                                    date: message.date,
                                    isReceived: isReceived,
                                    location: .forIndex(index, count: message.contents.count)
                                )
                                
                            case .localized(let key):
                                MessageText(
                                    state: .delivered,
                                    text: key.localizedStringByKey,
                                    date: message.date,
                                    isReceived: isReceived,
                                    location: .forIndex(index, count: message.contents.count)
                                )
                                
//                            case .kin(let amount, let verb):
//                                if let rate = rate(for: amount.currency) {
//                                    let amount = amount.amountUsing(rate: rate)
//                                    
//                                    MessagePayment(
//                                        state: message.state(for: chat.recipientPointers),
//                                        verb: verb,
//                                        amount: amount,
//                                        isReceived: isReceived,
//                                        date: message.date,
//                                        location: .forIndex(index, count: message.contents.count),
//                                        action: {
//                                            action(for: message)
//                                        }
//                                    )
//                                } else {
//                                    // If a rate for this currency isn't found, we can't
//                                    // represent the value so we fallback to a Kin amount
//                                    MessagePayment(
//                                        state: message.state(for: chat.recipientPointers),
//                                        verb: .unknown,
//                                        amount: KinAmount(kin: 0, rate: .oneToOne),
//                                        isReceived: isReceived,
//                                        date: message.date,
//                                        location: .forIndex(index, count: message.contents.count),
//                                        action: {
//                                            action(for: message, reference: reference)
//                                        }
//                                    )
//                                }
                                
                            case .sodiumBox:
                                MessageEncrypted(
                                    date: message.date,
                                    isReceived: isReceived,
                                    location: .forIndex(index, count: message.contents.count)
                                )
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
    
    private func action(for message: Chat.Message) {
        delegate?.didInteract(chat: chat, message: message)
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

private extension GeometryProxy {
    func messageWidth(for content: Chat.Content) -> CGFloat {
        switch content {
        case .localized, .sodiumBox, .text:
            return size.width * 0.70
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
