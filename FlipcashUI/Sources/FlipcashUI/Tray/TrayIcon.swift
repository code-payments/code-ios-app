//
//  TrayIcon.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI

/// The mark at a tray's top left: a Central icon tinted like the rest of the tray, or an image.
public enum TrayIcon {
    /// A Central icon, drawn bare at the icon size in the tray's tint.
    case central(Icon)
    /// An image drawn as it is, such as a brand mark; template images and SF Symbols take the
    /// tray's tint.
    case image(Image)
}

extension TrayIcon {
    /// What makes two icons the same for a step change: the Central name, or nil for an image,
    /// which can't be compared.
    var identity: AnyHashable? {
        switch self {
        case .central(let icon): icon.rawValue
        case .image: nil
        }
    }
}

extension TrayIcon {
    /// The mark a destructive or error tray shows: the exclamation circle.
    public static var destructive: TrayIcon { .central(.exclamationCircle) }
}

extension Image {
    /// A Central icon in the 1.5 pt set: the large mark at a tray's top left, where the 2 pt set
    /// reads heavy.
    static func trayIcon(_ icon: Icon) -> Image {
        Image(icon.rawValue.replacingOccurrences(of: "central/", with: "central-light/"), bundle: Bundle.module)
    }
}

/// A tray's icon at the tray's icon size.
struct TrayIconView: View {

    let icon: TrayIcon
    let color: Color

    var body: some View {
        let size = TrayMetrics.iconSize
        Group {
            switch icon {
            case .central(let icon):
                Image.trayIcon(icon)
                    .iconSize(size)
            case .image(let image):
                image
                    .iconSize(size)
            }
        }
        .foregroundStyle(color)
        .accessibilityHidden(true)
    }
}
