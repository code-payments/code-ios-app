//
//  ReactionPillRowView.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import SwiftUI
import FlipcashCore

/// The reaction pills under a bubble: one `ReactionPillView` per emoji, wrapping onto at most two
/// lines, with a trailing "+" that opens the picker. Pills that don't fit collapse into an "N more"
/// pill at the end of the second line, which expands the row to show them all. Collapses to zero height
/// when there are no reactions, so a plain message's layout is unaffected; otherwise it leads with
/// its own gap to the bubble, which the column leaves out (see `installColumn`).
final class ReactionPillRowView: UIView {

    /// Fired with the tapped emoji. Only reachable through a pill whose `canReact` allowed the tap —
    /// see `ReactionPillView.configure`.
    var onToggle: ((String) -> Void)?
    /// Fired with the long-pressed emoji, to open the reactors sheet scoped to it.
    var onLongPress: ((String) -> Void)?
    /// Fired when the trailing "+" is tapped, to open the picker. The button is never shown when the
    /// viewer cannot react (see `configure(pills:canReact:)`).
    var onAdd: (() -> Void)?

    /// The width the cell gives this row, known before the row has been laid out. A freshly configured
    /// cell is measured before its first layout pass, so the line count has to come from this.
    var layoutWidth: CGFloat = 0 {
        didSet { if layoutWidth != oldValue { invalidateIntrinsicContentSize() } }
    }

    /// Whether each line sits against the trailing edge, as under the viewer's own bubbles.
    var hugsTrailingEdge = false {
        didSet { if hugsTrailingEdge != oldValue { setNeedsLayout() } }
    }

    private var pillViews: [ReactionPillView] = []
    private let addButton = ReactionAddButton()
    private let overflowButton = ReactionOverflowButton()

