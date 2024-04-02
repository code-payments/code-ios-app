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
    
    private let messages: [MessageGroup]
    private let exchange: Exchange
    
    // MARK: - Init -
    
    init(messages: [Chat.Message], exchange: Exchange) {
        self.messages = messages.groupByDay()
        self.exchange = exchange
    }
    
    // MARK: - Body -
    
    public var body: some View {
        ScrollBox(color: .backgroundMain, ignoreEdges: [.bottom]) {
            GeometryReader { g in
                ScrollViewReader { scrollProxy in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 20) {
                            
                            ForEach(messages) { group in
                                message(for: group, geometry: g)
                            }
                            
                            Spacer()
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onAppear {
                            if let lastGroup = messages.last {
                                scrollProxy.scrollTo(lastGroup.lastMessageContentID(), anchor: .top)
                            }
                        }
                    }
                }
            }
        }
    }
    
    @MainActor
    @ViewBuilder private func message(for group: MessageGroup, geometry: GeometryProxy) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            MessageTitle(text: group.date.formattedRelatively())
            
            ForEach(group.messages) { message in
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(message.contents.enumerated()), id: \.element) { index, content in
                        MessageRow(width: geometry.messageWidth) {
                            switch content {
                            case .localized(let key):
                                MessageText(
                                    text: key.localizedStringByKey,
                                    date: message.date,
                                    location: .forIndex(index, count: message.contents.count)
                                )
                                
                            case .decrypted(let content):
                                MessageText(
                                    text: content,
                                    date: message.date,
                                    location: .forIndex(index, count: message.contents.count)
                                )
                                
                            case .kin(let amount, let verb):
                                if let rate = rate(for: amount.currency) {
                                    MessagePayment(
                                        verb: verb,
                                        amount: amount.amountUsing(rate: rate),
                                        location: .forIndex(index, count: message.contents.count)
                                    )
                                } else {
                                    MessagePayment(
                                        verb: .unknown,
                                        amount: KinAmount(kin: 0, rate: .oneToOne),
                                        location: .forIndex(index, count: message.contents.count)
                                    )
                                }
                                
                            case .sodiumBox:
                                // TODO: Decrypt and show correct content
                                MessageEncrypted(
                                    date: message.date,
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
    var messageWidth: CGFloat {
        size.width * 0.70
    }
}

public struct MessageRow<Content>: View where Content: View {
    
    private let width: CGFloat
    private let content: () -> Content
    
    public init(width: CGFloat, @ViewBuilder content: @escaping () -> Content) {
        self.width = width
        self.content = content
    }
    
    public var body: some View {
        HStack {
            content()
            Spacer()
        }
        .frame(maxWidth: width, alignment: .leading)
    }
}

public struct MessageTitle: View {
    
    public let text: String
    
    // MARK: - Init -
        
    public init(text: String) {
        self.text = text
    }
    
    // MARK: - Body -
    
    public var body: some View {
        HStack {
            Spacer()
            Text(text)
                .font(.appTextHeading)
                .foregroundColor(.textMain)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.backgroundItem)
                .cornerRadius(99)
            Spacer()
        }
    }
}

public struct MessageText: View {
    
    public let text: String
    public let date: Date
    public let location: MessageSemanticLocation
    
    // MARK: - Init -
        
    public init(text: String, date: Date, location: MessageSemanticLocation) {
        self.text = text
        self.date = date
        self.location = location
    }
    
    // MARK: - Body -
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(text)
                .font(.appTextMessage)
                .foregroundColor(.textMain)
                .multilineTextAlignment(.leading)
            HStack {
                Spacer()
                Text(date.formattedTime())
                    .font(.appTextHeading)
                    .foregroundColor(.textSecondary)
            }
        }
        .padding([.leading, .trailing, .top], 12)
        .padding(.bottom, 8)
        .background(Color.backgroundItem)
        .clipShape(UnevenRoundedCorners(
            tl: location.topRadius,
            bl: location.bottomRadius,
            br: Metrics.chatMessageRadiusLarge,
            tr: Metrics.chatMessageRadiusLarge
        ))
    }
}

public struct MessageItem: View {
    
    public let text: String
    public let subtitle: String
    public let location: MessageSemanticLocation
    
    // MARK: - Init -
        
    public init(text: String, subtitle: String, location: MessageSemanticLocation) {
        self.text = text
        self.subtitle = subtitle
        self.location = location
    }
    
    // MARK: - Body -
    
    public var body: some View {
        VStack(spacing: 7) {
            Text(text)
                .font(.appTextMedium)
                .foregroundColor(.textMain)
            HStack {
                Spacer()
                Text(subtitle)
                    .font(.appTextSmall)
                    .foregroundColor(.textSecondary)
            }
        }
        .padding([.top, .leading, .trailing], 20)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
        .background(Color.backgroundItem)
        .clipShape(UnevenRoundedCorners(
            tl: location.topRadius,
            bl: location.bottomRadius,
            br: Metrics.chatMessageRadiusLarge,
            tr: Metrics.chatMessageRadiusLarge
        ))
    }
}

