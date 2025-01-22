//
//  RoomCard.swift
//  Code
//
//  Created by Dima Bart on 2025-01-10.
//

import SwiftUI
import FlipchatServices

struct RoomCard: View {
    
    let title: String
    let host: String?
    let memberCount: Int
    let cover: Kin
    let avatarData: Data
    
    var body: some View {
        AspectRatioCard {
            VStack {
                Spacer()
                Image(with: .brandLarge)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 50)
                Spacer()
                Text(title)
                    .font(.appDisplaySmall)
                    .multilineTextAlignment(.center)
                
                Spacer()
                VStack(spacing: 4) {
                    Text("Hosted by \(host ?? "Member")")
                    Text("\(memberCount) \(memberCount == 1 ? "person" : "people") here")
                    Text("Cover Charge: \(cover.formattedTruncatedKin())")
                }
                .opacity(0.8)
                .font(.appTextSmall)
                Spacer()
            }
            .padding(20)
            .shadow(color: Color.black.opacity(0.2), radius: 1, y: 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                DeterministicGradient(data: avatarData)
            }
        }
    }
}