    /// Whether the viewer has opened the "N more" pill, lifting the two-line cap until the cell is reused.
    private var isExpanded = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        addButton.addTarget(self, action: #selector(addTapped), for: .touchUpInside)
        overflowButton.addTarget(self, action: #selector(overflowTapped), for: .touchUpInside)
        addButton.isHidden = true
        overflowButton.isHidden = true
        addSubview(addButton)
        addSubview(overflowButton)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Whether this row currently has anything to draw — false collapses it to zero height.
    private(set) var isEmpty = true

    /// - Parameters:
    ///   - pills: the message's reactions, already in display order.
    ///   - canReact: false withholds the trailing "+" and disables tap-to-toggle on existing pills,
    ///     but every pill still draws and long-press still opens the reactors sheet — a group
    ///     previewer's read of a message's reactions is otherwise unchanged.
    func configure(pills: [ReactionPill], canReact: Bool) {
        // Kept by emoji, so a count change or a reorder moves the pill that is already there and only
        // an emoji new to the row springs in.
        var reusable = Dictionary(pillViews.map { ($0.emoji, $0) }, uniquingKeysWith: { first, _ in first })
        pillViews = pills.map { pill in
            let view = reusable.removeValue(forKey: pill.emoji) ?? {
                let view = ReactionPillView()
                addSubview(view)
                if animatesChanges { entering.insert(ObjectIdentifier(view)) }
                return view
            }()
            view.configure(with: pill, canReact: canReact, animated: animatesChanges)
            view.onTap = canReact ? { [weak self] in self?.onToggle?(pill.emoji) } : nil
            view.onLongPress = { [weak self] in self?.onLongPress?(pill.emoji) }
            return view
        }
        for view in reusable.values {
            entering.remove(ObjectIdentifier(view))
            if animatesChanges, !view.isHidden, view.frame != .zero {
                exit(view, removing: true)
            } else {
                view.removeFromSuperview()
            }
        }
        showsAdd = canReact && !pills.isEmpty
        isEmpty = pills.isEmpty
        if animatesChanges { pendingChange = true }
        animatesChanges = true
        setNeedsLayout()
        invalidateIntrinsicContentSize()
    }

    /// Clears the row without animating, for a cell about to draw a different message.
    func prepareForReuse() {
        pillViews.forEach { $0.removeFromSuperview() }
        pillViews = []
        exiting.forEach { $0.removeFromSuperview() }
        exiting = []
        entering = []
        for view in [addButton, overflowButton] as [UIView] {
            view.layer.removeAllAnimations()
            view.alpha = 1
            view.transform = .identity
        }
        showsAdd = false
        addButton.isHidden = true
        overflowButton.isHidden = true
        isEmpty = true
        isExpanded = false
        animatesChanges = false
        pendingChange = false
        lastComputedHeight = 0
    }

    /// Whether the "+" belongs in the row. Its visibility follows this in `layoutSubviews`, where an
    /// appearance or disappearance can animate at the button's own frame.
    private var showsAdd = false

    /// Set by a reconfigure of a row already on screen and consumed by the next layout pass, which
    /// then animates the difference. Any other pass — a cell resize, a scroll — places items directly.
    private var pendingChange = false

    /// Pills removed from the row that are still animating out. Kept out of `pillViews` so layout
    /// leaves them at the spot they are leaving from.
    private var exiting: [UIView] = []

    /// Scales and fades `view` out where it stands, then removes it or hides it.
    private func exit(_ view: UIView, removing: Bool) {
        view.isUserInteractionEnabled = false
        if removing { exiting.append(view) }
        let scale = Self.reducesMotion ? 1 : ChatMotion.reactionExitScale
        ChatMotion.reactionExit.animate {
            view.alpha = 0
            view.transform = CGAffineTransform(scaleX: scale, y: scale)
        } completion: { [weak self] _ in
            guard let self else { return }
            if removing {
                view.removeFromSuperview()
                exiting.removeAll { $0 === view }
            } else if view.alpha == 0 {
                // Still meant to be gone; a return mid-exit animated it back and left alpha at 1.
                view.isHidden = true
                view.transform = .identity
                view.isUserInteractionEnabled = true
            }
        }
    }

    private static var reducesMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    /// False until the row has drawn its message once, so a cell scrolling in shows the pills it
    /// already had and only a change to them afterwards springs in.
    private var animatesChanges = false

    /// Items placed for the first time, which spring in at their own frame once `layoutSubviews`
    /// has put them there, rather than riding the cell's resize in from wherever they started.
    private var entering: Set<ObjectIdentifier> = []

    /// The height the last `layoutSubviews` pass computed, cached because `intrinsicContentSize` is
    /// asked for before a width is known and must answer something rather than nothing.
    private var lastComputedHeight: CGFloat = 0

    override func layoutSubviews() {
        super.layoutSubviews()
        let layout = currentLayout(width: bounds.width)
        // Only a pass with a real width can place anything usefully.
        let animating = pendingChange && bounds.width > 0
        if bounds.width > 0 { pendingChange = false }
        overflowButton.count = layout.hiddenCount

        var placed: [(UIView, CGRect)] = zip(pillViews, layout.pillFrames).map { ($0, $1) }
        for view in pillViews.dropFirst(layout.pillFrames.count) {
            view.isHidden = true
        }
        if let frame = layout.overflowFrame { placed.append((overflowButton, frame)) }
        if let frame = layout.addFrame { placed.append((addButton, frame)) }

        // The buttons leave the way a pill does; a pill folded into "N more" just goes, since the
        // "N more" count changing is what shows where it went.
        for (button, shown) in [(overflowButton as UIView, layout.overflowFrame != nil), (addButton, layout.addFrame != nil)] where !shown && !button.isHidden {
            if animating, button.alpha > 0 {
                exit(button, removing: false)
            } else if !animating {
                button.isHidden = true
            }
        }

        var arrivals: [UIView] = []
        var moves: [(UIView, CGRect)] = []
        for (view, frame) in placed {
            let frame = frame.offsetBy(dx: 0, dy: Self.topGap)
            let arriving = entering.remove(ObjectIdentifier(view)) != nil || view.isHidden || view.alpha < 1
            guard animating else {
                // Other passes run while a change is still animating (the cell resizing around the
                // row), so this corrects only what is actually out of place and leaves motion alone.
                if view.isHidden || view.alpha < 1 {
                    view.layer.removeAllAnimations()
                    view.isHidden = false
                    view.alpha = 1
                    view.transform = .identity
                    view.isUserInteractionEnabled = true
                }
                if !Self.sits(view, at: frame) { Self.place(view, at: frame) }
                continue
            }
            if arriving {
                // Placed outside any enclosing animation (the transcript's batch update), so the item
                // appears where it belongs instead of travelling there across the bubble.
                UIView.performWithoutAnimation {
                    view.isHidden = false
                    view.isUserInteractionEnabled = true
                    if view.alpha == 1 || view.frame == .zero {
                        view.alpha = 0
                        let scale = Self.reducesMotion ? 1 : ChatMotion.reactionEnterScale
                        view.transform = CGAffineTransform(scaleX: scale, y: scale)
                    }
                    Self.place(view, at: frame)
                }
                arrivals.append(view)
            } else if !Self.sits(view, at: frame) {
                moves.append((view, frame))
            }
        }
        if !moves.isEmpty {
            ChatMotion.reactionReflow.animate {
                for (view, frame) in moves { Self.place(view, at: frame) }
            }
        }
        if !arrivals.isEmpty {
            ChatMotion.reaction.animate {
                for view in arrivals {
                    view.alpha = 1
                    view.transform = .identity
                }
            }
        }
        let height = isEmpty ? 0 : Self.topGap + layout.height
        if height != lastComputedHeight {
            lastComputedHeight = height
            invalidateIntrinsicContentSize()
        }
    }

    /// Whether `view` already rests at `frame`. Compared through bounds and center, because `frame`
    /// is undefined while an arrival or exit still carries a transform.
    private static func sits(_ view: UIView, at frame: CGRect) -> Bool {
        view.bounds.size == frame.size && view.center == CGPoint(x: frame.midX, y: frame.midY)
    }

    private static func place(_ view: UIView, at frame: CGRect) {
        view.bounds = CGRect(origin: .zero, size: frame.size)
        view.center = CGPoint(x: frame.midX, y: frame.midY)
        view.layoutIfNeeded()
    }

    private func currentLayout(width: CGFloat) -> ReactionRowLayout {
        guard !isEmpty else { return ReactionRowLayout(pillFrames: [], overflowFrame: nil, addFrame: nil, hiddenCount: 0, height: 0) }
        return ReactionRowLayout.make(
            pillSizes: pillViews.map { $0.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize) },
            addSize: showsAdd ? Self.buttonSize : nil,
            overflowSize: { ReactionOverflowButton.size(for: $0) },
            width: width,
            maxLines: isExpanded ? nil : Self.maxLines,
            trailing: hugsTrailingEdge
        )
    }

    private static let maxLines = 2
    private static let buttonSize = CGSize(width: 28, height: 28)

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        guard !isEmpty else { return .zero }
        return CGSize(width: size.width, height: Self.topGap + currentLayout(width: size.width).height)
    }

