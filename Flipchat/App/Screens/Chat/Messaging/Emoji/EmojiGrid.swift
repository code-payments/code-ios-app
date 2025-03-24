//
//  EmojiGrid.swift
//  Code
//
//  Created by Dima Bart on 2025-03-19.
//

import SwiftUI
import CodeUI

struct EmojiGrid: View {
    
    let action: (Emoji) -> Void
    
    @StateObject private var emojiController = try! EmojiController()
    
    @State private var searchTerm: String = ""
    
    private var isShowingSearchResults: Bool {
        !searchTerm.isEmpty
    }
    
    private var results: [Emoji] {
        (try? emojiController.search(term: searchTerm)) ?? []
    }
    
    // MARK: - Init -
    
    init(action: @escaping (Emoji) -> Void) {
        self.action = action
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 0) {
                SearchBar(text: $searchTerm, placeholder: "Search emoji")
                    .padding(.horizontal, 10)
                    .zIndex(1)
                
                if isShowingSearchResults {
                    emojiGrid()
                } else {
                    searchResults()
                }
            }
            .animation(.easeInOut(duration: 0.1), value: isShowingSearchResults)
        }
    }
    
    @ViewBuilder func emojiGrid() -> some View {
        ScrollBox(color: .backgroundMain) {
            List(results) { emoji in
                Button {
                    didSelect(emoji: emoji)
                } label: {
                    HStack(spacing: 10) {
                        Text(emoji.symbol)
                            .font(.system(size: 32))
                        Text(emoji.shortName)
                            .font(.appTextMedium)
                    }
                }
                .listRowBackground(Color.backgroundMain)
            }
            .listStyle(.plain)
            .scrollDismissesKeyboard(.interactively)
        }
        .transition(.opacity.combined(with: .blurReplace()))
    }
    
    @ViewBuilder func searchResults() -> some View {
        ScrollBox(color: .backgroundMain) {
            EmojiGridView(groups: emojiController.emojis) { emoji in
                didSelect(emoji: emoji)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .transition(.opacity.combined(with: .blurReplace()))
    }
    
    private func didSelect(emoji: Emoji) {
        Feedback.buttonTap()
        action(emoji)
    }
}

extension Emoji: Identifiable {
    public var id: String {
        symbol
    }
}

#Preview {
    EmojiGrid(action: { _ in })
}

// MARK: - SearchBar -

private struct SearchBar: UIViewRepresentable {
    
    @Binding var text: String
    
    let placeholder: String
    let onTextChanged: ((String) -> Void)?
    
    init(text: Binding<String>, placeholder: String, onTextChanged: ((String) -> Void)? = nil) {
        self._text = text
        self.placeholder = placeholder
        self.onTextChanged = onTextChanged
    }
    
    func makeUIView(context: Context) -> UISearchBar {
        let searchBar             = UISearchBar()
        searchBar.placeholder     = placeholder
        searchBar.delegate        = context.coordinator
        searchBar.backgroundImage = .solid(color: .backgroundMain)
        searchBar.searchTextField.clearButtonMode = .never
        
        context.coordinator.searchBar = searchBar
        
        return searchBar
    }
    
    func updateUIView(_ uiView: UISearchBar, context: Context) {
        uiView.text = text
        uiView.showsCancelButton = !text.isEmpty
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onTextChanged: onTextChanged)
    }
}

// MARK: - Coordinator -

extension SearchBar {
    class Coordinator: NSObject, UISearchBarDelegate {
        
        @Binding var text: String
        
        let onTextChanged: ((String) -> Void)?
        
        var searchBar: UISearchBar!
        
        init(text: Binding<String>, onTextChanged: ((String) -> Void)?) {
            self._text = text
            self.onTextChanged = onTextChanged
        }
        
        // MARK: - Action -
        
        private func setCancelButton(visible: Bool) {
            searchBar.setShowsCancelButton(visible, animated: true)
        }
        
        // MARK: - UISearchBarDelegate -
        
