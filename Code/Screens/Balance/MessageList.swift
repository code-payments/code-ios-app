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
    
    private let useV2: Bool
    private let showThank: Bool
    
    // MARK: - Init -
    
    init(messages: [Chat.Message], exchange: Exchange, useV2: Bool = false, showThank: Bool = false) {
        self.messages = messages.groupByDay()
        self.exchange = exchange
        self.useV2 = useV2
        self.showThank = showThank
    }
    
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
    @ViewBuilder private func messageGroup(group: MessageGroup, geometry: GeometryProxy) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MessageTitle(text: group.date.formattedRelatively())
            
            ForEach(group.messages) { message in
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(message.contents.enumerated()), id: \.element) { index, content in
                        
                        MessageRow(width: geometry.messageWidth(for: content), isReceived: message.isReceived) {
                            switch content {
                            case .localized(let key):
                                MessageText(
                                    text: key.localizedStringByKey,
                                    date: message.date,
                                    isReceived: message.isReceived,
                                    location: .forIndex(index, count: message.contents.count)
                                )
                                
                            case .decrypted(let content):
                                MessageText(
                                    text: content,
                                    date: message.date,
                                    isReceived: message.isReceived,
                                    location: .forIndex(index, count: message.contents.count)
                                )
                                
                            case .kin(let amount, let verb):
                                if let rate = rate(for: amount.currency) {
                                    let amount = amount.amountUsing(rate: rate)
                                    
                                    if useV2 {
                                        MessagePaymentV2(
                                            verb: verb,
                                            amount: amount,
                                            isReceived: message.isReceived,
                                            date: message.date,
                                            location: .forIndex(index, count: message.contents.count),
                                            showThank: showThank
                                        )
                                    } else {
                                        MessagePayment(
                                            verb: verb,
                                            amount: amount,
                                            isReceived: message.isReceived,
                                            date: message.date,
                                            location: .forIndex(index, count: message.contents.count),
                                            showThank: showThank
                                        )
                                    }
                                } else {
                                    // If a rate for this currency isn't found, we can't
                                    // represent the value so we fallback to a Kin amount
                                    MessagePayment(
                                        verb: .unknown,
                                        amount: KinAmount(kin: 0, rate: .oneToOne),
                                        isReceived: message.isReceived,
                                        date: message.date,
                                        location: .forIndex(index, count: message.contents.count),
                                        showThank: showThank
                                    )
                                }
                                
                            case .sodiumBox:
                                MessageEncrypted(
                                    date: message.date,
                                    isReceived: message.isReceived,
                                    location: .forIndex(index, count: message.contents.count)
                                )
                                
                            case .thankYou:
                                MessageAction(text: content.localizedText)
                                
                            case .tip(_, let amount):
                                if let rate = rate(for: amount.currency) {
                                    let amount = amount.amountUsing(rate: rate)
                                    let formatted = amount.kin.formattedFiat(rate: amount.rate, showOfKin: true)
                                    
                                    MessageAction(text: "\(content.localizedText) \(formatted)")
                                    
                                } else {
                                    MessageAction(text: content.localizedText)
                                }
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
    func messageWidth(for content: Chat.Content) -> CGFloat {
        switch content {
        case .localized, .kin, .sodiumBox, .decrypted:
            return size.width * 0.70
        case .thankYou, .tip:
            return size.width
        }
    }
}

// MARK: - MessageTitle -

public struct MessageTitle: View {
    
    public let text: String
        
    public init(text: String) {
        self.text = text
    }
    
    public var body: some View {
        HStack {
            Spacer()
            Text(text)
                .font(.appTextHeading)
                .foregroundColor(.textMain)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.backgroundMessageReceived)
                .cornerRadius(99)
            Spacer()
        }
    }
}

// MARK: - MessageAction -

public struct MessageAction: View {
    
    public let text: String
        
    public init(text: String) {
        self.text = text
    }
    
    public var body: some View {
        HStack {
            Spacer()
            Text(text)
                .font(.appTextHeading)
                .foregroundColor(.textMain)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.backgroundMessageReceived)
                .cornerRadius(99)
            Spacer()
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

// MARK: - MessageText -

public struct MessageText: View {
    
    public let text: String
    public let date: Date
    public let isReceived: Bool
    public let location: MessageSemanticLocation
        
    public init(text: String, date: Date, isReceived: Bool, location: MessageSemanticLocation) {
        self.text = text
        self.date = date
        self.isReceived = isReceived
        self.location = location
    }
    
    public var body: some View {
        Group {
            if text.count < 10 {
                HStack(alignment: .bottom) {
                    Text(text)
                        .font(.appTextMessage)
                        .foregroundColor(.textMain)
                        .multilineTextAlignment(.leading)
                    
                    TimestampView(date: date, isReceived: isReceived)
                }
                .padding([.leading, .trailing, .top], 10)
                .padding(.bottom, 8)
                
            } else {
                VStack(alignment: .trailing, spacing: 5) {
                    Text(text)
                        .font(.appTextMessage)
                        .foregroundColor(.textMain)
                        .multilineTextAlignment(.leading)
                    
                    TimestampView(date: date, isReceived: isReceived)
                }
                .padding([.leading, .trailing, .top], 10)
                .padding(.bottom, 8)
            }
        }
        .background(isReceived ? Color.backgroundMessageReceived : Color.backgroundMessageSent)
        .clipShape(
            cornerClip(
                isReceived: isReceived,
                location: location
            )
        )
    }
}

// MARK: - MessagePayment -

public struct MessagePayment: View {
    
    public let verb: Chat.Verb
    public let amount: KinAmount
    public let isReceived: Bool
    public let date: Date
    public let location: MessageSemanticLocation
    public let showThank: Bool
    
    private let font: Font = .appTextMedium
    
    @State private var isThanked: Bool = false
        
    public init(verb: Chat.Verb, amount: KinAmount, isReceived: Bool, date: Date, location: MessageSemanticLocation, showThank: Bool) {
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
            VStack(spacing: 4) {
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
            .padding(.top, 16)
            .padding(.bottom, 6)
            .padding(.horizontal, 16)
            
            if showButtons {
                HStack(spacing: 8) {
                    CodeButton(style: .filledThin, title: "🙏  Thank", disabled: isThanked) {
                        isThanked.toggle()
                    }
                    CodeButton(style: .filledThin, title: "Message") {
                        // Nothing for now
                    }
                }
                .padding(.horizontal, 4)
            }
            
            TimestampView(date: date, isReceived: isReceived)
                .padding(.vertical, 2)
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

public struct MessagePaymentV2: View {
    
    public let verb: Chat.Verb
    public let amount: KinAmount
    public let isReceived: Bool
    public let date: Date
    public let location: MessageSemanticLocation
    public let showThank: Bool
    
    private let font: Font = .appTextMedium
    
    @State private var isThanked: Bool = false
        
    public init(verb: Chat.Verb, amount: KinAmount, isReceived: Bool, date: Date, location: MessageSemanticLocation, showThank: Bool) {
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
            VStack( spacing: 6) {
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
            
            TimestampView(date: date, isReceived: isReceived)
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

// MARK: - MessageEncrypted -

public struct MessageEncrypted: View {
    
    public let date: Date
    public let isReceived: Bool
    public let location: MessageSemanticLocation
        
    public init(date: Date, isReceived: Bool, location: MessageSemanticLocation) {
        self.date = date
        self.isReceived = isReceived
        self.location = location
    }
    
    public var body: some View {
        VStack(spacing: 7) {
            Image.system(.lockDashed)
                .font(.default(size: 30))
                .foregroundColor(.textMain)
                .padding(15)
            HStack {
                Spacer()
                Text(date.formattedTime())
                    .font(.appTextHeading)
                    .foregroundColor(.textSecondary)
            }
        }
        .padding([.top, .leading, .trailing], 12)
        .padding(.bottom, 8)
        .frame(width: 140)
        .background(isReceived ? Color.backgroundMessageReceived : Color.backgroundMessageSent)
        .clipShape(
            cornerClip(
                isReceived: isReceived,
                location: location
            )
        )
    }
}

// MARK: - MessageItem -

public struct MessageItem: View {
    
    public let text: String
    public let subtitle: String
    public let isReceived: Bool
    public let location: MessageSemanticLocation
        
    public init(text: String, subtitle: String, isReceived: Bool, location: MessageSemanticLocation) {
        self.text = text
        self.subtitle = subtitle
        self.isReceived = isReceived
        self.location = location
    }
    
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
        .background(isReceived ? Color.backgroundMessageReceived : Color.backgroundMessageSent)
        .clipShape(
            cornerClip(
                isReceived: isReceived,
                location: location
            )
        )
    }
}

// MARK: - MessageSemanticLocation -

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
    
    var topLeftRadius: CGFloat {
        switch self {
        case .standalone, .beginning:
            Metrics.chatMessageRadiusLarge
        case .middle, .end:
            Metrics.chatMessageRadiusSmall
        }
    }
    
    var bottomLeftRadius: CGFloat {
        switch self {
        case .standalone, .end:
            Metrics.chatMessageRadiusLarge
        case .middle, .beginning:
            Metrics.chatMessageRadiusSmall
        }
    }
    
    var topRightRadius: CGFloat {
        switch self {
        case .standalone, .beginning:
            Metrics.chatMessageRadiusLarge
        case .middle, .end:
            Metrics.chatMessageRadiusSmall
        }
    }
    
    var bottomRightRadius: CGFloat {
        switch self {
        case .standalone, .end:
            Metrics.chatMessageRadiusLarge
        case .middle, .beginning:
            Metrics.chatMessageRadiusSmall
        }
    }
}

// MARK: - TimestampView -

struct TimestampView: View {
    
    let date: Date
    let isReceived: Bool
    
    init(date: Date, isReceived: Bool) {
        self.date = date
        self.isReceived = isReceived
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Text(date.formattedTime())
                .font(.appTextHeading)
                .foregroundColor(.textSecondary)
            if !isReceived {
                Image.asset(.statusDelivered)
            }
        }
    }
}

// MARK: - FiatField -

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

private extension View {
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
                messages: [
//                    Chat.Message(
//                        id: .random,
//                        date: .now,
//                        isReceived: nil,
//                        contents: [
//                            .tip(.received, .exact(
//                                KinAmount(
//                                    fiat: 100.00,
//                                    rate: Rate(
//                                        fx: 0.000016,
//                                        currency: .usd
//                                    )
//                                )
//                            ))
//                        ]
//                    ),
//                    Chat.Message(
//                        id: .random,
//                        date: .now,
//                        isReceived: nil,
//                        contents: [
//                            .thankYou(.sent),
//                        ]
//                    ),
                    Chat.Message(
                        id: .random,
                        date: .now,
                        isReceived: nil,
                        contents: [
                            .localized("Hi")
                        ]
                    ),
                    Chat.Message(
                        id: .random,
                        date: .now,
                        isReceived: false,
                        contents: [
                            .localized("Hello"),
                        ]
                    ),
                    Chat.Message(
                        id: .random,
                        date: .now,
                        isReceived: false,
                        contents: [
                            .localized("I'm sending you some Kin to pay you back for lunch earlier."),
                            .kin(
                                .partial(Fiat(
                                    currency: .cny,
                                    amount: 35.75
                                )), .sent
                            ),
                        ]
                    ),
                    Chat.Message(
                        id: .random,
                        date: .now,
                        isReceived: nil,
                        contents: [
                            .localized("Oh, thanks! I think you sent me too much, I'll send some back."),
                        ]
                    ),
                    Chat.Message(
                        id: .random,
                        date: .now,
                        isReceived: nil,
                        contents: [
                            .kin(
                                .partial(Fiat(
                                    currency: .cad,
                                    amount: 1.00
                                )), .tipReceived
                            ),
                        ]
                    ),
//                    Chat.Message(
//                        id: .random,
//                        date: .now,
//                        isReceived: nil,
//                        contents: [
//                            .sodiumBox(
//                                EncryptedData(
//                                    peerPublicKey: .mock,
//                                    nonce: .init(),
//                                    encryptedData: .init()
//                                )
//                            )
//                        ]
//                    ),
                ],
                exchange: .mock
            )
        }
    }
}