    /// Width is always whatever the column stack hands this view (`noIntrinsicMetric`). Height is
    /// measured against the width the row has, or will have (`layoutWidth`), so the first measure of
    /// a cell and the transcript's resize for a reaction change both see the real line count.
    override var intrinsicContentSize: CGSize {
        guard !isEmpty else { return CGSize(width: UIView.noIntrinsicMetric, height: 0) }
        let width = bounds.width > 0 ? bounds.width : layoutWidth
        let height: CGFloat
        if width > 0 {
            height = Self.topGap + currentLayout(width: width).height
        } else {
            height = lastComputedHeight > 0 ? lastComputedHeight : Self.topGap + Self.buttonSize.height
        }
        return CGSize(width: UIView.noIntrinsicMetric, height: height)
    }

    /// The gap between the bubble and the first line of pills — the column's own spacing, which the
    /// column leaves out above this row so an empty row adds nothing.
    private static let topGap: CGFloat = 4

    @objc private func addTapped() {
        onAdd?()
    }

    @objc private func overflowTapped() {
        isExpanded = true
        pendingChange = true
        invalidateIntrinsicContentSize()
        setNeedsLayout()
        // The transcript re-measures a cell only when its content view's intrinsic size is invalidated,
        // and animates the new height only inside a batch update run on a spring.
        var view: UIView? = superview
        while let current = view, !(current is UICollectionViewCell) { view = current.superview }
        guard let cell = view as? UICollectionViewCell else { return }
        cell.contentView.invalidateIntrinsicContentSize()
        var container: UIView? = cell.superview
        while let current = container, !(current is UICollectionView) { container = current.superview }
        let collectionView = container as? UICollectionView
        ChatMotion.reactionReflow.animate {
            collectionView?.performBatchUpdates(nil)
            self.layoutIfNeeded()
        }
    }
}

/// Where each item of a pill row goes: the visible pills in order, then the "N more" pill standing in
/// for the rest, then the "+" button. Pure geometry, so the line cap and overflow can be tested
/// without views.
struct ReactionRowLayout: Equatable {
    var pillFrames: [CGRect]
    var overflowFrame: CGRect?
    var addFrame: CGRect?
    /// How many pills the "N more" pill stands in for; zero when every pill is shown.
    var hiddenCount: Int
    var height: CGFloat

    static let spacing: CGFloat = 6

