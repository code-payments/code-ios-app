//
//  MessageMenuView.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit

/// The action list under a long-pressed bubble, drawn like a system context menu on a Liquid Glass
/// platter. Rows come from the message's `UIAction`s, so the menu and its tests share one mapping.
/// A row can be tapped, or reached by dragging the pressing finger onto it and lifting. A divider
/// sets the destructive rows apart from the ones above them.
final class MessageMenuView: UIView {

    /// Fired with the chosen action, before it is performed.
    var onSelect: ((UIAction) -> Void)?

    static let width: CGFloat = 250
    private static let rowHeight: CGFloat = 44
    private static let verticalInset: CGFloat = 8
    private static let horizontalInset: CGFloat = 16
    private static let iconWidth: CGFloat = 24
    private static let cornerRadius: CGFloat = 24
    private static let dividerHeight: CGFloat = 13

    private let actions: [UIAction]
    private let surface: UIView
    private var rows: [UIControl] = []
    private let selection = UISelectionFeedbackGenerator()

    /// The menu's size for `actions`.
    static func size(for actions: [UIAction]) -> CGSize {
        let dividers: CGFloat = dividerIndex(in: actions) == nil ? 0 : 1
        return CGSize(
            width: width,
            height: CGFloat(actions.count) * rowHeight + dividers * dividerHeight + verticalInset * 2
        )
    }

    /// The index of the first destructive action when a non-destructive one comes before it, which
    /// is where the divider goes.
    private static func dividerIndex(in actions: [UIAction]) -> Int? {
        guard let index = actions.firstIndex(where: { $0.attributes.contains(.destructive) }), index > 0 else {
            return nil
        }
        return index
    }

    init(actions: [UIAction]) {
        self.actions = actions
        if #available(iOS 26, *) {
            let glass = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
            glass.cornerConfiguration = .uniformCorners(radius: .fixed(Self.cornerRadius))
            surface = glass
        } else {
            surface = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))
            surface.layer.cornerRadius = Self.cornerRadius
            surface.layer.cornerCurve = .continuous
            surface.clipsToBounds = true
        }
        super.init(frame: CGRect(origin: .zero, size: Self.size(for: actions)))

        surface.frame = bounds
        surface.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(surface)
        let content = (surface as? UIVisualEffectView)?.contentView ?? surface

        let dividerIndex = Self.dividerIndex(in: actions)
        var y = Self.verticalInset
        for (index, action) in actions.enumerated() {
            if index == dividerIndex {
                let hairline: CGFloat = 0.5
                let divider = UIView(frame: CGRect(
                    x: Self.horizontalInset,
                    y: y + (Self.dividerHeight - hairline) / 2,
                    width: bounds.width - Self.horizontalInset * 2,
                    height: hairline
                ))
                divider.backgroundColor = .separator
                divider.autoresizingMask = [.flexibleWidth]
                content.addSubview(divider)
                y += Self.dividerHeight
            }
            let row = Self.row(for: action)
            row.frame = CGRect(x: 0, y: y, width: bounds.width, height: Self.rowHeight)
            y += Self.rowHeight
            row.autoresizingMask = [.flexibleWidth]
            row.tag = index
            row.addTarget(self, action: #selector(rowTapped), for: .touchUpInside)
            content.addSubview(row)
            rows.append(row)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private static func row(for action: UIAction) -> UIControl {
        let destructive = action.attributes.contains(.destructive)
        let tint: UIColor = destructive ? .systemRed : .label
        let row = MenuRow()
        row.accessibilityLabel = action.title
        row.accessibilityTraits = .button
        row.isAccessibilityElement = true

        let icon = UIImageView(image: action.image?.withRenderingMode(.alwaysTemplate))
        icon.tintColor = tint
        icon.contentMode = .center
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(font: .preferredFont(forTextStyle: .body))
        let title = UILabel()
        title.text = action.title
        title.textColor = tint
        title.font = .preferredFont(forTextStyle: .body)
        title.adjustsFontForContentSizeCategory = true

        for view in [icon, title] {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.isUserInteractionEnabled = false
            row.addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: horizontalInset),
            icon.widthAnchor.constraint(equalToConstant: iconWidth),
            icon.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            title.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor, constant: -horizontalInset),
            title.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])
        return row
    }

    @objc private func rowTapped(_ row: UIControl) {
        select(at: row.tag)
    }

    /// Highlights the row under `point` (in this view's space) as a pressing finger drags over it.
    func track(_ point: CGPoint) {
        let index = rowIndex(at: point)
        for row in rows where row.isHighlighted != (row.tag == index) {
            row.isHighlighted = row.tag == index
            if row.isHighlighted { selection.selectionChanged() }
        }
    }

    /// Chooses the row under `point` (in this view's space) as a dragging finger lifts; returns
    /// whether there was one.
    @discardableResult
    func release(at point: CGPoint) -> Bool {
        rows.forEach { $0.isHighlighted = false }
        guard let index = rowIndex(at: point) else { return false }
        select(at: index)
        return true
    }

    private func rowIndex(at point: CGPoint) -> Int? {
        rows.first { $0.frame.contains(convert(point, to: $0.superview)) }?.tag
    }

    private func select(at index: Int) {
        guard actions.indices.contains(index) else { return }
        onSelect?(actions[index])
    }
}

/// A menu row, which shades itself while highlighted.
private final class MenuRow: UIControl {
    override var isHighlighted: Bool {
        didSet { backgroundColor = isHighlighted ? UIColor.label.withAlphaComponent(0.12) : .clear }
    }
}
#endif
