//
//  ListRow.swift
//  FlipcashUI
//

import SwiftUI

/// A tappable list row: a fixed leading slot, a title with an optional subtitle, and a trailing
/// accessory, with a divider that starts at the text and stops at the trailing margin.
public struct ListRow<Leading: View, Trailing: View>: View {

    private let title: String
    private let subtitle: String?
    private let tone: ListRowTone
    private let showsDivider: Bool
    private let leading: Leading
    private let trailing: Trailing
    private let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    /// Creates a row; pass `EmptyView()` content for a slot the row doesn't use.
    public init(
        _ title: String,
        subtitle: String? = nil,
        tone: ListRowTone = .standard,
        showsDivider: Bool = true,
        action: @escaping () -> Void,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.tone = tone
        self.showsDivider = showsDivider
        self.leading = leading()
        self.trailing = trailing()
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: ListRowMetrics.gap) {
                if Leading.self != EmptyView.self {
                    leading
                        .foregroundStyle(titleColor)
                        .environment(\.listRowTone, tone)
                        .frame(width: ListRowMetrics.leadingSlot, height: ListRowMetrics.leadingSlot)
                }
                HStack(spacing: ListRowMetrics.gap) {
                    VStack(alignment: .leading, spacing: ListRowMetrics.subtitleGap) {
                        Text(title)
                            .foregroundStyle(titleColor)
                            .lineLimit(1)
                            .font(.default(size: Tuner.shared.value("Rows/Title size", default: CGFloat(16), in: 13...24, unit: .points), weight: [Font.Weight.regular, .medium, .semibold, .bold][Tuner.shared.value("Rows/Title weight (1 regular–4 bold)", default: 2, in: 1...4) - 1])) // LOCAL-TUNER
                        if let subtitle {
                            Text(subtitle)
                                .font(.appTextSmall)
                                .foregroundStyle(Color.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    trailing
                }
                .padding(.vertical, ListRowMetrics.verticalPadding)
                .padding(.trailing, ListRowMetrics.margin)
                .frame(minHeight: ListRowMetrics.minHeight)
                .overlay(alignment: .bottom) {
                    if showsDivider {
                        Rectangle()
                            .fill(Color.rowSeparator)
                            .frame(height: Tuner.shared.value("Rows/Divider weight", default: CGFloat(1.0 / 3.0), in: 0...2, unit: .points)) // LOCAL-TUNER
                            .padding(.trailing, ListRowMetrics.dividerTrailingInset)
                    }
                }
            }
            .padding(.leading, ListRowMetrics.margin)
            .contentShape(Rectangle())
        }
        .buttonStyle(ListRowButtonStyle())
        .opacity(isEnabled ? 1 : 0.4)
    }

    private var titleColor: Color {
        switch tone {
        case .standard:    .textMain
        case .destructive: .textError
        }
    }
}

/// The colour treatment of a row's title and leading icon.
public enum ListRowTone {
    case standard
    case destructive
}

/// The row's metrics, shared by `ListRow` and `ListSectionTitle` so a group of rows stays aligned.
@MainActor public enum ListRowMetrics { // LOCAL-TUNER
    /// Screen-edge inset on both sides.
    public static var margin: CGFloat { Tuner.shared.value("Rows/Side margin", default: CGFloat(20), in: 0...32, unit: .points) } // LOCAL-TUNER
    /// The smallest a single-line row can be.
    public static var minHeight: CGFloat { Tuner.shared.value("Rows/Min height", default: CGFloat(60), in: 32...88, unit: .points) } // LOCAL-TUNER
    /// Space above and below the text.
    public static var verticalPadding: CGFloat { Tuner.shared.value("Rows/Vertical padding", default: CGFloat(20), in: 0...28, unit: .points) } // LOCAL-TUNER
    /// Width and height of the leading slot; the title starts after it.
    public static var leadingSlot: CGFloat { Tuner.shared.value("Rows/Leading slot", default: CGFloat(30), in: 20...60, unit: .points) } // LOCAL-TUNER
    /// Space between the leading slot, the text and the trailing accessory.
    public static var gap: CGFloat { Tuner.shared.value("Rows/Gap", default: CGFloat(12), in: 0...28, unit: .points) } // LOCAL-TUNER
    /// Space between the title and the subtitle.
    public static var subtitleGap: CGFloat { Tuner.shared.value("Rows/Subtitle gap", default: CGFloat(2), in: 0...12, unit: .points) } // LOCAL-TUNER
    /// How far before the trailing edge the divider stops.
    public static var dividerTrailingInset: CGFloat { Tuner.shared.value("Rows/Divider right inset", default: CGFloat(20), in: 0...40, unit: .points) } // LOCAL-TUNER
    /// The size of an icon in the leading slot.
    public static var iconSize: CGFloat { Tuner.shared.value("Rows/Icon size", default: CGFloat(20), in: 12...36, unit: .points) } // LOCAL-TUNER
    /// The opacity of an icon in the leading slot.
    public static var iconOpacity: Double { Tuner.shared.value("Rows/Icon opacity", default: 0.5, in: 0...1) } // LOCAL-TUNER
    /// The diameter of a flag in the leading slot.
    public static var flagSize: CGFloat { Tuner.shared.value("Rows/Flag size", default: CGFloat(28), in: 16...48, unit: .points) } // LOCAL-TUNER
    /// Space above a section title.
    public static var sectionTop: CGFloat { Tuner.shared.value("Rows/Section top", default: CGFloat(24), in: 0...48, unit: .points) } // LOCAL-TUNER
    /// Space between a section title and its first row.
    public static var sectionBottom: CGFloat { Tuner.shared.value("Rows/Section bottom", default: CGFloat(0), in: 0...24, unit: .points) } // LOCAL-TUNER
    /// The opacity of a section title.
    public static var sectionOpacity: Double { Tuner.shared.value("Rows/Section title opacity", default: 0.5, in: 0...1) } // LOCAL-TUNER
}

/// A leading-slot icon at the row's icon size and opacity.
public struct ListRowIcon: View {
    private let image: Image