    /// Lays the pills out within `maxLines` lines of `width`, or on as many lines as they need when
    /// `maxLines` is nil. When they don't all fit, as many pills as leave room for the "N more" pill (and
    /// the "+", if given) stay, and the rest collapse into it.
    static func make(
        pillSizes: [CGSize],
        addSize: CGSize?,
        overflowSize: (Int) -> CGSize,
        width: CGFloat,
        maxLines: Int?,
        trailing: Bool
    ) -> ReactionRowLayout {
        let trailer = addSize.map { [$0] } ?? []
        if let full = flow(pillSizes + trailer, width: width, maxLines: maxLines, trailing: trailing) {
            return ReactionRowLayout(
                pillFrames: Array(full.frames.prefix(pillSizes.count)),
                overflowFrame: nil,
                addFrame: addSize == nil ? nil : full.frames.last,
                hiddenCount: 0,
                height: full.height
            )
        }
        for shown in stride(from: pillSizes.count - 1, through: 0, by: -1) {
            let hidden = pillSizes.count - shown
            let sizes = Array(pillSizes.prefix(shown)) + [overflowSize(hidden)] + trailer
            guard let fit = flow(sizes, width: width, maxLines: maxLines, trailing: trailing) else { continue }
            return ReactionRowLayout(
                pillFrames: Array(fit.frames.prefix(shown)),
                overflowFrame: fit.frames[shown],
                addFrame: addSize == nil ? nil : fit.frames.last,
                hiddenCount: hidden,
                height: fit.height
            )
        }
        // Narrower than a single "N more" and "+": show only those rather than nothing.
        let sizes = [overflowSize(pillSizes.count)] + trailer
        let fit = flow(sizes, width: width, maxLines: nil, trailing: trailing)!
        return ReactionRowLayout(
            pillFrames: [],
            overflowFrame: fit.frames[0],
            addFrame: addSize == nil ? nil : fit.frames.last,
            hiddenCount: pillSizes.count,
            height: fit.height
        )
    }

    /// Flows `sizes` left to right, wrapping whenever the next item would overflow `width`, or `nil`
    /// if that takes more than `maxLines` lines. Each line is pushed to the trailing edge when
    /// `trailing` is set.
    private static func flow(_ sizes: [CGSize], width: CGFloat, maxLines: Int?, trailing: Bool) -> (frames: [CGRect], height: CGFloat)? {
        var lines: [[Int]] = [[]]
        var x: CGFloat = 0
        for (index, size) in sizes.enumerated() {
            if x > 0, x + size.width > width {
                lines.append([])
                x = 0
            }
            lines[lines.count - 1].append(index)
            x += size.width + spacing
        }
        if let maxLines, lines.count > maxLines { return nil }

        var frames = [CGRect](repeating: .zero, count: sizes.count)
        var y: CGFloat = 0
        for line in lines where !line.isEmpty {
            let lineWidth = line.map { sizes[$0].width }.reduce(0, +) + spacing * CGFloat(line.count - 1)
            let lineHeight = line.map { sizes[$0].height }.max() ?? 0
            var x = trailing ? max(0, width - lineWidth) : 0
            for index in line {
                frames[index] = CGRect(origin: CGPoint(x: x, y: y), size: sizes[index])
                x += sizes[index].width + spacing
            }
            y += lineHeight + spacing
        }
        return (frames, max(0, y - spacing))
    }
}

/// The "N more" pill standing in for the reactions past the second line; tapping it shows them all.
private final class ReactionOverflowButton: UIControl {

    private static let height: CGFloat = 28
    private static let horizontalPadding: CGFloat = 10
    private static let font = UIFont.default(size: 13, weight: .medium)

    private let label = UILabel()

    var count = 0 {
        didSet {
            label.text = Self.title(for: count)
            accessibilityLabel = "Show \(count) more reactions"
        }
    }

    private static func title(for count: Int) -> String { "\(count) more" }

    /// The pill's size when it reads "`count` more".
    static func size(for count: Int) -> CGSize {
        let textWidth = (title(for: count) as NSString).size(withAttributes: [.font: font]).width
        return CGSize(width: ceil(textWidth) + horizontalPadding * 2, height: height)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.white.withAlphaComponent(0.06)
        layer.cornerRadius = Self.height / 2
        clipsToBounds = true
        label.font = Self.font
        label.textColor = UIColor(Color.textMain)
        label.textAlignment = .center
        addSubview(label)
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.6 : 1 }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds
    }
}

/// The trailing "+" that opens the picker: the reaction strip's icon on a glass circle, at pill
/// height. Built from a glass effect view rather than `UIButton.Configuration.glass()`, whose platter
/// lays itself out larger than a 28pt frame.
private final class ReactionAddButton: UIControl {

    private static let iconSize: CGFloat = 20

    private let surface: UIView
    private let icon = UIImageView(image: .asset(.addReaction))

    override init(frame: CGRect) {
        if #available(iOS 26, *) {
            let glass = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
            glass.cornerConfiguration = .capsule()
            surface = glass
        } else {
            surface = UIView()
            surface.backgroundColor = UIColor.white.withAlphaComponent(0.18)
            surface.clipsToBounds = true
        }
        super.init(frame: frame)
        surface.isUserInteractionEnabled = false
        addSubview(surface)
        icon.contentMode = .scaleAspectFit
        addSubview(icon)
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = "Add reaction"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.6 : 1 }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        surface.frame = bounds
        surface.layer.cornerRadius = bounds.height / 2
        icon.frame = CGRect(
            x: (bounds.width - Self.iconSize) / 2, y: (bounds.height - Self.iconSize) / 2,
            width: Self.iconSize, height: Self.iconSize
        )
    }
}
#endif
