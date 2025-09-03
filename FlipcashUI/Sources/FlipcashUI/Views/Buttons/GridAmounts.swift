//
//  GridAmounts.swift
//  FlipcashUI
//
//  Created by Dima Bart on 2025-09-02.
//

import SwiftUI

public struct GridAmounts: View {
    
    @Binding public var selectedAction: SelectedAction?
    
    public let action: (SelectedAction) -> Void
    
    private let actions: [SelectedAction] = [
        .amount(10),
        .amount(25),
        .amount(50),
        .amount(75),
        .amount(100),
        .more,
    ]
    
    public init(selected: Binding<SelectedAction?>, action: @escaping (SelectedAction) -> Void) {
        self.action = action
        self._selectedAction = selected
    }
    
    public var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                ForEach(0..<3) { index in
                    let action = actions[index]
                    cell(action.label, action: action)
                }
            }
            
            HStack(spacing: 10) {
                ForEach(3..<6) { index in
                    let action = actions[index]
                    cell(action.label, action: action)
                }
            }
        }
        .background(Color.backgroundMain)
    }
    
    @ViewBuilder private func cell(_ text: String, action: SelectedAction) -> some View {
        Button {
            if action.isSelectable {
                selectedAction = action
            }
            self.action(action)
        } label: {
            Text(text)
        }
        .buttonStyle(
            CustomStyle(
                isSelected: selectedAction?.label == text
            )
        )
    }
}

extension GridAmounts {
    public enum SelectedAction: Equatable, Sendable, Hashable {
        case amount(Int)
        case more
        
        var label: String {
            switch self {
            case .amount(let int):
                "$\(int)"
            case .more:
                "..."
            }
        }
        
        var isSelectable: Bool {
            switch self {
            case .amount: return true
            case .more:   return false
            }
        }
    }
}

// MARK: - CustomStyle -

private extension GridAmounts {
    struct CustomStyle: ButtonStyle {
        
        let isSelected: Bool
        
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .frame(height: 70)
                .frame(maxWidth: .infinity)
                .font(.appBarButton)
                .background(background())
                .foregroundColor(textColor())
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(configuration.isPressed ? Color.black.opacity(0.3) : Color.black.opacity(0))
                        .stroke(Color.white, lineWidth: isSelected ? 1 : 0)
                }
                .cornerRadius(6)
        }
        
        @ViewBuilder private func background() -> some View {
            if isSelected {
                Color(r: 55, g: 71, b: 62)
            } else {
                Color(r: 29, g: 46, b: 35)
            }
        }
        
        private func textColor() -> Color {
            .textMain
        }
    }
}