    @Environment(\.listRowTone) private var tone

    /// Creates the icon from an image; it's drawn as a template in the row's title colour.
    public init(_ image: Image) {
        self.image = image
    }

    public var body: some View {
        image
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: ListRowMetrics.iconSize, height: ListRowMetrics.iconSize)
            // A destructive row's icon stays at full strength so the red reads as a warning.
            .opacity(tone == .destructive ? 1 : ListRowMetrics.iconOpacity)
    }
}

extension EnvironmentValues {
    /// The tone of the row an accessory sits in.
    @Entry var listRowTone: ListRowTone = .standard
}

/// The trailing chevron of a row that pushes somewhere.
public struct ListRowChevron: View {
    /// Creates the chevron.
    public init() {}

    public var body: some View {
        Image.icon(.chevronRightMedium)
            .iconSize(16)
            .foregroundStyle(Color.textSecondary.opacity(0.6))
    }
}

/// The title above a group of rows.
public struct ListSectionTitle: View {
    private let title: String

    /// Creates a section title.
    public init(_ title: String) {
        self.title = title
    }

    public var body: some View {
        Text(title)
            .font(.appTextSmall)
            .foregroundStyle(Color.textMain.opacity(ListRowMetrics.sectionOpacity))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ListRowMetrics.margin)
            .padding(.top, ListRowMetrics.sectionTop)
            .padding(.bottom, ListRowMetrics.sectionBottom)
    }
}

/// Dims a row while it's pressed.
private struct ListRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

#Preview {
    Background(color: .backgroundMain) {
        VStack(spacing: 0) {
            ListSectionTitle("Security")
            ListRow("Access Key", action: {}) {
                ListRowIcon(Image.icon(.key1))
            } trailing: {
                ListRowChevron()
            }
            ListRow("Blocked", action: {}) {
                ListRowIcon(Image.icon(.circleBanSign))
            } trailing: {
                Text("2").foregroundStyle(Color.textSecondary)
            }
            ListRow("Delete Account", tone: .destructive, showsDivider: false, action: {}) {
                ListRowIcon(Image.icon(.trashCan))
            } trailing: {
                EmptyView()
            }
            Spacer()
        }
        .font(.appTextMedium)
    }
}
