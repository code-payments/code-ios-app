//
//  DialogItem+GroupChange.swift
//  Flipcash
//

import FlipcashUI

extension DialogItem {

    /// The group fields the Edit Group list can replace.
    ///
    /// The sibling of ``DialogItem/ProfileField``, and confirmed for a different reason: a profile
    /// field is the user's own, while both of these are visible to everyone in the group the moment
    /// they save. Neither can be reached before the group exists, so unlike the profile fields
    /// there is no first-time-setup case to exempt — every edit here is a replacement.
    enum GroupField {

        case name
        case picture

        /// Group-qualified rather than borrowing the row's bare "Name" / "Picture", which would
        /// read as the user's own once the dialog covers the screen that gave them context.
        var title: String {
            switch self {
            case .name:    "Group Name"
            case .picture: "Group Picture"
            }
        }

        var subtitle: String {
            switch self {
            case .name:    "This will change the group name for everyone in it"
            case .picture: "This will change the group picture for everyone in it"
            }
        }
    }

    /// Confirms replacing a group field. Raised on Save, after validation, so the user is never
    /// asked to confirm a name the screen is about to reject anyway.
    ///
    /// Alerts rather than informs, which is where this parts company with the profile
    /// confirmations: those weigh whether the user can get their own old value back, and only the
    /// username can't. Here the edit lands on everyone in the group at once, and no later undo
    /// takes back what they have already seen.
    ///
    /// Untracked, for the same reason the profile confirmations are: a user changing a group they
    /// are permitted to edit is not an error worth an analytics event.
    static func confirmGroupChange(
        _ field: GroupField,
        onConfirm: @escaping () -> Void
    ) -> DialogItem {
        .alert(title: "Change \(field.title)?", subtitle: field.subtitle) {
            DialogAction.destructive("Change \(field.title)", action: onConfirm)
            DialogAction.cancel()
        }
    }
}
