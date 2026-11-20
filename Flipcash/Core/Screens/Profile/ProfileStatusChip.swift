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

    /// The amber label of a chip on ``ShapeStyle/warningSecondary``: `warning` in dark, a deeper
    /// amber in light, where `warning` is too pale to read as text on the chip.
    static let warningTint = Color(light: Color(r: 152, g: 87, b: 0), dark: Color(r: 255, g: 169, b: 57))
}
