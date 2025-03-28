//
//  ModalTipList.swift
//  Code
//
//  Created by Dima Bart on 2025-01-21.
//

import SwiftUI
import CodeUI
import FlipchatServices

struct ModalTipList: View {
    
    let userReactions: [UserReaction]
    
    private let tipsToShow: Int
    
    private var allowExpand: Bool {
        userReactions.count > tipsToShow
    }
    
    private static let rowHeight: CGFloat = 55
    
    // MARK: - Init -
    
    init(userReactions: [UserReaction]) {
        self.userReactions = userReactions
        self.tipsToShow = min(userReactions.count, 5)
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            VStack {
                NavBar(alignment: .bottom, title: "Reactions")
                List {
                    ForEach(userReactions) { userTip in
                        HStack(spacing: 12) {
                            UserGeneratedAvatar(
                                url: userTip.avatarURL,
                                data: userTip.userID.data,
                                diameter: 30,
                                isHost: userTip.isHost
                            )
                            
                            MemberNameLabel(
                                size: .medium,
                                showLogo: false,
                                name: userTip.name,
                                verificationType: userTip.verificationType
                            )
                            
                            Spacer()
                            
                            switch userTip.kind {
                            case .tip(let amount):
                                Text(amount.formattedTruncatedKin(showSuffix: false))
                                    .font(.appTextLarge)
                                
                            case .reactions(let emojis):
                                Text(emojis.joined(separator: " "))
                                    .lineLimit(1)
                                    .font(.appTextMedium)
                            }
                            
                        }
                        .foregroundStyle(Color.textMain)
                        .frame(height: Self.rowHeight)
                    }
                    .listRowSeparatorTint(.rowSeparator)
                    .listRowBackground(Color.backgroundMain)
                    .listRowInsets(.init(top: 0, leading: 20, bottom: 0, trailing: 20))
                    .scrollContentBackground(.hidden)
                }
                .listStyle(.plain)
            }
        }
        .presentationDetents(detents())
    }
    
    private func detents() -> Set<PresentationDetent> {
        let openingHeight = CGFloat(tipsToShow) * Self.rowHeight + 10 + 44 // 44pt nav bar
        
        var detents: Set<PresentationDetent> = []
        detents.insert(.height(openingHeight))
        
        // If the number of tips exceeds the
        // initial opening count, allow the
        // user to expand the sheet
        if allowExpand {
            detents.insert(.large)
        }
        
        return detents
    }
}

extension ModalTipList {
    struct UserReaction: Identifiable {
        var kind: Kind
        var userID: UUID
        var avatarURL: URL?
        var name: String
        var verificationType: VerificationType
        var isHost: Bool
        
        var id: String {
            switch kind {
            case .tip:
                "t:\(userID)"
            case .reactions:
                "r:\(userID)"
            }
        }
        
        enum Kind {
            case tip(Kin)
            case reactions([String])
        }
    }
}

#Preview {
    Background(color: .backgroundMain) {}
    .sheet(isPresented: .constant(true)) {
        ModalTipList(userReactions: [
            .init(
                kind: .tip(10),
                userID: UUID(),
                avatarURL: nil,
                name: "John",
                verificationType: .none,
                isHost: false
            ),
        ])
    }
}
