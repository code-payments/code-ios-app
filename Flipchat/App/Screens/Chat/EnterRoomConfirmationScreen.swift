//
//  EnterRoomConfirmationScreen.swift
//  Code
//
//  Created by Dima Bart on 2024-04-05.
//

import SwiftUI
import SwiftData
import CodeUI
import FlipchatServices

struct EnterRoomConfirmationScreen: View {
    
    @EnvironmentObject private var banners: Banners
    
    @ObservedObject private var viewModel: ChatViewModel
    
    @State private var showingPaymentConfirmation: Bool = false
    
    @Query private var chats: [pChat]
    
    private var chat: pChat {
        chats[0]
    }
    
    private let chatID: ChatID
    
    // MARK: - Init -
    
    init(chatID: ChatID, viewModel: ChatViewModel) {
        self.chatID = chatID
        self.viewModel = viewModel
        _chats = Query(filter: #Predicate { $0.serverID == chatID.data })
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    AspectRatioCard {
                        VStack {
                            Spacer()
                            Image(with: .brandLarge)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 50)
                            Spacer()
                            Text("Room \(chat.roomNumber.roomString)")
                                .font(.appDisplaySmall)
                            
                            Spacer()
                            VStack(spacing: 4) {
                                Text("Hosted by anonymous")
                                Text("\(chat.members.count) people inside")
                                Text("ID: \(chat.serverID.hexString().prefix(16))")
                                //                                    Text("Cover Charge: ⬢ 1,000 Kin")
                            }
                            .opacity(0.8)
                            .font(.appTextSmall)
                            Spacer()
                        }
                        .shadow(color: Color.black.opacity(0.2), radius: 1, y: 2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background {
                            DeterministicGradient(data: chat.serverID)
                        }
                    }
                    .padding(20)
                    
                    Spacer()
                    
                    CodeButton(
                        state: viewModel.beginChatState,
                        style: .filled,
                        title: "Join Room \(chat.roomNumber.roomString)"
                    ) {
                        showingPaymentConfirmation = true
                    }
                }
                .padding(20)
            }
            .foregroundColor(.textMain)
            .navigationBarTitle(Text("Enter Room Number"), displayMode: .inline)
            .sheet(isPresented: $showingPaymentConfirmation) {
                PartialSheet {
                    ModalPaymentConfirmation(
                        amount: KinAmount(kin: 200, rate: .oneToOne).kin.formattedFiat(rate: .oneToOne, suffix: nil),
                        currency: .kin,
                        primaryAction: "Swipe to Pay",
                        secondaryAction: "Cancel",
                        paymentAction: {
                            viewModel.attemptEnterGroupChat(
                                chatID: ChatID(data: chat.serverID),
                                hostID: UserID(data: chat.ownerUserID)
                            )
                        },
                        dismissAction: { showingPaymentConfirmation = false },
                        cancelAction: { showingPaymentConfirmation = false }
                    )
                }
            }
        }
    }
    
//    @ViewBuilder private func card() -> some View {
//        LinearGradient(
//            stops: [
//                Gradient.Stop(color: Color(red: 0.45, green: 0.02, blue: 0.72), location: 0.14), // Purple
//                Gradient.Stop(color: Color(red: 0.24, green: 0.2,  blue: 0.77), location: 0.37), // Blue
//                Gradient.Stop(color: Color(red: 1,    green: 0.73, blue: 0),    location: 0.55), // Yellow
//            ],
//            startPoint: UnitPoint(x: 0.5, y:  1.5),
//            endPoint:   UnitPoint(x: 0.5, y: -1.2)
//        )
//        .overlay {
//            EllipticalGradient(
//                stops: [
//                    Gradient.Stop(color: .white.opacity(0.2),  location: 0.00),
//                    Gradient.Stop(color: .white.opacity(0.00), location: 1.5),
//                ],
//                center: UnitPoint(x: 0.22, y: -0.1)
//            )
//            .blendMode(.overlay)
//        }
//        .drawingGroup()
//    }
    
    private func onAppear() {
        
    }
}

private struct AspectRatioCard<Content>: View where Content: View {
    
    private let padding: CGFloat = 20
    private let ratio: CGFloat = 1.647
    
    public let content: () -> Content
    
    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }
    
    var body: some View {
        GeometryReader { geometry in
            let size = size(for: geometry)
            
            content()
                .frame(width: size.width, height: size.height)
                .cornerRadius(8)
                .shadow(color: Color.black.opacity(0.25), radius: 40)
                .position(position(for: geometry, size: size))
        }
    }

    private func size(for geometry: GeometryProxy) -> CGSize {
        var h = geometry.size.height - padding * 2
        var w = h / ratio
        
        if w + padding * 2 > geometry.size.width {
            w = geometry.size.width - padding * 2
            h = w * ratio
        }
        
        return .init(
            width: max(w, 0),
            height: max(h, 0)
        )
    }
    
    private func position(for geometry: GeometryProxy, size: CGSize) -> CGPoint {
        let y = (geometry.size.height - size.height) * 0.5 + size.height * 0.5
        let x = (geometry.size.width  - size.width)  * 0.5 + size.width  * 0.5
        
        return .init(x: x, y: y)
    }
}

#Preview {
    EnterRoomConfirmationScreen(chatID: .mock, viewModel: .mock)
}
