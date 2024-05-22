//
//  Banner.swift
//  Code
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI
import CodeUI

public struct Banner {
    
    public var actionStyle: ActionStyle {
        switch _actionStyle {
        case .inline:
            if actions.count > 2 {
                return .stacked
            }
            
            switch position {
            case .top:
                return .inline
            case .bottom:
                return .stacked
            }
            
        case .stacked:
            return .stacked
        }
    }
    
    public let id: UUID
    public var style: Style
    public var title: String?
    public var description: String?
    public var position: Position
    public var actions: [Action]
    
    public var isDismissable: Bool
    
    private(set) var dismissAction: VoidAction?
    
    private var _actionStyle: ActionStyle
    
    internal var usesActionSeparators: Bool {
        switch position {
        case .top:
            return true
        case .bottom:
            return false
        }
    }
    
    // MARK: - Init -
    
    public init(style: Style, title: String? = nil, description: String? = nil, position: Position = .top, isDismissable: Bool? = nil, actionStyle: ActionStyle = .inline, actions: [Action] = []) {
        self.id = UUID()
        self.style = style
        self.title = title
        self.description = description
        self.position = position
        self.isDismissable = isDismissable ?? (position == .bottom)
        self._actionStyle = actionStyle
        self.actions = actions
    }
    
    mutating func setDismissAction(action: @escaping VoidAction) {
        dismissAction = action
    }
}

// MARK: - Style -

extension Banner {
    public enum Style: Hashable {
        case success(Icon)
        case notification
        case warning
        case error
        case networkError
        case neutral
    }
}

extension Banner.Style {
    var backgroundColor: Color {
        switch self {
        case .success:
            return .bannerDark
        case .notification:
            return .bannerInfo
        case .warning:
            return .bannerWarning
        case .error, .networkError:
            return .bannerError
        case .neutral:
            return .init(white: 0.5)
        }
    }
    
    var separatorColor: Color {
        switch self {
        case .notification, .success:
            return .white.opacity(0.12)
        case .warning, .error, .neutral, .networkError:
            return .black.opacity(0.3)
        }
    }
    
    var accessoryImage: Image {
        switch self {
        case .success(let icon):
            return icon.image
        case .notification:
            return Image(systemName: "checkmark.circle.fill")
        case .warning:
            return Image(systemName: "exclamationmark.octagon.fill")
        case .error:
            return Image(systemName: "xmark.octagon.fill")
        case .networkError:
            return Image(systemName: "wifi.slash")
        case .neutral:
            return Image(systemName: "exclamationmark.octagon.fill")
        }
    }
    
    var accessoryColor: Color {
        switch self {
        case .success(let icon):
            return icon.color
        case .notification, .warning, .error, .networkError, .neutral:
            return .textMain
        }
    }
    
    static var overlayColor: Color {
        .black.opacity(0.4)
    }
}

extension Banner {
    public enum Icon: Equatable, Hashable {
        
        case checkmark(Color)
        
        var color: Color {
            switch self {
            case .checkmark(let color):
                return color
            }
        }
        
        var image: Image {
            switch self {
            case .checkmark:
                Image(systemName: "checkmark.circle.fill")
            }
        }
    }
}

// MARK: - Action -

extension Banner {
    public struct Action {
        
        public var title: String
        public var style: Style
        public var action: VoidAction
        
        private init(title: String, style: Style, action: @escaping VoidAction) {
            self.title  = title
            self.style  = style
            self.action = action
        }
        
        public static func cancel(title: String, action: @escaping VoidAction = {}) -> Action {
            .standard(title: title, action: action)
        }
        
        public static func standard(title: String, action: @escaping VoidAction) -> Action {
            .init(title: title, style: .standard, action: action)
        }
        
        public static func destructive(title: String, action: @escaping VoidAction) -> Action {
            .init(title: title, style: .destructive, action: action)
        }
        
        public static func prominent(title: String, action: @escaping VoidAction) -> Action {
            .init(title: title, style: .prominent, action: action)
        }
        
        public static func subtle(title: String, action: @escaping VoidAction) -> Action {
            .init(title: title, style: .subtle, action: action)
        }
        
