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
    
    static let rowHeight: CGFloat = 55
    
    // MARK: - Init -
    
    public init(userTips: [UserTip]) {
        self.userTips = userTips
    }
    
    // MARK: - Body -
    
    public var body: some View {
        Background(color: .backgroundMain) {
            List {
                ForEach(userTips, id: \.userID) { tip in
                    HStack(spacing: 12) {
                        GradientAvatarView(
                            data: tip.userID.data,
                            diameter: 30
                        )
                        
                        Text(tip.name)
                            .font(.appTextMedium)
                        
                        Spacer()
                        
                        Text(tip.amount.formattedTruncatedKin(showSuffix: false))
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
            .padding(.top, 10)
        }
        .presentationDetents(detents())
    }
    
    private func detents() -> Set<PresentationDetent> {
        let tipsToShow = min(userTips.count, 5)
        let openingHeight = CGFloat(tipsToShow) * Self.rowHeight - 10
        
        var detents: Set<PresentationDetent> = []
        detents.insert(.height(openingHeight))
        
        // If the number of tips exceeds the
        // initial opening count, allow the
        // user to expand the sheet
        if userTips.count > tipsToShow {
            detents.insert(.large)
        }
        
        return detents
    }
}

extension ModalTipList {
    public struct UserTip {
        var userID: UUID
        var name: String
        var amount: Kin
    }
}

#Preview {
    Background(color: .backgroundMain) {}
    .sheet(isPresented: .constant(true)) {
        ModalTipList(userTips: [
            .init(userID: UUID(), name: "John",  amount: 5),
            .init(userID: UUID(), name: "Lisa",  amount: 20),
            .init(userID: UUID(), name: "Tim",   amount: 3),
            .init(userID: UUID(), name: "Jake",  amount: 1),
            .init(userID: UUID(), name: "Cindy", amount: 10),
            .init(userID: UUID(), name: "Kelly", amount: 15),
//            .init(userID: UUID(), name: "Billy", amount: 35),
        ])
    }
}
