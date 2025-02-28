//
//  MemberGrid.swift
//  Code
//
//  Created by Dima Bart on 2025-01-28.
//

import SwiftUI
import CodeUI
import FlipchatServices

struct MemberGrid: View {
    
    let chatName: String
    let avatarData: Data
    let members: [Member]
    let shareRoomNumber: RoomNumber?
    let isClosed: Bool
    let canEdit: Bool
    let memberActionEnabled: Bool
    let memberAction: ((Member) -> Void)?
    let editAction: (() -> Void)?
    
    private let speakers: [Member]
    private let listeners: [Member]
    
    private let size: CGFloat = 70
    private let spacing: CGFloat = 15
    private let padding: CGFloat = 20
    
    @Namespace private var namespace: Namespace.ID
    
    init(chatName: String, avatarData: Data, members: [Member], shareRoomNumber: RoomNumber? = nil, isClosed: Bool = false, canEdit: Bool, memberActionEnabled: Bool, memberAction: ((Member) -> Void)?, editAction: (() -> Void)?) {
        self.chatName = chatName
        self.avatarData = avatarData
        self.members = members
        self.shareRoomNumber = shareRoomNumber
        self.isClosed = isClosed
        self.canEdit = canEdit
        self.memberActionEnabled = memberActionEnabled
        self.memberAction = memberAction
        self.editAction = editAction
        
        self.speakers  = members.filter {  $0.isSpeaker }.sortedByDisplayName()
        self.listeners = members.filter { !$0.isSpeaker }.sortedByDisplayName()
    }
    
    var body: some View {
        GeometryReader { g in
            ScrollBox(color: .backgroundMain) {
                ScrollView {
                    HStack(alignment: .center) {
                        Spacer()
                        
                        VStack(spacing: 20) {
                            Button {
                                editAction?()
                            } label: {
                                VStack(spacing: 20) {
                                    RoomGeneratedAvatar(
                                        data: avatarData,
                                        diameter: 100
                                    )
                                    .if(canEdit) { $0
                                        .overlay {
                                            GeometryReader { g in
                                                Image.asset(.pencil)
                                                    .frame(width: 20, height: 20)
                                                    .position(x: g.size.width - 10, y: 10)
                                            }
                                        }
                                    }
                                    
                                    VStack(spacing: 8) {
                                        Text(chatName)
                                            .multilineTextAlignment(.center)
                                            .lineLimit(2)
                                            .font(.appDisplaySmall)
                                        
                                        HStack {
                                            if isClosed {
                                                Text("This Flipchat is currently closed")
                                                    .font(.appTextCaption)
                                                    .foregroundStyle(Color.textSecondary.opacity(0.8))
                                                    .transition(.move(edge: .top).combined(with: .opacity))
                                            }
                                        }
                                        .frame(height: 15)
                                        .animation(.easeInOut(duration: 0.2), value: isClosed)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .disabled(!canEdit)
                            
                            if let shareRoomNumber {
                                CodeButton(
                                    style: .filled,
                                    title: "Share a Link to This Flipchat"
                                ) {
                                    ShareSheet.present(url: .flipchatRoom(roomNumber: shareRoomNumber, messageID: nil))
                                }
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 10)
                    
                    LazyVGrid(columns: columns(for: g.size.width), spacing: spacing) {
                        Section(header: title("\(speakers.count) Speakers")) {
                            ForEach(speakers) { member in
                                user(member: member, defaultName: "Speaker")
                            }
                        }
                        
                        Section(header: title("\(listeners.count) Listeners")) {
                            ForEach(listeners) { member in
                                user(member: member, defaultName: "Listener")
                            }
                        }
                    }
                    .animation(.easeInOut(duration: 0.3), value: speakers)
                    .animation(.easeInOut(duration: 0.3), value: listeners)
                    .padding(.horizontal, padding)
                }
            }
        }
        .foregroundColor(.textMain)

    }
    
    @ViewBuilder private func user(member: Member, defaultName: String) -> some View {
        VStack {
            UserGeneratedAvatar(
                url: member.avatarURL,
                data: member.id.data,
                diameter: size,
                isHost: member.isModerator
            )
            
            Text(member.name ?? defaultName)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.9)
                .lineLimit(2)
                .font(.appTextHeading)
                .frame(height: 30, alignment: .topLeading)
        }
        .frame(width: size)
        .aspectRatio(contentMode: .fit)
//        .transition(.move(edge: .top).combined(with: .opacity))
        .matchedGeometryEffect(id: member.id, in: namespace)
        .onLongPressGesture {
            memberAction?(member)
        }
        
//        let actionEnabled = memberActionEnabled && !member.isSelf
//        Button {
//            // No action
//        } label: {
//            
//        }
//        .disabled(!actionEnabled)
//        .buttonStyle(MemberGridButtonStyle())
//        .simultaneousGesture(LongPressGesture().onEnded { _ in
//            memberAction?(member)
//        }, isEnabled: actionEnabled)
//        .matchedGeometryEffect(id: member.id, in: namespace)

    }
    
    private func title(_ text: String) -> some View {
        Text(text)
            .font(.appTextLarge)
            .frame(height: 45)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
    }
    
    private func columns(for width: CGFloat) -> [GridItem] {
        
        let totalHorizontalSpacing = padding * 2
        let availableWidth = width - totalHorizontalSpacing
        let totalSpacingPerRow = spacing * CGFloat(Int(availableWidth / size) - 1)
        let maxColumns = Int((availableWidth - totalSpacingPerRow) / size)
        
        return Array(
            repeating: GridItem(.flexible()),
            count: max(maxColumns, 1)
        )
    }
}

//private struct MemberGridButtonStyle: ButtonStyle {
//    func makeBody(configuration: Configuration) -> some View {
//        configuration.label
//            .background(
//                RoundedRectangle(cornerRadius: 8)
//                    .fill(Color.white.opacity(configuration.isPressed ? 0.1 : 0.0))
//                    .padding(-8)
//            )
//    }
//}

extension MemberGrid {
    struct Member: Identifiable, Equatable {
        var id: UUID
        var isSelf: Bool
        var isSpeaker: Bool
        var isModerator: Bool
        var name: String?
        var avatarURL: URL?
    }
}

private extension Array where Element == MemberGrid.Member {
    func sortedByDisplayName() -> [Element] {
        return sorted { lhs, rhs in
            
            // Lowercase names for alphabetical comparison
            let lhsName = lhs.name?.lowercased() ?? ""
            let rhsName = rhs.name?.lowercased() ?? ""
            
            // 1. Sort by isModerator
            let lhsModerator = lhs.isModerator ? 0 : 1
            let rhsModerator = rhs.isModerator ? 0 : 1
            if lhsModerator != rhsModerator {
                return lhsModerator < rhsModerator
            }
            
            // 2. Sort by isSelf
            let lhsSelf = lhs.isSelf ? 0 : 1
            let rhsSelf = rhs.isSelf ? 0 : 1
            if lhsSelf != rhsSelf {
                return lhsSelf < rhsSelf
            }
            
            // 3. Sort by displayName
            if !lhsName.isEmpty && !rhsName.isEmpty {
                return lhsName.lexicographicallyPrecedes(rhsName)
                
            } else if !lhsName.isEmpty {
                return true
                
            } else if !rhsName.isEmpty {
                return false
                
            } else {
                return lhs.id.data < rhs.id.data
            }
        }
    }
}
