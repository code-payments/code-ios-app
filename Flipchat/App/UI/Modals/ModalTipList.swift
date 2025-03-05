//
//  ModalTipList.swift
//  Code
//
//  Created by Dima Bart on 2025-01-21.
//

import SwiftUI
import CodeUI
import FlipchatServices

public struct ModalTipList: View {
    
    let userTips: [UserTip]
    
    private let tipsToShow: Int
    
    private var allowExpand: Bool {
        userTips.count > tipsToShow
    }
    
    private static let rowHeight: CGFloat = 55
    
    // MARK: - Init -
    
    public init(userTips: [UserTip]) {
        self.userTips = userTips
        self.tipsToShow = min(userTips.count, 5)
    }
    
    // MARK: - Body -
    
    public var body: some View {
        Background(color: .backgroundMain) {
            List {
                ForEach(userTips, id: \.userID) { userTip in
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
                        
                        Text(userTip.amount.formattedTruncatedKin(showSuffix: false))
                            .font(.appTextLarge)
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
        .presentationDetents(detents())
    }
    
    private func detents() -> Set<PresentationDetent> {
        let openingHeight = CGFloat(tipsToShow) * Self.rowHeight + 10
        
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
    public struct UserTip {
        var userID: UUID
        var avatarURL: URL?
        var name: String
        var verificationType: VerificationType
        var isHost: Bool
        var amount: Kin
    }
}

#Preview {
    Background(color: .backgroundMain) {}
    .sheet(isPresented: .constant(true)) {
        ModalTipList(userTips: [
            .init(
                userID: UUID(),
                avatarURL: nil,
                name: "John",
                verificationType: .none,
                isHost: false,
                amount: 5
            ),
        ])
    }
}
