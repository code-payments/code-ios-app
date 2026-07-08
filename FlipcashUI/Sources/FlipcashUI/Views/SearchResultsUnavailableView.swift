//
//  SearchResultsUnavailableView.swift
//  FlipcashUI
//

import SwiftUI

/// The app's themed equivalent of `ContentUnavailableView.search(text:)`, shown
/// over a list when a search matches nothing.
public struct SearchResultsUnavailableView: View {

    private let searchText: String

    // MARK: - Init -

    public init(searchText: String) {
        self.searchText = searchText
    }

    // MARK: - Body -

    public var body: some View {
        ContentUnavailableView {
            Label {
                Text("No Results for “\(searchText)”")
                    .font(.appTextLarge)
                    .foregroundStyle(Color.textMain)
            } icon: {
                Image(systemName: "magnifyingglass")
            }
        } description: {
            Text("Check the spelling or try a new search.")
                .font(.appTextMedium)
                .foregroundStyle(Color.textSecondary)
        }
    }
}

// MARK: - Previews -

struct SearchResultsUnavailableView_Previews: PreviewProvider {
    static var previews: some View {
        Background(color: .backgroundMain) {
            SearchResultsUnavailableView(searchText: "Zzzqqq")
        }
    }
}
