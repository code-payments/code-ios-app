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
    
    let messages: [Chat.Message]
    let exchange: Exchange
    
    // MARK: - Init -
    
    init(messages: [Chat.Message], exchange: Exchange) {
        self.messages = messages
        self.exchange = exchange
    }
    
    // MARK: - Body -
    
    public var body: some View {
        ScrollBox(color: .backgroundMain) {
            GeometryReader { g in
                ScrollViewReader { scrollProxy in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 8) {
                            
                            ForEach(messages) { message in
                                MessageTitle(text: message.date.formattedRelatively())
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(Array(message.contents.enumerated()), id: \.element) { index, content in
                                        MessageRow(width: g.messageWidth) {
                                            switch content {
                                            case .localized(let key):
                                                MessageText(
                                                    text: key.localizedStringByKey,
                                                    location: .forIndex(index, count: message.contents.count)
                                                )
                                                
                                            case .kin(let amount, let verb):
                                                if let rate = exchange.rate(for: amount.currency) {
                                                    MessagePayment(
                                                        title: verb.localizedText,
                                                        amount: amount.amountUsing(rate: rate),
                                                        location: .forIndex(index, count: message.contents.count)
                                                    )
                                                } else {
                                                    MessagePayment(
                                                        title: "Rate Not Found",
                                                        amount: KinAmount(kin: 0, rate: .oneToOne),
                                                        location: .forIndex(index, count: message.contents.count)
                                                    )
                                                }
                                                
                                            case .sodiumBox:
                                                // TODO: Decrypt and show correct content
                                                MessageText(
                                                    text: content.localizedText,
                                                    location: .forIndex(index, count: message.contents.count)
                                                )
                                            }
                                        }
                                    }
                                }
                                .id(message.id)
                            }
                            
                            Spacer()
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onAppear {
                            if let lastMessage = messages.last {
                                scrollProxy.scrollTo(lastMessage.id, anchor: .top)
                            }
                        }
                    }
                }
            }
        }
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
                .font(.appTextCaption)
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
    public let location: MessageSemanticLocation
    
    // MARK: - Init -
        
    public init(text: String, location: MessageSemanticLocation) {
        self.text = text
        self.location = location
    }
    
    // MARK: - Body -
    
    public var body: some View {
        VStack(alignment: .leading) {
            Text(text)
                .font(.appTextSmall)
                .foregroundColor(.textMain)
                .multilineTextAlignment(.leading)
                .padding(12)
                .background(Color.backgroundItem)
                .clipShape(UnevenRoundedCorners(
                    tl: location.topRadius,
                    bl: location.bottomRadius,
                    br: Metrics.chatMessageRadiusLarge,
                    tr: Metrics.chatMessageRadiusLarge
                ))
//                .cornerRadius(Metrics.chatMessageRadiusLarge)
        }
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
//        .cornerRadius(Metrics.chatMessageRadiusLarge)
    }
}

public struct MessagePayment: View {
    
    public let title: String
    public let amount: KinAmount
    public let location: MessageSemanticLocation
    
    private let font: Font = .appTextMedium
    
    // MARK: - Init -
        
    public init(title: String, amount: KinAmount, location: MessageSemanticLocation) {
        self.title  = title
        self.amount = amount
        self.location = location
    }
    
    // MARK: - Body -
    
    public var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.appTextSmall)
                .foregroundColor(.textMain)
            
            FiatField(size: .large, amount: amount)
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
//        .cornerRadius(Metrics.chatMessageRadiusLarge)
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

private struct UnevenRoundedCorners: Shape {
    
    var tl: CGFloat = 0.0
    var bl: CGFloat = 0.0
    var br: CGFloat = 0.0
    var tr: CGFloat = 0.0

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let w = rect.size.width
        let h = rect.size.height

        // Make sure we do not exceed the size of the rectangle
        let tr = min(min(self.tr, h * 0.5), w * 0.5)
        let tl = min(min(self.tl, h * 0.5), w * 0.5)
        let bl = min(min(self.bl, h * 0.5), w * 0.5)
        let br = min(min(self.br, h * 0.5), w * 0.5)
        
