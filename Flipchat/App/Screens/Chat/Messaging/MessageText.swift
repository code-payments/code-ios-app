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
    
    let messageID: UUID
    let state: Chat.Message.State
    let name: String
    let avatarData: Data
    let text: String
    let date: Date
    let isReceived: Bool
    let isHost: Bool
    let isBlocked: Bool
    let hasTipFromSelf: Bool
    let offStage: Bool
    let kinTips: Kin
    let deletionState: MessageDeletion?
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
        
    init(messageID: UUID, state: Chat.Message.State, name: String, avatarData: Data, text: String, date: Date, isReceived: Bool, isHost: Bool, isBlocked: Bool, hasTipFromSelf: Bool, offStage: Bool, kinTips: Kin, deletionState: MessageDeletion?, replyingTo: ReplyingTo?, location: MessageSemanticLocation, action: @escaping (MessageAction) -> Void, @ViewBuilder menu: @escaping () -> MenuItems) {
        self.messageID = messageID
        self.state = state
        self.name = name
        self.avatarData = avatarData
        self.text = text
        self.date = date
        self.isReceived = isReceived
        self.isHost = isHost
        self.isBlocked = isBlocked
        self.hasTipFromSelf = hasTipFromSelf
        self.offStage = offStage
        self.kinTips = kinTips
        self.deletionState = deletionState
        self.replyingTo = replyingTo
        self.location = location
        self.action = action
        self.menu = menu
    }
    
    var body: some View {
        HStack(alignment: .top) {
            if isReceived {
                if shouldShowAvatar {
                    UserGeneratedAvatar(
                        data: avatarData,
                        diameter: 35,
                        isHost: isHost
                    )
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
                    messageID: messageID,
                    state: state,
                    text: text,
                    date: date,
                    isReceived: isReceived,
                    isBlocked: isBlocked,
                    hasTipFromSelf: hasTipFromSelf,
                    offStage: offStage,
                    kinTips: kinTips,
                    deletionState: deletionState,
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
    let deletion: ReferenceDeletion?
    let action: () -> Void
}

// MARK: - MessageBubble -

struct MessageBubble: View {
    
    let messageID: UUID
    let state: Chat.Message.State
    let rawText: String
    let text: String
    let date: Date
    let isReceived: Bool
    let isBlocked: Bool
    let hasTipFromSelf: Bool
    let offStage: Bool
    let kinTips: Kin
    let deletionState: MessageDeletion?
    let replyingTo: ReplyingTo?
    let action: (MessageAction) -> Void
    let location: MessageSemanticLocation
    let isOnlyEmoji: Bool
    
    private var hasTips: Bool {
        kinTips > 0
    }
    
    private var isDeleted: Bool {
        deletionState != nil
    }
    
    private var spacing: CGFloat {
        if isOnlyEmoji {
            return 0
        } else {
            return 4
        }
    }
    
    private var messageOpacity: CGFloat {
        isBlocked || isDeleted ? 0.6 : 1.0
    }
    
    private var backgroundColor: Color {
        isReceived ? Color.backgroundMessageReceived : Color.backgroundMessageSent
    }
    
    // MARK: - Init -
    
    init(messageID: UUID, state: Chat.Message.State, text: String, date: Date, isReceived: Bool, isBlocked: Bool, hasTipFromSelf: Bool, offStage: Bool, kinTips: Kin, deletionState: MessageDeletion?, replyingTo: ReplyingTo?, action: @escaping (MessageAction) -> Void, location: MessageSemanticLocation) {
        self.messageID = messageID
        self.state = state
        self.rawText = text
        self.text = Self.adjusted(text: text, isBlocked: isBlocked, deletionState: deletionState)
        self.date = date
        self.isReceived = isReceived
        self.isBlocked = isBlocked
        self.hasTipFromSelf = hasTipFromSelf
        self.offStage = offStage
        self.kinTips = kinTips
        self.deletionState = deletionState
        self.replyingTo = replyingTo
        self.action = action
        self.location = location
        self.isOnlyEmoji = text.isOnlyEmoji
    }
    
    static func adjusted(text: String, isBlocked: Bool, deletionState: DeletionState?) -> String {
        if let deletionState {
            if deletionState.isSelf {
                return "Message deleted by you"
            } else if deletionState.isSender {
                var byUser = ""
                if let name = deletionState.senderName {
                    byUser = " by \(name)"
                }
                return "Message deleted\(byUser)"
            } else {
                return "Message deleted by host"
            }
        }
        
        guard !isBlocked else {
            return "Blocked message"
        }
        
        return text
    }
    
    // MARK: - Body -
    
    var body: some View {
        if isDeleted {
            bubbleContent()
                .italic()
                .overlay {
                    cornerClip(location: location)
                        .strokeBorder(Color.backgroundMessageSent, lineWidth: 2)
                }
            
        } else if offStage {
            bubbleContent()
                .background(Color.backgroundMain)
                .overlay {
                    cornerClip(location: location)
                        .strokeBorder(Color.actionSecondary, style: .init(lineWidth: 2, dash: [2, 2], dashPhase: 0))
                }
            
        } else {
            bubbleContent()
                .background(backgroundColor)
                .clipShape(
                    cornerClip(location: location)
                )
        }
    }
    
    @ViewBuilder private func bubbleContent() -> some View {
        if text.count < 10 && !hasTips {
            compactBubble()
        } else {
            standardBubble()
        }
    }
    
    @ViewBuilder private func compactBubble() -> some View {
        ///
        /// The Overlay Maneuver
        ///
        /// The Goal: The point of this tactic is to expand the
        /// underlying content width-wise but only up to
        /// the maximum width of the widest child. We can't
        /// use a spacer or similar approach because it will
        /// expand to the full width of the container
        ///
        /// How it works: The content is provided by a builder
        /// and it determines the overall size of this container
        /// VStack. We don't actually want to show this content,
        /// it's here just to determine the size so opacity 0.
        /// Next, we overlay the same content in the same container
        /// and pass in the `expand` flag. The child views will
        /// then use this flag to max out all relevant component
        /// widths so they always fill the container.
        ///
        VStack(alignment: .leading, spacing: spacing) {
            content(compact: true)
        }
        .opacity(0)
        .overlay {
            VStack(alignment: .leading, spacing: spacing) {
                content(compact: true, expand: true)
            }
            .frame(maxWidth: .infinity)
        }
        .padding([.horizontal], 10)
        .padding([.vertical], 8)
    }
    
    @ViewBuilder private func standardBubble() -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            content(compact: false)
        }
        .opacity(0)
        .overlay {
            VStack(alignment: .leading, spacing: spacing) {
                content(compact: false, expand: true)
            }
            .frame(maxWidth: .infinity)
        }
        .padding([.horizontal], 11)
        .padding([.vertical], 11)
    }
    
    @ViewBuilder private func content(compact: Bool, expand: Bool = false) -> some View {
        if let replyingTo, !isDeleted {
            MessageReplyBannerCompact(
                name: replyingTo.name,
                content: Self.adjusted(
                    text: replyingTo.content,
                    isBlocked: false,
                    deletionState: replyingTo.deletion
                ),
                expand: expand,
                deleted: replyingTo.deletion != nil
            ) {
                replyingTo.action()
            }
            .padding(.bottom, 3)
            .opacity(messageOpacity)
        }
        
        if compact {
            HStack(alignment: .bottom) {
                innerContent(compact: true, expand: expand)
            }
        } else {
            innerContent(compact: false, expand: expand)
        }
    }
    
    @ViewBuilder private func innerContent(compact: Bool, expand: Bool = false) -> some View {
        Text(parse(text: text))
            .font(.appTextMessage)
//            .font(isOnlyEmoji ? .appDisplayMedium : .appTextMessage)
            .foregroundColor(.textMain)
            .opacity(messageOpacity)
            .multilineTextAlignment(.leading)
            .environment(\.openURL, OpenURLAction { url in
                handleURL(url)
            })
            .layoutPriority(1)
            .if(expand) { $0
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        
        if hasTips && !isDeleted {
            HStack(alignment: .bottom) {
                TipAnnotation(kin: kinTips, isFilled: hasTipFromSelf) {
                    action(.showTippers(MessageID(uuid: messageID)))
                }
                
                if expand {
                    Spacer()
                }
                
                TimestampView(state: state, date: date, isReceived: isReceived)
            }
            .foregroundStyle(Color.textMain)
            .padding(.top, 4)
            
        } else {
            TimestampView(state: state, date: date, isReceived: isReceived)
                .fixedSize(horizontal: true, vertical: false)
                .if(expand && !compact) { $0
                    // Don't expand for compact formats
                    // because we want the text to fill
                    // all the space
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
        }
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
    
    // MARK: - Parse -
    
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
        let rules: [NSRegularExpression] = [
            .matchRoomHashtag,
//            .matchRoomSpelled,
        ]
        
        rules.forEach {
            let matches = $0.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
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
}

extension NSRegularExpression {
    static let matchRoomHashtag = try! NSRegularExpression(pattern: "#(\\d+)", options: [])
    static let matchRoomSpelled = try! NSRegularExpression(pattern: "[rR]oom ?(\\d+)", options: [])
}

#Preview {
    Background(color: .backgroundMain) {
        VStack {
            Spacer()
            MessageText(
                messageID: UUID(),
                state: .delivered,
                name: "Bob",
                avatarData: Data([0,0,0,0,0,0,0,0]),
                text: "Hey",
                date: .now,
                isReceived: true,
                isHost: false,
                isBlocked: false,
                hasTipFromSelf: false,
                offStage: false,
                kinTips: 7,
                deletionState: nil,
                replyingTo: .init(
                    name: "Bob",
//                    content: "That's what I was trying to say before",
                    content: "🔥",
                    deletion: nil,
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