        fileprivate func appending(_ action: @escaping VoidAction) -> Action {
            Action(
                title: title,
                style: style,
                action: {
                    self.action()
                    action()
                }
            )
        }
    }
}

// MARK: - Action Style -

extension Banner.Action {
    public enum Style {
        case standard
        case prominent
        case destructive
        case subtle
    }
}

// MARK: - ActionStyle -

extension Banner {
    public enum ActionStyle {
        case inline
        case stacked
    }
}

// MARK: - Position -

extension Banner {
    public enum Position {
        case top
        case bottom
    }
}

// MARK: - View -

extension View {
    public func banner(_ banner: Banner?) -> some View {
        return self.modifier(BannerModifier(banner: banner))
    }
}

// MARK: - Modifier -

public struct BannerModifier: ViewModifier {
    
    private let banner: Banner?
    
    // MARK: - Init -
    
    public init(banner: Banner?) {
        self.banner = banner
    }
    
    // MARK: - Body -
    
    public func body(content: Content) -> some View {
        ZStack(alignment: .top) {
            content
            bannerContainer(banner: banner)
        }
    }
    
    @ViewBuilder private func bannerContainer(banner: Banner?) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: containerAlignment(for: banner?.position ?? .top)) {
                if let banner = banner {
                    Rectangle()
                        .fill(Banner.Style.overlayColor)
                        .edgesIgnoringSafeArea(.all)
                        .zIndex(10)
                        .onTapGesture {
                            if banner.isDismissable {
                                banner.dismissAction?()
                            }
                        }
                    bannerView(banner: banner)
                        .zIndex(11)
                        .transition(
                            transition(for: banner.position, geometry: geometry)
                        )
                }
            }
            .animation(animation(), value: banner == nil)
        }
    }
    
    @ViewBuilder private func bannerView(banner: Banner) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: titleSpacing(for: banner.position)) {
                if let title = banner.title {
                    HStack(alignment: .center, spacing: 10) {
                        if banner.position == .top {
                            banner.style.accessoryImage
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .foregroundColor(banner.style.accessoryColor)
                                .frame(width: 15, height: 15, alignment: .center)
                        }
                        Text(title)
                            .font(.appTextLarge)
                            .frame(maxWidth: .infinity, alignment: alignment(for: banner.position))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let description = banner.description {
                    Text(description)
                        .font(.appTextSmall)
                        .opacity(0.8)
                        .frame(maxWidth: .infinity, alignment: alignment(for: banner.position))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(textAlignment(for: banner.position))
            .padding([.leading, .trailing], sidePadding(for: banner.position))
            .padding(.bottom, bottomPadding(for: banner.position))
            .padding(.top, topPadding(for: banner.position))
            
            actions(banner: banner)
        }
        .foregroundColor(.textMain)
        .frame(maxWidth: .infinity)
        .background(
            // We layer on and offset an additional
            // layer to cover any gaps that may result
            // from spring animations that overshoot
            // the final Y position.
            GeometryReader { geometry in
                banner.style.backgroundColor
                    .zIndex(2)
                    .if(banner.position == .bottom) { $0
                        .clipShape(
                            CustomRoundedRectangle(radius: Metrics.buttonRadius, corners: [.topLeft, .topRight])
                        )
                    }
                banner.style.backgroundColor
                    .frame(height: 10_000)
                    .position(x: geometry.size.width * 0.5, y: yOffset(for: banner.position))
                    .zIndex(1)
            }
        )
        .fixedSize(horizontal: false, vertical: true)
    }
    
    @ViewBuilder private func actions(banner: Banner) -> some View {
        if !banner.actions.isEmpty {
            containerFor(style: banner.actionStyle, position: banner.position, useSubtleActionPadding: banner.actions.last?.style == .subtle) {
                ForEach(banner.actions, id: \.title) { action in
                    let currentAction = action.appending {
                        banner.dismissAction?()
                    }
                    
                    if currentAction.title == banner.actions.last?.title {
                        button(position: banner.position, action: currentAction)
                    } else {
                        switch banner.actionStyle {
                        case .inline:
                            button(position: banner.position, action: currentAction)
                                .condition(banner.usesActionSeparators) { $0
                                    .hSeparator(color: banner.style.separatorColor, position: .trailing)
                                }
                            
                        case .stacked:
                            button(position: banner.position, action: currentAction)
                                .condition(banner.usesActionSeparators) { $0
                                    .vSeparator(color: banner.style.separatorColor, position: .bottom)
                                }
                        }
                    }
                }
            }
            .condition(banner.usesActionSeparators) { $0
                .vSeparator(color: banner.style.separatorColor, position: [.top, .bottom])
            }
        }
    }
    
    @ViewBuilder private func containerFor<T>(style: Banner.ActionStyle, position: Banner.Position, useSubtleActionPadding: Bool, @ViewBuilder builder: () -> T) -> some View where T: View {
        switch style {
        case .inline:
            HStack(spacing: 0) {
                builder()
            }
        case .stacked:
            switch position {
            case .top:
                VStack(spacing: 0) {
                    builder()
                }
                
            case .bottom:
                VStack(spacing: 15) {
                    builder()
                }
                .padding([.leading, .trailing], 20)
                .padding(.bottom, useSubtleActionPadding ? 0 : 15)
            }
        }
    }
    
    @ViewBuilder private func button(position: Banner.Position, action: Banner.Action) -> some View {
        switch position {
        case .top:
            Button(action: action.action) {
                Text(action.title)
            }
            .buttonStyle(SquarePlainStyle())
            
        case .bottom:
            Button(action: action.action) {
                Text(action.title)
            }
            .buttonStyle(RoundTranslucentStyle(style: action.style))
        }
    }
    
    // MARK: - Metrics -
    
    private func animation() -> Animation {
        if let banner = banner {
            switch banner.position {
            case .top:
                return .spring(dampingFraction: 0.55).speed(1.8)
            case .bottom:
                return .spring(dampingFraction: 0.65).speed(2.0)
            }
        } else {
            return .easeInOut(duration: 0.15)
        }
    }
    
    func titleSpacing(for position: Banner.Position) -> CGFloat {
        switch position {
        case .top:
            return 10
        case .bottom:
            return 15
        }
    }
    
    func alignment(for position: Banner.Position) -> Alignment {
        switch position {
        case .top:
            return .leading
        case .bottom:
            return .leading
        }
    }
    
    func textAlignment(for position: Banner.Position) -> TextAlignment {
        switch position {
        case .top:
            return .leading
        case .bottom:
            return .leading
        }
    }
    
    func topPadding(for position: Banner.Position) -> CGFloat {
        switch position {
        case .top:
            return 10
        case .bottom:
            return 25
        }
    }
    
    func bottomPadding(for position: Banner.Position) -> CGFloat {
        switch position {
        case .top:
            return 20
        case .bottom:
            return 20
        }
    }
    
    func sidePadding(for position: Banner.Position) -> CGFloat {
        switch position {
        case .top:
            return 20
        case .bottom:
            return 20
        }
    }
    
    func yOffset(for position: Banner.Position) -> CGFloat {
        switch position {
        case .top:
            return -5_000
        case .bottom:
            return 5_000
        }
    }
    
    func containerAlignment(for position: Banner.Position) -> Alignment {
        switch position {
        case .top:
            return .top
        case .bottom:
            return .bottom
        }
    }
    
    func transition(for position: Banner.Position, geometry: GeometryProxy) -> AnyTransition {
        switch position {
        case .top:
            return .move(edge: .top)
                .combined(with: .offset(x: 0, y: -geometry.safeAreaInsets.top - 10.0))
        case .bottom:
            return .move(edge: .bottom)
                .combined(with: .offset(x: 0, y: geometry.safeAreaInsets.bottom + 10.0))
        }
    }
}

extension View {
    @ViewBuilder func condition<Content>(_ condition: @autoclosure () -> Bool, content: (Self) -> Content) -> some View where Content: View {
            if condition() {
                content(self)
            } else {
                self
            }
        }
}

// MARK: - CustomRoundedRectangle -

private struct CustomRoundedRectangle: Shape {

    var radius: CGFloat
    var corners: UIRectCorner

    func path(in rect: CGRect) -> Path {
        Path(
            UIBezierPath(
                roundedRect: rect,
                byRoundingCorners: corners,
                cornerRadii: CGSize(width: radius, height: radius)
            ).cgPath
        )
    }
}

// MARK: - Styles -

private extension BannerModifier {
    struct SquarePlainStyle: ButtonStyle {
        
        func makeBody(configuration: Configuration) -> some View {
            Rectangle()
                .fill(Color.clear)
                .frame(height: 50)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .overlay(
                    configuration.label
                        .font(.appTextMedium)
                )
                .background(
                    VStack {
                        if configuration.isPressed {
                            Color.black.opacity(0.1)
                        } else {
                            Color.clear
                        }
                    }
                    .animation(nil, value: !configuration.isPressed)
                )
        }
    }
}

private extension BannerModifier {
    struct RoundTranslucentStyle: ButtonStyle {
        
        var style: Banner.Action.Style
        
        func makeBody(configuration: Configuration) -> some View {
            Rectangle()
                .fill(Color.clear)
                .frame(height: Metrics.buttonHeight)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .overlay(
                    configuration.label
                        .font(.appTextMedium)
                        .foregroundColor(fontColor(for: configuration))
                        .padding(Metrics.buttonPadding)
                        .frame(height: Metrics.buttonHeight)
                )
                .background(
                    VStack {
                        buttonColor(for: configuration)
                            .clipShape(
                                RoundedRectangle(cornerRadius: Metrics.buttonRadius)
                            )
                    }
                    .animation(nil, value: !configuration.isPressed)
                )
        }
        
        private func buttonColor(for configuration: Configuration) -> Color {
            switch style {
            case .standard:
                if configuration.isPressed {
                    return .white.opacity(0.25)
                } else {
                    return .white.opacity(0.15)
                }
                
            case .prominent, .destructive:
                if configuration.isPressed {
                    return .white.opacity(0.5)
                } else {
                    return .white
                }
                
            case .subtle:
                if configuration.isPressed {
                    return .white.opacity(0.1)
                } else {
                    return .clear
                }
            }
        }
        
        private func fontColor(for configuration: Configuration) -> Color {
            switch style {
            case .standard:
                if configuration.isPressed {
                    return .textMain
                } else {
                    return .textMain
                }
                
            case .prominent:
                if configuration.isPressed {
                    return .black.opacity(0.5)
                } else {
                    return .black
                }
                
            case .destructive:
                if configuration.isPressed {
                    return .bannerError.opacity(0.5)
                } else {
                    return .bannerError
                }
                
            case .subtle:
                if configuration.isPressed {
                    return .white.opacity(1.0)
                } else {
                    return .white.opacity(0.75)
                }
            }
        }
    }
}

// MARK: - Previews -

struct BannerModifier_Previews: PreviewProvider {
    
    private static let banners: [Banner] = [
        Banner(
            style: .notification,
            title: "Error 1",
            description: "Something went wrong, please try again."
        ),
        Banner(
            style: .warning,
            title: "Error 2",
            description: "Something went wrong again, please try again."
        ),
        Banner(
            style: .notification,
            title: "Error 3",
            description: "Something went wrong, please try again.",
            actions: [
                .cancel(title: "Dismiss"),
                .standard(title: "Try a Thing", action: {}),
            ]
        ),
        Banner(
            style: .error,
            title: "Error 4",
            description: "Something went wrong, please try again.",
            actions: [
                .cancel(title: "Dismiss"),
                .standard(title: "Try a Thing", action: {}),
                .standard(title: "Another Thing", action: {}),
            ]
        ),
        Banner(
            style: .error,
            title: "Not a Code Account",
            description: "Only accounts created through Code are supported.",
            position: .bottom,
            actionStyle: .stacked,
            actions: [
                .destructive(title: "Delete Forever", action: {}),
                .cancel(title: "Cancel"),
            ]
        ),
    ]
    
    static var previews: some View {
        Group {
            ForEach(banners, id: \.title) { banner in
                Background(color: .white) {
                    Text("There's something big here")
                        .font(.appTextLarge)
                        .foregroundColor(.textMain)
                        .padding(20)
                }
                .banner(banner)
//                .previewLayout(.fixed(width: 380, height: 300))
                .previewDevice(PreviewDevice(rawValue: "iPhone SE (3rd generation)"))
//                .previewDevice(PreviewDevice(rawValue: "iPhone 12 Pro"))
            }
        }
    }
}
