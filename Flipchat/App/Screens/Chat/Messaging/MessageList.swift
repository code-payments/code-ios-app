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
    private var messages: [MessageDescription]
    private let action: (MessageAction) -> Void
    private let loadMore: () -> Void
    
    @Binding private var state: ListState
    
    // MARK: - Init -
    
    @MainActor
    init(state: Binding<ListState>, chatID: ChatID, userID: UserID, hostID: UserID, messages: [MessageRow], action: @escaping (MessageAction) -> Void = { _ in }, loadMore: @escaping () -> Void = {}) {
        _state = state
        self.chatID = chatID
        self.userID = userID
        self.hostID = hostID
        self.action = action
        self.loadMore = loadMore
        
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
                
                let message = messageContainer.row.message
                let isReceived = message.senderID != userID.uuid
                
                for (index, content) in message.contents.contents.enumerated() {
                    switch content {
                    case .text(let text):
                        container.append(
                            .init(
                                kind: .message(ID(uuid: message.serverID), isReceived, messageContainer.row, messageContainer.location),
                                content: text,
                                contentIndex: index
                            )
                        )
                        
                    case .announcement(let text):
                        container.append(
                            .init(
                                kind: .announcement(ID(uuid: message.serverID)),
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
                        Color.clear
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.backgroundMain)
                            .id(scrollViewTopID)
                            .frame(height: 1)
                            .onAppear {
                                loadMore()
                            }
                        
                        ForEach(messages) { description in
                            MessageRowView(kind: description.kind, width: description.messageWidth(in: g.size)) {
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
                    .scrollDismissesKeyboard(.never)
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
                top: 10,
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
                            return 10
                        }
                    }
                }(),
                leading: horizontal,
                bottom: location.isLast ? 10 : 0,
                trailing: horizontal
            )
            
        case .announcement:
            return .init(
                top: 10,
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
            
        case .message(_, let isReceived, let row, let location):
            let message = row.message
            let isFromSelf = message.senderID == userID.uuid
            let displayName = row.member.displayName ?? "Member"
            
            MessageText(
                state: message.state,
                name: displayName,
                avatarData: message.senderID?.data ?? Data([0, 0, 0, 0]),
                text: description.content,
                date: message.date,
                isReceived: isReceived,
                isHost: message.senderID == hostID.uuid,
                location: location
            )
            .contextMenu {
                Button {
                    action(.copy(description.content))
                } label: {
                    Label("Copy Message", systemImage: "doc.on.doc")
                }
                
                Divider()
                
                if let senderID = message.senderID, senderID != userID.uuid {
                    Button(role: .destructive) {
                        action(.reportMessage(UserID(data: senderID.data), MessageID(uuid: message.serverID)))
                    } label: {
                        Label("Report", systemImage: "exclamationmark.shield")
                    }
                }
                
                // Only if the current user is a host
                if !isFromSelf, userID == hostID, let senderID = message.senderID {
                    
                    Button(role: .destructive) {
                        action(.muteUser(displayName, UserID(data: senderID.data), chatID))
                    } label: {
                        Label("Mute", systemImage: "speaker.slash")
                    }
                }
            }
            
        case .announcement:
            MessageAnnouncement(text: description.content)
        }
    }
    
    private let scrollViewTopID    = "com.code.scrollView.topID"
    private let scrollViewBottomID = "com.code.scrollView.bottomID"
}

extension MessageList {
    public struct ListState {
        
        var scrollToBottomIndex: Int = 0
        
        init() {}
        
        mutating func scrollToBottom() {
            scrollToBottomIndex += 1
        }
    }
}

enum MessageAction {
    case copy(String)
    case muteUser(String, UserID, ChatID)
    case reportMessage(UserID, MessageID)
}

struct MessageDescription: Identifiable, Hashable, Equatable {
    enum Kind: Hashable, Equatable {
        case date(Date)
        case message(MessageID, Bool, MessageRow, MessageSemanticLocation)
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
    
    init(userID: UserID, date: Date, messages: [MessageRow]) {
        self.date = date
        self.messages = messages.assigningSemanticLocation(selfUserID: userID)
    }
}

struct MessageContainer: Identifiable, Hashable {
    
    var id: UUID {
        row.message.roomID
    }
    
