//
//  LazyTable.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

public struct LazyTable<Content, Header>: View where Content: View, Header: View {
    
    public var alignment: HorizontalAlignment
    public var spacing: CGFloat?
    public var contentPadding: EdgeInsets?
    public var isLazy: Bool
    public var showsIndicators: Bool
    public var content: () -> Content
    public var headerHeight: CGFloat?
    public var header: (() -> Header)?
    
    private let headerOffsetFactor: CGFloat = 0.3
    
    private var resolvedHeaderHeight: CGFloat {
        headerHeight ?? 0
    }
    
    // MARK: - Init -
    
    public init(alignment: HorizontalAlignment = .leading, spacing: CGFloat? = 0, contentPadding: EdgeInsets? = nil, isLazy: Bool = true, showsIndicators: Bool = true, @ViewBuilder content: @escaping () -> Content, headerHeight: CGFloat? = nil, @ViewBuilder header: @escaping () -> Header) {
        self.alignment       = alignment
        self.spacing         = spacing
        self.contentPadding  = contentPadding
        self.isLazy          = isLazy
        self.showsIndicators = showsIndicators
        self.content         = content
        self.headerHeight    = headerHeight
        self.header          = header
    }
    
    // MARK: - Body -
    
    public var body: some View {
        ScrollView(.vertical, showsIndicators: showsIndicators) {
            if let height = contentPadding?.top {
                Spacer()
                    .frame(width: 1, height: height)
            }
            if let header = header {
                ZStack {
                    lazyContent()
                        .padding(.top, resolvedHeaderHeight)
                    
                    GeometryReader { geometry in
                        VStack {
                            header()
                                .frame(maxHeight: resolvedHeaderHeight)
                            Spacer()
                        }
                        .offset(y: (-geometry.frame(in: .named(CoordinateSpace.scrollView)).origin.y + (contentPadding?.top ?? 0)) * headerOffsetFactor)
                    }
                }
            } else {
                lazyContent()
            }
            
            if let height = contentPadding?.bottom {
                Spacer()
                    .frame(width: 1, height: height)
            }
        }
        .coordinateSpace(name: CoordinateSpace.scrollView)
    }
    
    @ViewBuilder func lazyContent() -> some View {
        if isLazy {
            LazyVStack(alignment: alignment, spacing: spacing) {
                content()
                Spacer()
            }
        } else {
            VStack(alignment: alignment, spacing: spacing) {
                content()
                Spacer()
            }
        }
    }
}

// MARK: - Init -

extension LazyTable where Header == EmptyView {
    public init(alignment: HorizontalAlignment = .leading, spacing: CGFloat? = 0, contentPadding: EdgeInsets? = nil, isLazy: Bool = true, showsIndicators: Bool = true, @ViewBuilder content: @escaping () -> Content) {
        self.init(
            alignment: alignment,
            spacing: spacing,
            contentPadding: contentPadding,
            isLazy: isLazy,
            showsIndicators: showsIndicators,
            content: content,
            header: { EmptyView() }
        )
    }
}

// MARK: - CoordinateSpace -

private extension LazyTable {
    enum CoordinateSpace: String, Hashable, Equatable {
        case scrollView = "com.code.scrollView"
    }
}

// MARK: - ScrollBox -

extension EdgeInsets {
    public static let scrollBox: EdgeInsets = .init(top: 10, leading: 0, bottom: 10, trailing: 0)
}

// MARK: - Previews -

struct Table_Previews: PreviewProvider {
    static var previews: some View {
        Background(color: .backgroundMain) {
            LazyTable {
                ForEach(0..<100, id: \.self) { index in
                    Text("Hello")
                        .foregroundColor(.white)
                        .padding([.top, .bottom], 20)
                        .vSeparator(color: .white)
                }
            }
        }
    }
}
