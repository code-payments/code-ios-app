//
//  MessageList.swift
//  Code
//
//  Created by Dima Bart on 2023-10-06.
//

import SwiftUI
import FlipchatServices
import CodeUI

public struct MessageList: View {
    
    private let chatID: ChatID
    private let userID: UserID
    private let hostID: UserID
    private let action: (MessageAction) -> Void
    private var messages: [MessageDescription]
    
    @Binding private var state: State
    
    // MARK: - Init -
    
    @MainActor
    init(state: Binding<State>, chatID: ChatID, userID: UserID, hostID: UserID, action: @escaping (MessageAction) -> Void = { _ in }, messages: [pMessage]) {
        _state = state
        self.chatID = chatID
        self.userID = userID
        self.hostID = hostID
        self.action = action
        
        var container: [MessageDescription] = []
        for dateGroup in messages.groupByDay(userID: userID) {
            
            // Date
            container.append(
                .init(
                    kind: .date(dateGroup.date),
                    content: dateGroup.date.formattedRelatively(),
                    contentIndex: 0
                )
            )
            
            for messageContainer in dateGroup.messages {
                
                let message = messageContainer.message
                let isReceived = message.senderID != userID.data
                
                for (index, content) in message.contents.enumerated() {
                    switch content {
                    case .text(let text):
                        container.append(
                            .init(
                                kind: .message(ID(data: message.serverID), isReceived, message, messageContainer.location),
                                content: text,
                                contentIndex: index
                            )
                        )
                        
                    case .announcement(let text):
                        container.append(
                            .init(
                                kind: .announcement(ID(data: message.serverID)),
                                content: text,
                                contentIndex: index
                            )
                        )
                    }
                }
            }
        }
        
        self.messages = container
    }
    
    // MARK: - Actions -
    
    private func scrollToBottom(with proxy: ScrollViewProxy, animated: Bool) {
        scrollTo(
            id: scrollViewBottomID,
            proxy: proxy,
            animated: animated
        )
    }
    
    private func scrollTo(id: String, proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.easeOutFastest) {
                proxy.scrollTo(id, anchor: .center)
            }
        } else {
            proxy.scrollTo(id, anchor: .center)
        }
    }
    
    // MARK: - Body -
    
    public var body: some View {
        ScrollBox(color: .backgroundMain, ignoreEdges: []) {
            GeometryReader { g in
                ScrollViewReader { scrollProxy in
                    List {
                        ForEach(messages) { description in
                            MessageRow(kind: description.kind, width: description.messageWidth(in: g.size)) {
                                row(for: description)
//                                    .background(.green) // Diagnostics
                            }
                            .padding(padding(for: description))
//                            .background(.red) // Diagnostics
                            .listRowSpacing(0)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.backgroundMain)
                            .listRowInsets(.zero)
                            .scrollContentBackground(.hidden)
                        }
                        
                        // This invisible view creates a 44pt row
                        // at the very bottom of the list so we
                        // have to offset* the content with a -44 pad
                        Color.clear
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.backgroundMain)
                            .id(scrollViewBottomID)
                            .frame(height: 1)
                    }
                    .environment(\.defaultMinListRowHeight, 0)
                    .safeAreaInset(edge: .bottom, alignment: .center) {
                        Rectangle()
                            .fill(.red)
                            .frame(height: 40)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.bottom, -44) // <- offset*
                    .clipped()
                    .listStyle(.plain)
                    .onChange(of: state.scrollToBottomIndex) { _, _ in
                        scrollToBottom(with: scrollProxy, animated: true)
                    }
                    .onAppear {
                        scrollToBottom(with: scrollProxy, animated: false)
                    }
                }
            }
        }
    }
    
    private func padding(for description: MessageDescription) -> EdgeInsets {
        let horizontal: CGFloat = 20
        switch description.kind {
        case .date:
            return .init(
                top: 15,
                leading: horizontal,
                bottom: 0,
                trailing: horizontal
            )
            
        case .message(_, let isReceived, _, let location):
            return .init(
                top: {
                    if !location.isFirst {
                        return 2
                    } else {
                        if isReceived {
                            return 10
                        } else {
                            return 15
                        }
                    }
                }(),
                leading: horizontal,
                bottom: location.isLast ? 10 : 0,
                trailing: horizontal
            )
            
        case .announcement:
            return .init(
                top: 5,
                leading: horizontal,
                bottom: 10,
                trailing: horizontal
            )
        }
    }
    
    @ViewBuilder
    private func row(for description: MessageDescription) -> some View {
        switch description.kind {
        case .date(let date):
            MessageTitle(text: date.formattedRelatively())
            
        case .message(_, let isReceived, let message, let location):
            MessageText(
                state: message.state.state,
                name: message.userDisplayName,
                avatarData: message.senderID ?? Data([0, 0, 0, 0]),
                text: description.content,
                date: message.date,
                isReceived: isReceived,
                isHost: message.senderID == hostID.data,
                location: location
            )
            .contextMenu {
                Button {
                    action(.copy(description.content))
                } label: {
                    Label("Copy Message", systemImage: "doc.on.doc")
                }
                
                Divider()
                
                if let senderID = message.senderID, senderID != userID.data {
                    Button(role: .destructive) {
                        action(.reportMessage(UserID(data: senderID), MessageID(data: message.serverID)))
                    } label: {
                        Label("Report", systemImage: "exclamationmark.shield")
                    }
                }
                
                // Only if the current user is a host
                if userID == hostID, let senderID = message.senderID, let name = message.sender?.displayName {
                    
                    Button(role: .destructive) {
                        action(.removeUser(name, UserID(data: senderID), chatID))
                    } label: {
                        Label("Remove \(name)", systemImage: "person.slash")
                    }
                }
            }
            
        case .announcement:
            MessageAnnouncement(text: description.content)
        }
    }
    
    private let scrollViewBottomID = "com.code.scrollView.bottomID"
}

