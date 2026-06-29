//
//  ConversationSheetRoot.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

/// Root view for the `.conversation` sheet — a chat entered as the bottom view
/// via deeplink / push notification. The `NavigationStack` is bound to the
/// `.conversation` stack so in-chat pushes (e.g. tapping a cash card to open its
/// currency info) land here, and `.appRouterDestinations` registers the map those
/// pushes resolve through. The trailing close button is the root-sheet counterpart
/// to the back button the pushed `.dmConversation` entry gets (push → back, root
/// sheet → close).
struct ConversationSheetRoot: View {

    let context: ConversationContext

    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router[.conversation]) {
            ConversationScreen(context: context)
                .appRouterDestinations()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        CloseButton(action: router.dismissSheet)
                    }
                }
        }
    }
}
