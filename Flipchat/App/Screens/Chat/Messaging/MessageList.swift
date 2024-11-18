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
    
    private let userID: UserID
    private let hostID: UserID

    private var messages: [MessageDateGroup]
    
    @Binding private var state: State
    
    // MARK: - Init -
    
    @MainActor
    init(state: Binding<State>, userID: UserID, hostID: UserID, messages: [pMessage]) {
        _state = state
        self.userID = userID
        self.hostID = hostID
        self.messages = messages.groupByDay(userID: userID)
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
                        ForEach(messages) { group in
                            messageDateGroup(group: group, geometry: g)
                        }
                        .padding(.bottom, 5)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.backgroundMain)
                        .scrollContentBackground(.hidden)
                        
                        // This invisible view creates a 44pt row
                        // at the very bottom of the list so we
                        // have to offset* the content with a -44 pad
                        Color.clear
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.backgroundMain)
                            .id(scrollViewBottomID)
                            .frame(height: 1)
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
    
    @MainActor
    @ViewBuilder private func messageDateGroup(group: MessageDateGroup, geometry: GeometryProxy) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            MessageTitle(text: group.date.formattedRelatively())
            
            ForEach(group.messages) { container in // MessageContainer
                let message = container.message
                let isReceived = message.senderID != userID.data
                
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(message.contents.enumerated()), id: \.element) { index, content in
                        MessageRow(width: geometry.messageWidth(), isReceived: isReceived) {
                            MessageText(
                                state: message.state.state,
                                name: message.userDisplayName,
                                avatarData: message.senderID ?? Data([0, 0, 0, 0]),
                                text: content,
                                date: message.date,
                                isReceived: isReceived,
                                isHost: message.senderID == hostID.data,
                                location: container.location
                            )
                        }
                    }
                }
            }
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
            
            let location: MessageSemanticLocation
            
            if message.senderID != previousSender && message.senderID != nextSender {
                location = .standalone(.init(received: isReceived))
                
            } else if message.senderID != previousSender && message.senderID == nextSender {
                location = .beginning(.init(received: isReceived))
                
            } else if message.senderID == previousSender && message.senderID == nextSender {
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
        }
        
        return containers
    }
}

private extension GeometryProxy {
    func messageWidth() -> CGFloat {
        size.width * 0.80
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
            MessageList(state: .constant(.init()), userID: .mock, hostID: .mock, messages: [
                .init(
                    serverID: Data([1]),
                    date: .now,
                    state: .delivered,
                    senderID: nil,
                    isDeleted: false,
                    contents: ["Hey how's it going"]
                ),
                .init(
                    serverID: Data([1]),
                    date: .now,
                    state: .delivered,
                    senderID: nil,
                    isDeleted: false,
                    contents: ["Hey how's it going"]
                ),
            ])
        }
        .navigationTitle("Chat")
    }
    .modelContainer(container)
}
