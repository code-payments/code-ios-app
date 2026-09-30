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
/// A row can be tapped, or reached by dragging the pressing finger onto it and lifting.
final class MessageMenuView: UIView {

    /// Fired with the chosen action, before it is performed.
    var onSelect: ((UIAction) -> Void)?

    static let width: CGFloat = 250
    private static let rowHeight: CGFloat = 44
    private static let verticalInset: CGFloat = 8
    private static let horizontalInset: CGFloat = 16
    private static let iconWidth: CGFloat = 24
    private static let cornerRadius: CGFloat = 24

    private let actions: [UIAction]
    private let surface: UIView
    private var rows: [UIControl] = []
    private let selection = UISelectionFeedbackGenerator()

    /// The menu's size for `count` rows.
    static func size(rows count: Int) -> CGSize {
        CGSize(width: width, height: CGFloat(count) * rowHeight + verticalInset * 2)
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
        super.init(frame: CGRect(origin: .zero, size: Self.size(rows: actions.count)))

        surface.frame = bounds
        surface.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(surface)
        let content = (surface as? UIVisualEffectView)?.contentView ?? surface

        for (index, action) in actions.enumerated() {
            let row = Self.row(for: action)
            row.frame = CGRect(x: 0, y: Self.verticalInset + CGFloat(index) * Self.rowHeight, width: bounds.width, height: Self.rowHeight)
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
