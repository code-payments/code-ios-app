//
//  EmojiPickerSheet.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI

/// The reaction picker: a glass search field, a Frequently Used row, and the catalog's base emoji
/// in a fixed 7-column grid, grouped into the catalog's own categories behind a floating glass
/// category bar. A long press on an emoji with skin tones opens them. Presented as a `.sheet` at
/// the medium detent, draggable to large — see `ChatMessagesReactionPicker` (the caller) for the
/// detents.
///
/// Loads the catalog and the undrawable set off `EmojiCatalog`/`UndrawableEmojiCache` and indexes
/// them off the main thread, so none of it blocks the sheet's first frame. A search rebuilds the
/// sections off the main thread too, once typing pauses.
public struct EmojiPickerSheet: View {

    /// Fired with the chosen emoji. The caller toggles the reaction and dismisses the sheet — this
    /// view doesn't dismiss itself, since the toggle might still be validated by the caller (the
    /// too-many-reaction-types limit) before the sheet goes away.
    public let onSelect: (String) -> Void
    /// The current recents, most-used first, already capped by the caller
    /// (`RecentReactionsStore.pickerRowLimit`) and filtered for drawability — this view does not
    /// re-derive them, since the ranking source lives above this module.
    public let recents: [String]

    @State private var query = ""
    @State private var index: EmojiPickerModel.Index?
    @State private var loadFailed = false
    /// The grid's sections, rebuilt only when the catalog, recents or search change — building
    /// them walks the whole catalog.
    @State private var sections: [EmojiPickerModel.Section] = []
    @State private var categories = EmojiCategoryTracker()

    public init(recents: [String], onSelect: @escaping (String) -> Void) {
        self.recents = recents
        self.onSelect = onSelect
    }

    /// What `sections` is built from, so one `task(id:)` rebuilds on any of them.
    private struct SectionsInput: Equatable {
        let query: String
        let recents: [String]
        let isLoaded: Bool
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scrollEdgeBar(.top) { searchField }
            .scrollEdgeBar(.bottom) { categoryBar }
            .softScrollEdge(for: [.top, .bottom])
            .background(Color.backgroundMain)
            .task {
                do {
                    let contents = try await EmojiCatalog.shared.load()
                    let undrawable = await UndrawableEmojiCache.shared.undrawable(in: contents.emoji)
                    index = await Task.detached(priority: .userInitiated) {
                        EmojiPickerModel.Index(catalog: contents, undrawable: undrawable)
                    }.value
                } catch {
                    loadFailed = true
                }
            }
            .task(id: SectionsInput(query: query, recents: recents, isLoaded: index != nil)) {
                await rebuildSections()
            }
    }

    /// Rebuilds `sections` off the main thread, waiting out a burst of typing first.
    private func rebuildSections() async {
        guard let index else { return }
        let query = query
        let recents = recents
        if !query.isEmpty {
            do { try await Task.sleep(for: Self.searchDebounce) } catch { return }
        }
        let built = await Task.detached(priority: .userInitiated) {
            EmojiPickerModel.sections(index: index, recents: recents, query: query)
        }.value
        guard !Task.isCancelled else { return }
        sections = built
    }

    @ViewBuilder
    private var content: some View {
        if let index {
            EmojiGrid(
                sections: sections,
                index: index,
                categories: categories,
                bottomPadding: query.isEmpty ? 8 : 16,
                onSelect: onSelect
            )
        } else if loadFailed {
            Text("Couldn't load the emoji list.")
                .foregroundStyle(Color.textSecondary)
        } else {
            ProgressView()
        }
    }

    // Search field and the phase-2 `$` slot, node 9768:1538 and 9768:1541.
    private var searchField: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.textSecondary)
                TextField("Search", text: $query)
                    .foregroundStyle(Color.textMain)
                    .autocorrectionDisabled()
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.textSecondary)
                    }
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .glassFieldBackground(cornerRadius: 22)
        }
        .padding(.horizontal, EmojiGrid.inset)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var categoryBar: some View {
        if query.isEmpty, sections.count > 1 {
            EmojiCategoryBar(
                categories: sections.map { .init(id: $0.id, title: $0.title, emoji: Self.barEmoji(for: $0)) },
                tracker: categories
            )
            .padding(.bottom, 4)
        }
    }

    private static let searchDebounce = Duration.milliseconds(150)

    /// The category bar's icon for a section. Frequently Used gets a fixed ❤️ so its slot doesn't
    /// change as your recents do; catalog categories use their first emoji.
    private static func barEmoji(for section: EmojiPickerModel.Section) -> String {
        if section.id == EmojiPickerModel.frequentlyUsedID { return "❤️" }
        return section.entries.first?.emoji ?? "＃"
    }
}

