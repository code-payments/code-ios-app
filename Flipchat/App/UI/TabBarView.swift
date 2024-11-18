//
//  TabBarView.swift
//  Code
//
//  Created by Dima Bart on 2024-11-02.
//

import SwiftUI
import CodeUI

struct TabBarView<Content>: View where Content: View {
    
    @Binding var selection: TabBarItem
    @Binding var isTabBarVisible: Bool
    
    @State private var tabBarItems: [TabBarItem] = []
    
    private let content: () -> Content
    
    // MARK: - Init -
    
    init(selection: Binding<TabBarItem>, isTabBarVisible: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) {
        self._selection = selection
        self._isTabBarVisible = isTabBarVisible
        self.content = content
    }
    
    // MARK: - Body -
    
    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            GeometryReader { geometry in
                content()
                    .frame(
                        width: geometry.size.width,
                        height: geometry.size.height
                    )
            }
            
            if isTabBarVisible {
                TabBarToolbar(
                    items: tabBarItems,
                    selection: $selection
                )
                .transition(.offset(x: 0, y: 80))
            }
        }
        .animation(.easeOut(duration: 0.05), value: isTabBarVisible)
        .onPreferenceChange(TabBarItemPreferenceKey.self) { items in
            self.tabBarItems = items
        }
    }
}

// MARK: - TabBarToolbar -

struct TabBarToolbar: View {
    
    let items: [TabBarItem]
    
    @Binding var selection: TabBarItem
    
    @Namespace private var namespace
    
    init(items: [TabBarItem], selection: Binding<TabBarItem>) {
        self.items = items
        self._selection = selection
    }
    
    var body: some View {
        HStack {
            ForEach(0..<items.count, id: \.self) { index in
                Button {
                    selection = items[index]
                } label: {
                    tabView(for: items[index])
                }
                .buttonStyle(TabItemStyle())
            }
        }
        .padding(.bottom, -5)
        .background(
            ZStack(alignment: .top) {
                Color.darkPurple
                Color.white.opacity(0.1)
                    .frame(height: 1)
                    .frame(maxWidth: .infinity)
            }
            .ignoresSafeArea(edges: .bottom)
        )
    }
    
    @ViewBuilder private func tabView(for tabBarItem: TabBarItem) -> some View {
        let selected = selection == tabBarItem
        VStack {
            Image.asset(tabBarItem.asset)
                .renderingMode(.template)
                .resizable()
                .frame(width: 20, height: 20)
            Text(tabBarItem.title)
                .font(.appTextSmall)
        }
        .frame(maxWidth: .infinity)
        .foregroundColor(selected ? .textMain : .textSecondary.opacity(0.7))
        .padding(.top, 14)
        .background {
            if selected {
                Color.lightPurple.opacity(0.3)
                    .matchedGeometryEffect(id: "tabContent", in: namespace)
                    .edgesIgnoringSafeArea(.bottom)
            }
        }
        .animation(.easeOutFastest, value: selection)
    }
}

private struct TabItemStyle: ButtonStyle {

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
    }
}

extension Color {
    static let darkPurple = Color(r: 40, g: 23, b: 110)
    static let lightPurple = Color(r: 68, g: 48, b: 145)
}

// MARK: - TabBarItem -

struct TabBarItem: Equatable, Hashable, Sendable {
    var title: String
    var asset: Asset
}

// MARK: - PreferenceKey -

struct TabBarItemPreferenceKey: PreferenceKey {
    
    static let defaultValue: [TabBarItem] = []
    
    static func reduce(value: inout [TabBarItem], nextValue: () -> [TabBarItem]) {
        value += nextValue()
    }
}

struct TabBarItemViewModifer: ViewModifier {
    
    let tabBarItem: TabBarItem
    let selection: TabBarItem
    
    func body(content: Content) -> some View {
        let selected = tabBarItem == selection
        content
            .opacity(selected ? 1 : 0)
            .preference(key: TabBarItemPreferenceKey.self, value: [tabBarItem])
    }
}

extension View {
    func tabBarItem(title: String, asset: Asset, selection: TabBarItem) -> some View {
        modifier(
            TabBarItemViewModifer(
                tabBarItem: TabBarItem(
                    title: title,
                    asset: asset
                ),
                selection: selection
            )
        )
    }
}

// MARK: - Preview -

#Preview {
    @Previewable @State var selection: TabBarItem = .init(title: "Chat", asset: .bubble)
    
    TabBarView(selection: $selection, isTabBarVisible: .constant(true)) {
        Background(color: .backgroundMain) {
            NavigationStack {
                Color.backgroundMain
                    .navigationTitle("Chat")
            }
        }
        .tabBarItem(title: "Chat", asset: .bubble, selection: selection)
        
        Background(color: .backgroundMain) {
            NavigationStack {
                Color.backgroundMain
                    .navigationTitle("Balance")
            }
        }
        .tabBarItem(title: "Balance", asset: .bubble, selection: selection)
    }
}
