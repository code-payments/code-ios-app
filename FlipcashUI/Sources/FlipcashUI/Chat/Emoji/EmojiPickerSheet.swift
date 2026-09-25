//
//  EmojiPickerSheet.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI

/// The reaction picker: search, a Frequently Used row, and the full catalog in a fixed 7-column
/// grid, grouped into the catalog's own categories behind a floating glass category bar. Presented
/// as a `.sheet` at the medium detent, draggable to large — see `ChatMessagesReactionPicker` (the
/// caller) for the detents.
///
/// Loads the ~3,944-entry catalog and the undrawable set off `EmojiCatalog`/`UndrawableEmojiCache`
/// (both actors, so this doesn't block the sheet's first frame), then reruns `EmojiPickerModel`
/// synchronously as the search text changes.
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
    @State private var catalog: EmojiCatalogContents?
    @State private var undrawable: Set<String> = []
    @State private var loadFailed = false
    /// The category at the top of the grid, which the category bar marks.
    @State private var visibleCategory: String?
    /// The grid's sections, rebuilt only when the catalog, recents or search change — building
    /// them walks the whole catalog.
    @State private var sections: [EmojiPickerModel.Section] = []
    /// A category chosen from the bar whose section the grid is still scrolling to. The indicator
    /// holds on it so it doesn't pass through every category the grid scrolls over on the way.
    @State private var pendingCategory: String?

    public init(recents: [String], onSelect: @escaping (String) -> Void) {
        self.recents = recents
        self.onSelect = onSelect
    }

    private func rebuildSections() {
        guard let catalog else { return }
        sections = EmojiPickerModel.sections(catalog: catalog, undrawable: undrawable, recents: recents, query: query)
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            if catalog != nil {
                grid
            } else if loadFailed {
                Spacer()
                Text("Couldn't load the emoji list.")
                    .foregroundStyle(Color.textSecondary)
                Spacer()
            } else {
                Spacer()
                ProgressView()
                Spacer()
            }
        }
        .background(Color.backgroundMain)
        .onChange(of: query) { rebuildSections() }
        .onChange(of: recents) { rebuildSections() }
        .task {
            do {
                let contents = try await EmojiCatalog.shared.load()
                let undrawableSet = await UndrawableEmojiCache.shared.undrawable(in: contents.emoji)
                catalog = contents
                undrawable = undrawableSet
                rebuildSections()
            } catch {
                loadFailed = true
            }
        }
    }

    // Search field and the phase-2 `$` slot, node 9768:1538 and 9768:1541.
    private var header: some View {
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
            .background(Color.black.opacity(0.26), in: .capsule)
        }
        .padding(.horizontal, Self.inset)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private static let inset: CGFloat = 16
    private static let emojiSize: CGFloat = 34
    private static let rowSpacing: CGFloat = 12
    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    private var grid: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .top) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(sections) { section in
                            VStack(alignment: .leading, spacing: Self.rowSpacing) {
                                if section.id != EmojiPickerModel.searchResultsID {
                                    Text(section.title.uppercased())
                                        .font(.default(size: 12, weight: .medium))
                                        .foregroundStyle(Color.textMain.opacity(0.5))
                                }
                                LazyVGrid(columns: Self.columns, spacing: Self.rowSpacing) {
                                    ForEach(section.entries, id: \.emoji) { entry in
                                        Button {
                                            onSelect(entry.emoji)
                                        } label: {
                                            Text(entry.emoji)
                                                .font(.system(size: Self.emojiSize))
                                                .frame(maxWidth: .infinity, minHeight: 41)
                                        }
                                        .accessibilityLabel(entry.name)
                                    }
                                }
                            }
                            .padding(.horizontal, Self.inset)
                            .id(section.id)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.top, 4)
                    .padding(.bottom, query.isEmpty ? EmojiCategoryBar.barHeight + 24 : 16)
                }
                .scrollPosition(id: $visibleCategory, anchor: .top)
                .onScrollPhaseChange { _, phase in
                    if phase == .interacting { pendingCategory = nil }
                }
                .onChange(of: visibleCategory) { _, id in
                    if id == pendingCategory { pendingCategory = nil }
                }
                .scrollDismissesKeyboard(.immediately)
                if query.isEmpty, sections.count > 1 {
                    EmojiCategoryBar(
                        categories: sections.map { .init(id: $0.id, title: $0.title, emoji: $0.entries.first?.emoji ?? "＃") },
                        selected: pendingCategory ?? visibleCategory ?? sections.first?.id
                    ) { id in
                        pendingCategory = id
                        withAnimation(Self.scrollSpring) { proxy.scrollTo(id, anchor: .top) }
                    }
                        .padding(.bottom, 4)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
    }

    private static let scrollSpring = Animation.spring(duration: 0.35, bounce: 0.2)
}

/// The floating jump bar to each category, a glass capsule over the grid (node 9768:1624). The
/// selected category sits on its own glass indicator. Like the tab bar, the indicator can be
/// pressed and dragged across the bar; `onSelect` fires only once it's let go over a category.
///
/// Its own view so a drag redraws only the bar, not the grid of every emoji behind it.
private struct EmojiCategoryBar: View {

    struct Category: Equatable {
        let id: String
        let title: String
        let emoji: String
    }

    let categories: [Category]
    let selected: String?
    let onSelect: (String) -> Void

    /// Where the finger is along the bar while it drags the indicator, `nil` otherwise.
    @State private var dragX: CGFloat?
    /// The slot under the finger while dragging, for a haptic at each new one.
    @State private var hovered: Int?

    var body: some View {
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
                            onSelect(category.id)
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
                        onSelect(categories[index].id)
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
