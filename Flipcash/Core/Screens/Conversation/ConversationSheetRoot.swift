//
//  ConversationSheetRoot.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

/// Root view for the `.conversation` sheet — a chat entered as the bottom view
/// via deeplink / push notification. The `NavigationStack` is unbound: nothing
/// pushes onto this stack, so it exists only to render the toolbar. The trailing
/// close button is the root-sheet counterpart to the back button the pushed
/// `.dmConversation` entry gets (push → back, root sheet → close).
struct ConversationSheetRoot: View {

    let context: ConversationContext

    @Environment(AppRouter.self) private var router

    var body: some View {
        NavigationStack {
            ConversationScreen(context: context)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        CloseButton(action: router.dismissSheet)
                    }
                }
        }
    }
}