extension MessageList {
    public struct State {
        
        var scrollToBottomIndex: Int = 0
        
        init() {}
        
        mutating func scrollToBottom() {
            scrollToBottomIndex += 1
        }
    }
}

enum MessageAction {
    case copy(String)
    case removeUser(String, UserID, ChatID)
    case reportMessage(UserID, MessageID)
}

struct MessageDescription: Identifiable {
    enum Kind {
        case date(Date)
        case message(MessageID, Bool, pMessage, MessageSemanticLocation)
        case announcement(MessageID)
    }
    
    var id: String {
        switch kind {
        case .date(let date):
            return "\(date.timeIntervalSince1970)"
        case .message(let messageID, _, _, _):
            return messageID.data.hexString()
        case .announcement(let messageID):
            return messageID.data.hexString()
        }
    }
    
    let kind: Kind
    let content: String
    let contentIndex: Int
    
    func messageWidth(in size: CGSize) -> CGFloat {
        switch kind {
        case .date, .announcement:
            size.width * 1.0
        case .message:
            size.width * 0.8
        }
    }
}

struct MessageDateGroup: Identifiable, Hashable {
    
    var id: Date {
        date
    }
    
    var date: Date
    var messages: [MessageContainer]
    
    init(userID: UserID, date: Date, messages: [pMessage]) {
        self.date = date
        self.messages = messages.assigningSemanticLocation(selfUserID: userID)
    }
}

struct MessageContainer: Identifiable, Hashable {
    
    var id: Data {
        message.serverID
    }
    
    var location: MessageSemanticLocation
    var message: pMessage
}

extension Array where Element == pMessage {
    func groupByDay(userID: UserID) -> [MessageDateGroup] {
        
        let calendar = Calendar.current
        var container: [Date: [pMessage]] = [:]

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
            MessageDateGroup(userID: userID, date: $0, messages: container[$0] ?? [])
        }

        return groupedMessages
    }
    
    func assigningSemanticLocation(selfUserID: UserID) -> [MessageContainer] {
        var containers: [MessageContainer] = []
        let messages = self
        
        for (index, message) in messages.enumerated() {
            let previousSender = index > 0 ? messages[index - 1].senderID : nil
            let nextSender = index < messages.count - 1 ? messages[index + 1].senderID : nil
            
            let isReceived = message.senderID != selfUserID.data
            if let senderID = message.senderID {
                
                let location: MessageSemanticLocation
                
                if senderID != previousSender && senderID != nextSender {
                    location = .standalone(.init(received: isReceived))
                    
                } else if senderID != previousSender && senderID == nextSender {
                    location = .beginning(.init(received: isReceived))
                    
                } else if senderID == previousSender && senderID == nextSender {
                    location = .middle(.init(received: isReceived))
                    
                } else {
                    location = .end(.init(received: isReceived))
                }
                
                containers.append(
                    MessageContainer(
                        location: location,
                        message: message
                    )
                )
                
            } else {
                let location: MessageSemanticLocation = .standalone(.init(received: isReceived))
                containers.append(
                    MessageContainer(
                        location: location,
                        message: message
                    )
                )
            }
        }
        
        return containers
    }
}

