//
//  SearchBar.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

#if canImport(UIKit)

import SwiftUI

public struct SearchBar: UIViewRepresentable {
    
    @Binding var content: String
    @Binding var isActive: Bool
    
    private let configuration: (UISearchBar) -> Void
    
    public init(content: Binding<String>, isActive: Binding<Bool>, configuration: @escaping (UISearchBar) -> Void) {
        self._content  = content
        self._isActive = isActive
        self.configuration = configuration
    }
    
    public func makeCoordinator() -> SearchBarCoordinator {
        SearchBarCoordinator(content: $content, isActive: $isActive)
    }
    
    public func makeUIView(context: Context) -> UISearchBar {
        let searchBar = UISearchBar(frame: .zero)
        context.coordinator.setup(for: searchBar)
        return searchBar
    }
    
    public func updateUIView(_ searchBar: UISearchBar, context: Context) {
        searchBar.text = content
        searchBar.setContentHuggingPriority(.defaultHigh, for: .vertical)
        searchBar.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        searchBar.setBackgroundImage(UIImage.solid(color: .clear), for: .any, barMetrics: .default)
        
        configuration(searchBar)
        
        if isActive {
            searchBar.becomeFirstResponder()
        } else {
            _ = searchBar.resignFirstResponder()
        }
    }
}

// MARK: - SearchBarCoordinator -

public class SearchBarCoordinator: NSObject, UISearchBarDelegate {
    
    @Binding var content: String
    @Binding var isActive: Bool
    
    init(content: Binding<String>, isActive: Binding<Bool>) {
        self._content  = content
        self._isActive = isActive
        
        super.init()
    }
    
    func setup(for searchBar: UISearchBar) {
        searchBar.delegate = self
        searchBar.enablesReturnKeyAutomatically = false
    }
    
    // MARK: - UISearchBarDelegate -
    
    public func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBarTextDidEndEditing(searchBar)
    }
    
    public func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        content = searchBar.text ?? ""
        searchBar.text = content
    }
    
    public func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        DispatchQueue.main.async {
            if !self.isActive {
                self.isActive = true
            }
        }
    }
    
    public func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
        DispatchQueue.main.async {
            if self.isActive {
                self.isActive = false
            }
        }
    }
}

#endif