/// Which category the grid is showing and which one the bar asked for, shared between the two so
/// scrolling across a category redraws only the bar.
@MainActor @Observable
private final class EmojiCategoryTracker {

    /// The cell at the top of the grid, written by the grid's scroll position. Not observed: it
    /// changes every row, and only the category it falls in matters.
    @ObservationIgnored var topCell: EmojiGrid.CellID? {
        didSet {
            let category = topCell?.section
            if visible != category { visible = category }
            if pending == category { pending = nil }
        }
    }

    /// The category at the top of the grid.
    private(set) var visible: String?

    /// A category chosen from the bar whose section the grid is still scrolling to. The indicator
    /// holds on it so it doesn't pass through every category the grid scrolls over on the way.
    private(set) var pending: String?

    /// Asks the grid to scroll to `category`, handled by the grid's scroll reader.
    private(set) var request: (category: String, token: Int)?

    func select(_ category: String) {
        pending = category
        request = (category, (request?.token ?? 0) + 1)
    }

    /// A finger on the grid overrides a jump still in flight.
    func userDidScroll() {
        if pending != nil { pending = nil }
    }
}

/// The emoji grid: one lazy grid for every section, so a fling lays out rows rather than whole
/// categories.
private struct EmojiGrid: View {

    /// A cell's identity. An emoji can sit in both Frequently Used and its category, so the
    /// section is part of it.
    struct CellID: Hashable {
        let section: String
        let emoji: String
    }

    let sections: [EmojiPickerModel.Section]
    let index: EmojiPickerModel.Index
    let categories: EmojiCategoryTracker
    let bottomPadding: CGFloat
    let onSelect: (String) -> Void

    static let inset: CGFloat = 16
    private static let rowSpacing: CGFloat = 12
    private static let sectionGap: CGFloat = 8
    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        @Bindable var categories = categories
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: Self.columns, alignment: .leading, spacing: Self.rowSpacing) {
                    ForEach(sections) { section in
                        Section {
                            ForEach(section.entries, id: \.emoji) { entry in
                                EmojiCell(entry: entry, toneFamily: index.toneFamily(of: entry.emoji), onSelect: onSelect)
                                    .id(CellID(section: section.id, emoji: entry.emoji))
                            }
                        } header: {
                            if section.id != EmojiPickerModel.searchResultsID {
                                Text(section.title.uppercased())
                                    .font(.default(size: 12, weight: .medium))
                                    .foregroundStyle(Color.textMain.opacity(0.5))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, section.id == sections.first?.id ? 0 : Self.sectionGap)
                                    .id(section.id)
                            }
                        }
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, Self.inset)
                .padding(.top, 4)
                .padding(.bottom, bottomPadding)
            }
            .scrollPosition(id: $categories.topCell, anchor: .top)
            .onScrollPhaseChange { _, phase in
                if phase == .interacting { categories.userDidScroll() }
            }
            .onChange(of: categories.request?.token) {
                guard let category = categories.request?.category else { return }
                withAnimation(Self.scrollSpring) { proxy.scrollTo(category, anchor: .top) }
            }
            .scrollDismissesKeyboard(.immediately)
        }
    }

    private static let scrollSpring = Animation.spring(duration: 0.35, bounce: 0.2)
}

/// One emoji in the grid. A tap picks it; when it has skin tones, a long press opens them.
private struct EmojiCell: View {

    let entry: EmojiCatalogEntry
    /// The base and its tones, or empty when the emoji has none.
    let toneFamily: [EmojiCatalogEntry]
    let onSelect: (String) -> Void

    @State private var showsTones = false

    private static let emojiSize: CGFloat = 34

    var body: some View {
        let glyph = Text(entry.emoji)
            .font(.system(size: Self.emojiSize))
            .frame(maxWidth: .infinity, minHeight: 41)
            .contentShape(.rect)
            .accessibilityElement()
            .accessibilityLabel(entry.name)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onSelect(entry.emoji) }
        if toneFamily.isEmpty {
            glyph
                .onTapGesture { onSelect(entry.emoji) }
        } else {
            // One composed gesture: separate tap and long-press modifiers let the tap win a held press.
            glyph
                .gesture(
                    LongPressGesture(minimumDuration: 0.35)
                        .onEnded { _ in showsTones = true }
                        .exclusively(before: TapGesture().onEnded { onSelect(entry.emoji) })
                )
                .accessibilityAction(named: "Skin tones") { showsTones = true }
                .sensoryFeedback(.impact(weight: .light), trigger: showsTones) { _, new in new }
                .popover(isPresented: $showsTones) {
                    EmojiTonePicker(family: toneFamily) { emoji in
                        showsTones = false
                        onSelect(emoji)
                    }
                    .presentationCompactAdaptation(.popover)
                }
        }
    }
}

