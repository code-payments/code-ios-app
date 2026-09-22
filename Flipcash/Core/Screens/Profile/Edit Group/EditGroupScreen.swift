//
//  EditGroupScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// What a group's editor can change, one row each (node 10187:110373).
///
/// The design draws four rows — Icon, Membership Card, Description and Social Links — but only the
/// first has contract support: `EditChatRequest` carries a title and a picture and nothing else, so
/// the other three would be rows that cannot save. Name is the counterpart the design omits, styled
/// to match. The design's "Icon" is called Picture here, matching both the contract's
/// `EditChatRequest.picture` and the row Android ships.
struct EditGroupScreen: View {

    let conversationID: ConversationID

    @Environment(ConversationController.self) private var conversationController
    @Environment(AppRouter.self) private var router

    private var conversation: Conversation? {
        conversationController.conversation(withID: conversationID)
    }

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 0) {
                Row(insets: rowInsets, accessory: .chevron) {
                    Image.system(.photo)
                        .frame(minWidth: 45)
                    Text("Picture")
                } action: {
                    router.push(.editGroupPicture(conversationID))
                }
                .accessibilityIdentifier("edit-group-picture")

                Row(insets: rowInsets, accessory: .chevron) {
                    Image.system(.textformat)
                        .frame(minWidth: 45)
                    Text("Name")
                } action: {
                    router.push(.editGroupName(conversationID))
                }
                .accessibilityIdentifier("edit-group-name")

                Spacer()
            }
            .font(.appDisplayXS)
            .padding(.horizontal, 20)
        }
        .navigationTitle("Edit Group")
        .toolbarTitleDisplayMode(.inline)
        // An edit permission the server withdraws while this screen is open leaves the user on a
        // list of things they can no longer save. Unwinding is the honest answer, and matches the
        // gate that put the menu item there in the first place.
        .onChange(of: conversation?.canEdit ?? false) { _, canEdit in
            if !canEdit { router.popTopmost() }
        }
    }

    /// The 25pt vertical rhythm every other list in the app uses, near enough to the design's ~24pt
    /// that matching the app is the better trade. Leading inset is zero because the row's own icon
    /// column starts the content; the 20pt screen padding holds it off the edge.
    private var rowInsets: EdgeInsets {
        .init(top: 25, leading: 0, bottom: 25, trailing: 0)
    }
}
