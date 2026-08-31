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
                "This will change your display name"
            case .profilePicture:
                "This will change your profile photo"
            case .minimumTip:
                "This will change your minimum tip"
            }
        }

        /// Whether the change can cost the user something they can't take back.
        /// Only the username can, so only it gets the red banner and the
        /// destructive button; the rest confirm in the grey informational one.
        var isIrreversible: Bool {
            switch self {
            case .username:
                true
            case .displayName, .profilePicture, .minimumTip:
                false
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
        let title = "Change \(field.title)?"
        let confirm = "Change \(field.title)"

        if field.isIrreversible {
            return .alert(title: title, subtitle: field.subtitle) {
                DialogAction.destructive(confirm, action: onConfirm)
                DialogAction.cancel()
            }
        } else {
            return .info(title: title, subtitle: field.subtitle) {
                DialogAction.standard(confirm, action: onConfirm)
                DialogAction.cancel()
            }
        }
    }
}