/// The skin tones for one emoji: the base and its five tones on the first row, and for a two-person
/// emoji the mixed-tone pairs in rows of five beneath the tones.
private struct EmojiTonePicker: View {

    let family: [EmojiCatalogEntry]
    let onSelect: (String) -> Void

    private static let cellSize: CGFloat = 44
    private static let perRow = 5

    var body: some View {
        let base = family[0]
        let variants = Array(family.dropFirst())
        let rows = stride(from: 0, to: variants.count, by: Self.perRow).map {
            Array(variants[$0..<min($0 + Self.perRow, variants.count)])
        }
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(rows.enumerated()), id: \.offset) { row, entries in
                HStack(spacing: 4) {
                    if row == 0 {
                        cell(base)
                    } else {
                        Color.clear.frame(width: Self.cellSize, height: Self.cellSize)
                    }
                    ForEach(entries, id: \.emoji, content: cell)
                }
            }
        }
        .padding(8)
    }

    private func cell(_ entry: EmojiCatalogEntry) -> some View {
        Button {
            onSelect(entry.emoji)
        } label: {
            Text(entry.emoji)
                .font(.system(size: 32))
                .frame(width: Self.cellSize, height: Self.cellSize)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entry.name)
    }
}

/// The floating jump bar to each category, a glass capsule over the grid (node 9768:1624). The
/// selected category sits on its own glass indicator. Like the tab bar, the indicator can be
/// pressed and dragged across the bar; it selects a category only once it's let go over one.
///
/// Its own view so a drag redraws only the bar, not the grid of every emoji behind it.
private struct EmojiCategoryBar: View {

    struct Category: Equatable {
        let id: String
        let title: String
        let emoji: String
    }

    let categories: [Category]
    let tracker: EmojiCategoryTracker

    /// Where the finger is along the bar while it drags the indicator, `nil` otherwise.
    @State private var dragX: CGFloat?
    /// The slot under the finger while dragging, for a haptic at each new one.
    @State private var hovered: Int?

    var body: some View {
        let selected = tracker.pending ?? tracker.visible ?? categories.first?.id
        let selectedIndex = categories.firstIndex { $0.id == selected } ?? 0
        GeometryReader { geometry in
            let slot = geometry.size.width / CGFloat(max(categories.count, 1))
            let restingX = slot * (CGFloat(selectedIndex) + 0.5)
            let indicatorX = dragX.map { min(max($0, slot / 2), geometry.size.width - slot / 2) } ?? restingX
            ZStack(alignment: .leading) {
                CategoryIndicator()
                    .frame(width: min(slot, Self.indicatorHeight + 6), height: Self.indicatorHeight)
                    .scaleEffect(dragX == nil ? 1 : 1.15)
                    .offset(x: indicatorX - min(slot, Self.indicatorHeight + 6) / 2)
                HStack(spacing: 0) {
                    ForEach(categories, id: \.id) { category in
                        Button {
                            tracker.select(category.id)
                        } label: {
                            Text(category.emoji)
                                .font(.system(size: 20))
                                .frame(width: slot, height: geometry.size.height)
                        }
                        .accessibilityLabel(category.title)
                        .accessibilityAddTraits(category.id == selected ? .isSelected : [])
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        // Follow the finger 1:1; only the press and the release animate.
                        var transaction = Transaction()
                        transaction.disablesAnimations = dragX != nil
                        withTransaction(transaction) { dragX = value.location.x }
                        let index = Self.index(at: value.location.x, slot: slot, count: categories.count)
                        if hovered != index { hovered = index }
                    }
                    .onEnded { value in
                        let index = Self.index(at: value.location.x, slot: slot, count: categories.count)
                        hovered = nil
                        withAnimation(Self.settleSpring) { dragX = nil }
                        tracker.select(categories[index].id)
                    }
            )
        }
        .padding(.horizontal, 6)
        .animation(Self.settleSpring, value: selectedIndex)
        .sensoryFeedback(.selection, trigger: hovered) { _, new in new != nil }
        .frame(height: Self.barHeight)
        .capsuleGlassBackground()
        .padding(.horizontal, 30)
    }

    private static func index(at x: CGFloat, slot: CGFloat, count: Int) -> Int {
        min(max(Int(x / slot), 0), count - 1)
    }

    static let barHeight: CGFloat = 45
    private static let indicatorHeight: CGFloat = 38
    private static let settleSpring = Animation.spring(duration: 0.35, bounce: 0.2)
}

/// The glass under the category in view.
private struct CategoryIndicator: View {
    var body: some View {
        if #available(iOS 26, *) {
            Color.clear.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            Capsule().fill(Color.textMain.opacity(0.14))
        }
    }
}
