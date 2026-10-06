//
//  ProfileStatusChip.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

/// A tinted capsule stating one setting of the viewer's over a profile, such as muted or blocked.
struct ProfileStatusChip: View {

    let systemImage: String
    let text: String
    let tint: Color
    let fill: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
            Text(text)
        }
        .chip(.tinted(tint, on: fill))
    }
}