public struct MessageEncrypted: View {
    
    public let date: Date
    public let location: MessageSemanticLocation
    
    // MARK: - Init -
        
    public init(date: Date, location: MessageSemanticLocation) {
        self.date = date
        self.location = location
    }
    
    // MARK: - Body -
    
    public var body: some View {
        VStack(spacing: 7) {
            Image.system(.lockDashed)
                .font(.default(size: 30))
                .foregroundColor(.textMain)
                .padding(10)
            HStack {
                Spacer()
                Text(date.formattedTime())
                    .font(.appTextHeading)
                    .foregroundColor(.textSecondary)
            }
        }
        .padding([.top, .leading, .trailing], 20)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
        .background(Color.backgroundItem)
        .clipShape(UnevenRoundedCorners(
            tl: location.topRadius,
            bl: location.bottomRadius,
            br: Metrics.chatMessageRadiusLarge,
            tr: Metrics.chatMessageRadiusLarge
        ))
    }
}

public struct MessagePayment: View {
    
    public let verb: Chat.Verb
    public let amount: KinAmount
    public let location: MessageSemanticLocation
    
    private let font: Font = .appTextMedium
    
    // MARK: - Init -
        
    public init(verb: Chat.Verb, amount: KinAmount, location: MessageSemanticLocation) {
        self.verb = verb
        self.amount = amount
        self.location = location
    }
    
    // MARK: - Body -
    
    public var body: some View {
        VStack(spacing: 10) {
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
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color.backgroundItem)
        .clipShape(UnevenRoundedCorners(
            tl: location.topRadius,
            bl: location.bottomRadius,
            br: Metrics.chatMessageRadiusLarge,
            tr: Metrics.chatMessageRadiusLarge
        ))
    }
}

public enum MessageSemanticLocation {
    
    case standalone
    case beginning
    case middle
    case end
    
    static func forIndex(_ index: Int, count: Int) -> MessageSemanticLocation {
        if count < 2 {
            return .standalone
        }
        
        if index == 0 {
            return .beginning
        } else if index >= count - 1 {
            return .end
        } else {
            return .middle
        }
    }
    
    var topRadius: CGFloat {
        switch self {
        case .standalone, .beginning:
            Metrics.chatMessageRadiusLarge
        case .middle, .end:
            Metrics.chatMessageRadiusSmall
        }
    }
    
    var bottomRadius: CGFloat {
        switch self {
        case .standalone, .end:
            Metrics.chatMessageRadiusLarge
        case .middle, .beginning:
            Metrics.chatMessageRadiusSmall
        }
    }
}

public struct FiatField: View {
    
    public let size: Size
    public let amount: KinAmount
    
    public init(size: Size, amount: KinAmount) {
        self.size = size
        self.amount = amount
    }
    
    public var body: some View {
        HStack(spacing: size.spacing) {
            Flag(style: amount.rate.currency.flagStyle, size: .none)
                .aspectRatio(contentMode: .fit)
                .frame(width: size.uiFont.lineHeight * 0.8)
            
            Text(amount.kin.formattedFiat(rate: amount.rate, showOfKin: true))
                .padding(.leading, 0)
                .lineLimit(1)
                .minimumScaleFactor(0.3)
                .layoutPriority(10)
        }
        .font(size.font)
    }
    
    public enum Size {
        
        case small
        case large
        
        fileprivate var spacing: CGFloat {
            switch self {
            case .small:
                return 10
            case .large:
                return 12
            }
        }
        
        fileprivate var font: Font {
            switch self {
            case .small:
                return .appTextMedium
            case .large:
                return .appDisplaySmall
            }
        }
        
        fileprivate var uiFont: UIFont {
            switch self {
            case .small:
                return .appTextMedium
            case .large:
                return .appDisplaySmall
            }
        }
    }
}

// MARK: - Previews -

struct MessageList_Previews: PreviewProvider {
    static var previews: some View {
        Background(color: .backgroundMain) {
            MessageList(
                messages: [
                    Chat.Message(
                        id: .mock2,
                        date: .now,
                        contents: [
                            .localized("Welcome bonus! You've received a gift in Kin."),
                            .kin(
                                .partial(Fiat(
                                    currency: .kin,
                                    amount: 5.00
                                )), .returned
                            ),
                            .sodiumBox(
                                EncryptedData(
                                    peerPublicKey: .mock,
                                    nonce: .init(),
                                    encryptedData: .init()
                                )
                            )
                        ]
                    )
                ],
                exchange: .mock
            )
        }
    }
}
