//
//  ListRow.swift
//  FlipcashUI
//

import SwiftUI

/// A tappable list row: a fixed leading slot, a title with an optional subtitle, and a trailing
/// accessory, with a divider that starts at the text and stops at the trailing margin.
public struct ListRow<Leading: View, Trailing: View>: View {

    private let title: Text
    private let subtitle: Text?
    private let tone: ListRowTone
    private let showsDivider: Bool
    private let leading: Leading
    private let trailing: Trailing
    private let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.displayScale) private var displayScale

    /// Creates a row with localized copy; pass `EmptyView()` content for a slot the row doesn't use.
    public init(
        _ title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        tone: ListRowTone = .standard,
        showsDivider: Bool = true,
        action: @escaping () -> Void,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = Text(title)
        self.subtitle = subtitle.map { Text($0) }
        self.tone = tone
        self.showsDivider = showsDivider
        self.leading = leading()
        self.trailing = trailing()
        self.action = action
    }

    /// Creates a row that shows `title` and `subtitle` verbatim, for copy that's already localized
    /// or is data, like a region's name.
    @_disfavoredOverload
    public init<S: StringProtocol>(
        _ title: S,
        subtitle: S? = nil,
        tone: ListRowTone = .standard,
        showsDivider: Bool = true,
        action: @escaping () -> Void,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = Text(title)
        self.subtitle = subtitle.map { Text($0) }
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
                        title
                            .foregroundStyle(titleColor)
                            .font(.default(size: 16, weight: .medium))
                        if let subtitle {
                            subtitle
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
                            .frame(height: 1 / displayScale)
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
public enum ListRowMetrics {
    /// Screen-edge inset on both sides.
    public static let margin: CGFloat = 20
    /// The smallest a single-line row can be.
    public static let minHeight: CGFloat = 60
    /// Space above and below the text.
    public static let verticalPadding: CGFloat = 20
    /// Width and height of the leading slot; the title starts after it.
    public static let leadingSlot: CGFloat = 30
    /// Space between the leading slot, the text and the trailing accessory.
    public static let gap: CGFloat = 12
    /// Space between the title and the subtitle.
    public static let subtitleGap: CGFloat = 2
    /// How far before the trailing edge the divider stops.
    public static let dividerTrailingInset: CGFloat = 20
    /// The size of an icon in the leading slot.
    public static let iconSize: CGFloat = 20
    /// The opacity of an icon in the leading slot.
    public static let iconOpacity: Double = 0.5
    /// The diameter of a flag in the leading slot.
    public static let flagSize: CGFloat = 28
    /// Space above a section title.
    public static let sectionTop: CGFloat = 24
    /// Space between a section title and its first row.
    public static let sectionBottom: CGFloat = 0
    /// The opacity of a section title.
    public static let sectionOpacity: Double = 0.5
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
    private let title: LocalizedStringKey

    /// Creates a section title from localized copy.
    public init(_ title: LocalizedStringKey) {
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
            .accessibilityAddTraits(.isHeader)
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