        func searchBarShouldBeginEditing(_ searchBar: UISearchBar) -> Bool {
            setCancelButton(visible: true)
            return true
        }
        
        func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
            if searchBar.text?.isEmpty == true {
                setCancelButton(visible: false)
            }
        }
        
        func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
            setCancelButton(visible: true)
            text = searchText
            onTextChanged?(searchText)
        }
        
        func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
            setCancelButton(visible: false)
            
            text = ""
            searchBar.text = ""
            searchBar.resignFirstResponder()
            onTextChanged?("")
        }
        
        func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
            searchBar.resignFirstResponder()
        }
    }
}

// MARK: - EmojiGridView -

private struct EmojiGridView: UIViewRepresentable {
    
    let groups: [EmojiGroup]
    let onTap: (Emoji) -> Void
    
    func makeUIView(context: Context) -> UICollectionView {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 5
        layout.minimumLineSpacing      = 5
        layout.sectionInset = UIEdgeInsets(
            top: 0,
            left: 20,
            bottom: 0,
            right: 20
        )
        
        layout.headerReferenceSize = CGSize(width: 0, height: 50)
        
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.keyboardDismissMode = .interactive
        
        collectionView.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "cell")
        collectionView.register(HeaderView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "header")
        
        collectionView.delegate   = context.coordinator
        collectionView.dataSource = context.coordinator
        
        return collectionView
    }
    
    func updateUIView(_ collectionView: UICollectionView, context: Context) {
        context.coordinator.groups = groups
        collectionView.reloadData()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(groups: groups, onTap: onTap)
    }
}

// MARK: - Coordinator -

extension EmojiGridView {
    class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
        
        var groups: [EmojiGroup]
        let onTap: (Emoji) -> Void
        
        private let dimension: CGFloat = 45
        
        init(groups: [EmojiGroup], onTap: @escaping (Emoji) -> Void) {
            self.groups = groups
            self.onTap = onTap
        }
        
        // MARK: - Cell -
        
        @ViewBuilder func item(emoji: Emoji) -> some View {
            Text(emoji.symbol)
                .font(.system(size: 32))
                .frame(width: dimension, height: dimension)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(emoji.symbol)
        }
        
        private func group(at indexPath: IndexPath) -> EmojiGroup {
            groups[indexPath.section]
        }
        
        private func emoji(at indexPath: IndexPath) -> Emoji {
            group(at: indexPath).emojis[indexPath.item]
        }
        
        // MARK: - DataSource -
        
        func numberOfSections(in collectionView: UICollectionView) -> Int {
            groups.count
        }
        
        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            groups[section].emojis.count
        }
        
        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            let cell  = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath)
            let emoji = emoji(at: indexPath)
            
            cell.contentConfiguration = UIHostingConfiguration {
                item(emoji: emoji)
            }
            
            return cell
        }
        
        func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
            guard kind == UICollectionView.elementKindSectionHeader else {
                return UICollectionReusableView()
            }
            
            let header = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "header", for: indexPath) as! HeaderView
            let group  = groups[indexPath.section]
            
            header.set(title: group.name)
//            header.backgroundColor = .green
            
            return header
        }
        
        // MARK: - Delegate -
        
        func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
            let padding: CGFloat = 40 // Section insets (left + right)
            let spacing: CGFloat = 5  // Minimum interitem spacing
            
            let availableWidth = collectionView.bounds.width - padding
            let itemsPerRow    = floor(availableWidth / (dimension + spacing))
            let itemWidth      = (availableWidth - (itemsPerRow - 1) * spacing) / itemsPerRow
            
            return CGSize(width: itemWidth, height: itemWidth)
        }
        
        func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            onTap(emoji(at: indexPath))
        }
    }
}

// MARK: - HeaderView -

private class HeaderView: UICollectionReusableView {
    
    private let label: UILabel = {
        let label = UILabel()
        label.font = .appTextMedium
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        addSubview(label)
        
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        ])
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    func set(title: String) {
        label.text = title
    }
}
