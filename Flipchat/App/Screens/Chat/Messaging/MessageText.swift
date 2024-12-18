//
//  MessageText.swift
//  Code
//
//  Created by Dima Bart on 2024-07-02.
//

import SwiftUI
import CodeUI
import FlipchatServices

struct MessageText<MenuItems>: View where MenuItems: View {
    
    let state: Chat.Message.State
    let name: String
    let avatarData: Data
    let text: String
    let date: Date
    let isReceived: Bool
    let isHost: Bool
    let replyingTo: ReplyingTo?
    let location: MessageSemanticLocation
    let action: (MessageAction) -> Void
    let menu: () -> MenuItems
    
    private var shouldShowName: Bool {
        switch location {
        case .beginning, .standalone:
            return true
        case .middle, .end:
            return false
        }
    }
    
    private var shouldShowAvatar: Bool {
        switch location {
        case .beginning, .standalone:
            return true
        case .middle, .end:
            return false
        }
    }
    
    private var topPadding: CGFloat {
        switch location {
        case .beginning, .standalone:
            return 8
        case .middle, .end:
            return 0
        }
    }
        
    init(state: Chat.Message.State, name: String, avatarData: Data, text: String, date: Date, isReceived: Bool, isHost: Bool, replyingTo: ReplyingTo?, location: MessageSemanticLocation, action: @escaping (MessageAction) -> Void, @ViewBuilder menu: @escaping () -> MenuItems) {
        self.state = state
        self.name = name
        self.avatarData = avatarData
        self.text = text
        self.date = date
        self.isReceived = isReceived
        self.isHost = isHost
        self.replyingTo = replyingTo
        self.location = location
        self.action = action
        self.menu = menu
    }
    
    var body: some View {
        HStack(alignment: .top) {
            if isReceived {
                if shouldShowAvatar {
                    DeterministicAvatar(data: avatarData, diameter: 35)
                        .if(isHost) { $0
                            .overlay {
                                Image.asset(.crown)
                                    .position(x: 5, y: 5)
                            }
                        }
                        .padding(.top, 17)
                } else {
                    VStack {
                        
                    }
                    .frame(width: 35, height: 5)
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                if shouldShowName, isReceived {
                    Text(name)
                        .font(.appTextCaption)
                        .foregroundStyle(Color.textSecondary)
                        .padding(.leading, Metrics.chatMessageRadiusSmall)
                }
                
                MessageBubble(
                    state: state,
                    text: text,
                    date: date,
                    isReceived: isReceived,
                    replyingTo: replyingTo,
                    action: action,
                    location: location
                )
                .contextMenu {
                    menu()
                }
            }
        }
        .padding(.top, topPadding)
    }
}

struct ReplyingTo {
    let name: String
    let content: String
    let action: () -> Void
}

struct MessageBubble: View {
    
    let state: Chat.Message.State
    let text: String
    let date: Date
    let isReceived: Bool
    let replyingTo: ReplyingTo?
    let action: (MessageAction) -> Void
    let location: MessageSemanticLocation
    
    private let horizontalPadding: CGFloat = 11
    private let verticalPadding: CGFloat = 11
    
