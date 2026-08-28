//
//  DialogItem+ProfileChange.swift
//  Flipcash
//

import FlipcashUI

extension DialogItem {

    /// The profile fields My Account can replace. Each screen that edits one
    /// also serves as its first-time setup step, so the field is only named
    /// here for the replacement case.
    enum ProfileField {

        case username
        case displayName
        case profilePicture
        case minimumTip

        /// The label My Account uses for the field, so the dialog names it the
        /// same way the row the user tapped did.
        var title: String {
            switch self {
            case .username:       "Username"
            case .displayName:    "Display Name"
            case .profilePicture: "Profile Picture"
            case .minimumTip:     "Minimum Tip"
            }
        }

        var subtitle: String {
            switch self {
            case .username:
                // A released handle is claimable by anyone, so this change is
                // the only one of the four the user may not be able to undo.
                "Are you sure you want to permanently change your username? You might not be able to get your old username back"
            case .displayName:
                "Are you sure you want to permanently change your display name?"
            case .profilePicture:
                "Are you sure you want to permanently change your profile picture?"
            case .minimumTip:
                "Are you sure you want to permanently change your minimum tip?"
            }
        }
    }

    /// Confirms replacing a profile field that is already set. Raised on Save,
    /// after validation, so the user is never asked to confirm an entry the
    /// screen is about to reject anyway.
    ///
    /// Untracked: the user choosing to change their own display name is not an
    /// error worth an analytics event.
    static func confirmProfileChange(
        _ field: ProfileField,
        onConfirm: @escaping () -> Void
    ) -> DialogItem {
        .alert(title: "Change \(field.title)?", subtitle: field.subtitle) {
            DialogAction.destructive("Change \(field.title)", action: onConfirm)
            DialogAction.cancel()
        }
    }
}