private extension GeometryProxy {
    func messageWidth(for content: pMessageContent) -> CGFloat {
        switch content {
        case .text:
            size.width * 0.80
        case .announcement:
            size.width * 1.00
        }
    }
}

// MARK: - MessageRow -

struct MessageRow<Content>: View where Content: View {
    
    private let kind: MessageDescription.Kind
    private let width: CGFloat
    private let content: () -> Content
    
    private var vAlignment: HorizontalAlignment {
        switch kind {
        case .date:
            return .center
        case .message(_, let isReceived, _, _):
            return isReceived ? .leading : .trailing
        case .announcement:
            return .center
        }
    }
    
    private var alignment: Alignment {
        switch kind {
        case .date:
            return .top
        case .message(_, let isReceived, _, _):
            return isReceived ? .leading : .trailing
        case .announcement:
            return .bottom
        }
    }
    
    init(kind: MessageDescription.Kind, width: CGFloat, @ViewBuilder content: @escaping () -> Content) {
        self.kind = kind
        self.width = width
        self.content = content
    }
    
    var body: some View {
        VStack(alignment: vAlignment) {
            HStack {
                switch kind {
                case .date, .announcement:
                    content()
                    
                case .message(_, let isReceived, _, _):
                    if isReceived {
                        content()
                        Spacer()
                    } else {
                        Spacer()
                        content()
                    }
                }
            }
            .frame(maxWidth: width, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: alignment)
    }
}

extension View {
    func cornerClip(smaller: Bool = false, location: MessageSemanticLocation) -> some Shape {
        let m = (smaller ? 0.65 : 1.0)
        return UnevenRoundedCorners(
            tl: location.topLeftRadius     * m,
            bl: location.bottomLeftRadius  * m,
            br: location.bottomRightRadius * m,
            tr: location.topRightRadius    * m
        )
    }
}

import SwiftData

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: pChat.self, pMessage.self, pMember.self, pPointer.self, configurations: config)
    
    NavigationStack {
        Background(color: .backgroundMain) {
            MessageList(state: .constant(.init()), chatID: .mock, userID: .mock3, hostID: .mock, messages: [
                .init(
                    serverID: .tempID,
                    date: .now,
                    state: .delivered,
                    senderID: PublicKey.mock.data,
                    isDeleted: false,
                    contents: [.text("Hey")]
                ),
                .init(
                    serverID: .tempID,
                    date: .now,
                    state: .delivered,
                    senderID: PublicKey.mock.data,
                    isDeleted: false,
                    contents: [.text("How's it going")]
                ),
                .init(
                    serverID: .tempID,
                    date: .now,
                    state: .delivered,
                    senderID: PublicKey.mock.data,
                    isDeleted: false,
                    contents: [.text("Hey how's it going Hey how's it going Hey how's it going Hey how's it going Hey how's it going")]
                ),
                .init(
                    serverID: .tempID,
                    date: .now,
                    state: .delivered,
                    senderID: nil,
                    isDeleted: false,
                    contents: [.announcement("Bob joined")]
                ),
                .init(
                    serverID: .tempID,
                    date: .now,
                    state: .delivered,
                    senderID: nil,
                    isDeleted: false,
                    contents: [.announcement("Something else happened that requires the attention of someone in this chat because it is a very long action")]
                ),
                .init(
                    serverID: .tempID,
                    date: .now,
                    state: .delivered,
                    senderID: PublicKey.mock.data,
                    isDeleted: false,
                    contents: [.text("Yeah that sounds good to me")]
                ),
                .init(
                    serverID: .tempID,
                    date: .now,
                    state: .delivered,
                    senderID: ID.mock3.data,
                    isDeleted: false,
                    contents: [.text("Hey")]
                ),
                .init(
                    serverID: .tempID,
                    date: .now,
                    state: .delivered,
                    senderID: ID.mock3.data,
                    isDeleted: false,
                    contents: [.text("That's exactly what I thought")]
                ),
                .init(
                    serverID: .tempID,
                    date: .now,
                    state: .delivered,
                    senderID: PublicKey.mock.data,
                    isDeleted: false,
                    contents: [.text("Yeah that sounds good to me")]
                ),
                .init(
                    serverID: .tempID,
                    date: .now,
                    state: .delivered,
                    senderID: PublicKey.mock.data,
                    isDeleted: false,
                    contents: [.text("Yeah that sounds good to me")]
                ),
            ])
        }
        .navigationTitle("Chat")
    }
    .modelContainer(container)
}