    var body: some View {
        Group {
            if text.count < 10 {
                VStack(alignment: .leading) {
                    if let replyingTo {
                        MessageReplyBannerCompact(
                            name: replyingTo.name,
                            content: replyingTo.content
                        ) {
                            replyingTo.action()
                        }
                    }
                    HStack(alignment: .bottom) {
                        Text(parse(text: text))
                            .font(.appTextMessage)
                            .foregroundColor(.textMain)
                            .multilineTextAlignment(.leading)
                        
                        // Expand the the message
                        // if there's a reply
                        if replyingTo != nil {
                            Spacer()
                        }
                        
                        TimestampView(state: state, date: date, isReceived: isReceived)
                    }
                }
                .padding([.horizontal], 10)
                .padding([.vertical], 8)
                
            } else {
                VStack(alignment: .leading) {
                    if replyingTo != nil {
                        // Create space for the reply banner
                        // but don't insert it here. We want
                        // to prevent from expanding the text
                        // bubble so we'll apply it as an overlay
                        Rectangle()
                            .fill(.clear)
                            .frame(width: 1, height: MessageReplyBannerCompact.height)
                    }
                    
                    VStack(alignment: .trailing, spacing: 5) {
                        Text(parse(text: text))
                            .font(.appTextMessage)
                            .foregroundColor(.textMain)
                            .multilineTextAlignment(.leading)
                            .environment(\.openURL, OpenURLAction { url in
                                handleURL(url)
                            })
                        
                        TimestampView(state: state, date: date, isReceived: isReceived)
                    }
                }
                .padding([.horizontal], horizontalPadding)
                .padding([.vertical], verticalPadding)
                .overlay {
                    if let replyingTo {
                        VStack(alignment: .leading) {
                            MessageReplyBannerCompact(
                                name: replyingTo.name,
                                content: replyingTo.content
                            ) {
                                replyingTo.action()
                            }
                            Spacer()
                        }
                        .padding([.horizontal], horizontalPadding)
                        .padding([.vertical], verticalPadding)
                    }
                }
            }
        }
        .background(isReceived ? Color.backgroundMessageReceived : Color.backgroundMessageSent)
        .clipShape(
            cornerClip(location: location)
        )
    }
    
    func handleURL(_ url: URL) -> OpenURLAction.Result {
        print("Handled URL: \(url.absoluteString)")
        if url.scheme == "fc" {
            let roomNumber = RoomNumber(url.host(percentEncoded: false)?.dropFirst(4) ?? "")
            if let roomNumber {
                action(.linkTo(roomNumber))
                return .handled
            } else {
                return .discarded
            }
            
        } else {
            return .systemAction
        }
    }
    
    private func parse(text: String) -> AttributedString {
        var string = AttributedString(text)
        
        findLinks(in: text, string: &string)
        findHashtags(in: text, string: &string)
        
        return string
    }
    
    private func findLinks(in text: String, string: inout AttributedString) {
        let types: NSTextCheckingResult.CheckingType = [.link, .phoneNumber, .regularExpression]
        
        guard let detector = try? NSDataDetector(types: types.rawValue) else {
            return
        }
        
        let matches = detector.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
        for match in matches {
            
            guard let range = Range(match.range, in: text) else {
                continue
            }
            
            guard let attributedRange = Range(range, in: string) else {
                continue
            }
            
            switch match.resultType {
            case .link:
                guard let url = match.url else {
                    break
                }
                
                string[attributedRange].link = url
                string[attributedRange].underlineStyle = .single
                
            case .phoneNumber:
                guard let phone = match.phoneNumber else {
                    break
                }
                
                string[attributedRange].link = URL(string: "tel:\(phone)")
                string[attributedRange].underlineStyle = .single
                
            default:
                break
            }
        }
    }
    
    private func findHashtags(in text: String, string: inout AttributedString) {
        guard let regex = try? NSRegularExpression(pattern: "#(\\d+)", options: []) else {
            return
        }
        
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
        for match in matches {
            guard let range = Range(match.range, in: text), let roomNumberRange = Range(match.range(at: 1), in: text) else {
                continue
            }
            
            let roomNumber = String(text[roomNumberRange])
            
            guard let attributedRange = Range(range, in: string) else {
                continue
            }
            
            string[attributedRange].link = URL(string: "fc://room\(roomNumber)")
            string[attributedRange].underlineStyle = .single
        }
    }
}

private struct WidthPreferenceKey: PreferenceKey {
    
    static let defaultValue: CGFloat = 0
    
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

#Preview {
    Background(color: .backgroundMain) {
        VStack {
            Spacer()
            MessageText(
                state: .delivered,
                name: "Bob",
                avatarData: Data([0,0,0,0,0,0,0,0]),
                text: "Hey",
                date: .now,
                isReceived: true,
                isHost: false,
                replyingTo: .init(
                    name: "Bob",
                    content: "That's what I was trying to say before",
                    action: {}
                ),
                location: .standalone(.received),
                action: { _ in },
                menu: {
                    Button {
                        /* action */
                    } label: {
                        Label("Copy Message", systemImage: "doc.on.doc")
                    }
                }
            )
            Rectangle()
                .fill(.black)
                .frame(height: 200)
                .frame(maxWidth: .infinity)
        }
        .padding(20)
    }
}