        path.move(to: CGPoint(x: w / 2.0, y: 0))
        path.addLine(to: CGPoint(x: w - tr, y: 0))
        path.addArc(
            center: CGPoint(x: w - tr, y: tr),
            radius: tr,
            startAngle: Angle(degrees: -90), 
            endAngle: Angle(degrees: 0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: w, y: h - br))
        path.addArc(center: CGPoint(x: w - br, y: h - br), radius: br,
                    startAngle: Angle(degrees: 0), endAngle: Angle(degrees: 90), clockwise: false)
        path.addLine(to: CGPoint(x: bl, y: h))
        path.addArc(center: CGPoint(x: bl, y: h - bl), radius: bl,
                    startAngle: Angle(degrees: 90), endAngle: Angle(degrees: 180), clockwise: false)
        path.addLine(to: CGPoint(x: 0, y: tl))
        path.addArc(center: CGPoint(x: tl, y: tl), radius: tl,
                    startAngle: Angle(degrees: 180), endAngle: Angle(degrees: 270), clockwise: false)
        path.closeSubpath()

        return path
    }
}

private struct ChatBubble: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        let tailWidth: CGFloat = 10
        let tailHeight: CGFloat = 15
        let cornerRadius: CGFloat = 15
        
        // Start at the tail tip on the left
        path.move(to: CGPoint(x: tailWidth, y: rect.midY))

        // Line to start of tail arc
        path.addLine(to: CGPoint(x: tailWidth, y: rect.midY - tailHeight / 2))

        // Tail arc
        path.addQuadCurve(to: CGPoint(x: 0, y: rect.midY),
                          control: CGPoint(x: tailWidth / 2, y: rect.midY - tailHeight / 2))

        path.addQuadCurve(to: CGPoint(x: tailWidth, y: rect.midY + tailHeight / 2),
                          control: CGPoint(x: tailWidth / 2, y: rect.midY + tailHeight / 2))

        // Line to bottom left corner
        path.addLine(to: CGPoint(x: tailWidth, y: rect.maxY - cornerRadius))

        // Bottom left corner
        path.addArc(center: CGPoint(x: tailWidth + cornerRadius, y: rect.maxY - cornerRadius),
                    radius: cornerRadius,
                    startAngle: Angle(degrees: 180),
                    endAngle: Angle(degrees: 90),
                    clockwise: true)

        // Bottom line
        path.addLine(to: CGPoint(x: rect.maxX - cornerRadius, y: rect.maxY))

        // Bottom right corner
        path.addArc(center: CGPoint(x: rect.maxX - cornerRadius, y: rect.maxY - cornerRadius),
                    radius: cornerRadius,
                    startAngle: Angle(degrees: 90),
                    endAngle: Angle(degrees: 0),
                    clockwise: true)

        // Right line
        path.addLine(to: CGPoint(x: rect.maxX, y: cornerRadius))

        // Top right corner
        path.addArc(center: CGPoint(x: rect.maxX - cornerRadius, y: cornerRadius),
                    radius: cornerRadius,
                    startAngle: Angle(degrees: 0),
                    endAngle: Angle(degrees: 270),
                    clockwise: true)

        // Top line
        path.addLine(to: CGPoint(x: tailWidth + cornerRadius, y: 0))

        // Top left corner
        path.addArc(center: CGPoint(x: tailWidth + cornerRadius, y: cornerRadius),
                    radius: cornerRadius,
                    startAngle: Angle(degrees: 270),
                    endAngle: Angle(degrees: 180),
                    clockwise: true)

        // Close the path
        path.closeSubpath()

        return path
    }
}

// MARK: - Previews -

struct MessageList_Previews: PreviewProvider {
    static var previews: some View {
        Background(color: .backgroundMain) {
            MessageList(messages: [], exchange: .mock)
        }
    }
}