    var location: MessageSemanticLocation
    var row: MessageRow
}

extension Array where Element == MessageRow {
    func groupByDay(userID: UserID) -> [MessageDateGroup] {
        
        let calendar = Calendar.current
        var container: [Date: [MessageRow]] = [:]

        forEach { row in
            let components = calendar.dateComponents([.year, .month, .day], from: row.message.date)
            if let date = calendar.date(from: components) {
                if container[date] == nil {
                    container[date] = [row]
                } else {
                    container[date]?.append(row)
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
        
        for (index, row) in messages.enumerated() {
            let message = row.message
            let previousSender = index > 0 ? messages[index - 1].message.senderID : nil
            let nextSender = index < messages.count - 1 ? messages[index + 1].message.senderID : nil
            
            let isReceived = message.senderID != selfUserID.uuid
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
                        row: row
                    )
                )
                
            } else {
                let location: MessageSemanticLocation = .standalone(.init(received: isReceived))
                containers.append(
                    MessageContainer(
                        location: location,
                        row: row
                    )
                )
            }
        }
        
        return containers
    }
}

private extension GeometryProxy {
    func messageWidth(for content: ContentContainer.Content) -> CGFloat {
        switch content {
        case .text:
            size.width * 0.80
        case .announcement:
            size.width * 1.00
        }
    }
}

// MARK: - MessageRow -

private struct MessageRowView<Content>: View where Content: View {
    
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

//#Preview {
//    NavigationStack {
//        Background(color: .backgroundMain) {
//            MessageList(state: .constant(.init()), chatID: .mock, userID: .mock3, hostID: .mock, messages: [
//                .init(
//                    serverID: UUID(),
//                    chatID: UUID(),
//                    date: .now,
//                    state: .delivered,
//                    senderID: ID.mock.uuid,
//                    isDeleted: false,
//                    contents: [.text("Hey")]
//                ),
//                .init(
//                    serverID: UUID(),
//                    chatID: UUID(),
//                    date: .now,
//                    state: .delivered,
//                    senderID: ID.mock.uuid,
//                    isDeleted: false,
//                    contents: [.text("How's it going?")]
//                ),
//                .init(
//                    serverID: UUID(),
//                    chatID: UUID(),
//                    date: .now,
//                    state: .delivered,
//                    senderID: ID.mock.uuid,
//                    isDeleted: false,
//                    contents: [.text("I was wondering if you're for dinner some time next week? Perhaps we can do lunch.")]
//                ),
//                .init(
//                    serverID: UUID(),
//                    chatID: UUID(),
//                    date: .now,
//                    state: .delivered,
//                    senderID: nil,
//                    isDeleted: false,
//                    contents: [.announcement("Bob joined")]
//                ),
//                .init(
//                    serverID: UUID(),
//                    chatID: UUID(),
//                    date: .now,
//                    state: .delivered,
//                    senderID: nil,
//                    isDeleted: false,
//                    contents: [.announcement("Something else happened that requires the attention of someone in this chat because it is a very long action")]
//                ),
//                .init(
//                    serverID: UUID(),
//                    chatID: UUID(),
//                    date: .now,
//                    state: .delivered,
//                    senderID: ID.mock3.uuid,
//                    isDeleted: false,
//                    contents: [.text("Sure")]
//                ),
//                .init(
//                    serverID: UUID(),
//                    chatID: UUID(),
//                    date: .now,
//                    state: .delivered,
//                    senderID: ID.mock.uuid,
//                    isDeleted: false,
//                    contents: [.text("Okay cool, tap here to book a reso https://www.google.com")]
//                ),
//                .init(
//                    serverID: UUID(),
//                    chatID: UUID(),
//                    date: .now,
//                    state: .delivered,
//                    senderID: ID.mock3.uuid,
//                    isDeleted: false,
//                    contents: [.text("Sounds good, let me know")]
//                ),
//                .init(
//                    serverID: UUID(),
//                    chatID: UUID(),
//                    date: .now,
//                    state: .delivered,
//                    senderID: ID.mock.uuid,
//                    isDeleted: false,
//                    contents: [.text("Will do!")]
//                ),
//            ])
//        }
//        .navigationTitle("Chat")
//        .navigationBarTitleDisplayMode(.inline)
//    }
//}
