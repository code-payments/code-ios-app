//
//  TipUser.swift
//  Code
//
//  Created by Dima Bart on 2025-03-13.
//

import Foundation
import FlipchatServices

struct TipUser {
    let userID: UUID
    let displayName: String?
    let tip: Kin
    let profile: SocialProfile?
    
    var resolvedDisplayName: String {
        (profile?.displayName ?? displayName) ?? defaultMemberName
    }
}
