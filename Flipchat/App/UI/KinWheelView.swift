//
//  KinWheelView.swift
//  Code
//
//  Created by Dima Bart on 2025-01-21.
//

import SwiftUI

struct KinWheelView: View {
    
    @Binding private var selection: Int
    
    private let max: Int
    
    fileprivate let width: CGFloat
    
    init(selection: Binding<Int>, max: Int, width: CGFloat = 200) {
        self._selection = selection
        self.max = max
        self.width = width
    }
    
    var body: some View {
        HStack(spacing: 0) {
            Text(String.unicodeHex)
                .font(.system(size: 50))
                .padding(.bottom, 8)
                .padding(.leading, 20)
                .foregroundStyle(.white)
            
            KinWheelPicker(
                selection: $selection,
                max: max,
                width: width
            )
            .frame(width: width)
        }
    }
}

struct KinWheelPicker: UIViewRepresentable {
    
    @Binding var selection: Int
    
    private let items: [String]
    private let max: Int
    
    fileprivate let width: CGFloat
    
    init(selection: Binding<Int>, max: Int, width: CGFloat) {
        self._selection = selection
        self.max = max
        self.width = width
        self.items = (0...max).map { "\($0)" }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UIPickerView {
        let picker = UIPickerView()
        picker.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        
        picker.dataSource = context.coordinator
        picker.delegate = context.coordinator

        return picker
    }

    func updateUIView(_ uiView: UIPickerView, context: Context) {
        uiView.selectRow(selection, inComponent: 0, animated: false)
        uiView.reloadAllComponents()
    }

    class Coordinator: NSObject, UIPickerViewDataSource, UIPickerViewDelegate {
        
        let parent: KinWheelPicker

        init(_ parent: KinWheelPicker) {
            self.parent = parent
        }

        func numberOfComponents(in pickerView: UIPickerView) -> Int {
            1
        }

        func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
            parent.items.count
        }

        func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
            "\(parent.items[row]) Kin"
        }

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            parent.selection = row
        }
        
        func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat {
            return 50
        }
        
        func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {
            var targetView = view
                
            let margins: CGFloat = 20 // Native picker view margins
            let padding: CGFloat = 10
            let labelTag = 987
            
            let labelFrame: CGRect = .init(x: padding, y: 0, width: parent.width - (padding * 2) - margins, height: 50)
            let outerFrame: CGRect = .init(x: 0, y: 0, width: parent.width - margins, height: 50)
            
            let text = pickerView.delegate?.pickerView?(pickerView, titleForRow: row, forComponent: component) ?? ""
            if targetView == nil {
                
                let label = UILabel()
                label.frame = labelFrame
                label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                label.baselineAdjustment = .alignCenters
                label.numberOfLines = 1
                label.textAlignment = .left
                label.font = .systemFont(ofSize: 40)
                label.text = text
                label.textColor = .white
                label.tag = labelTag
                
                let container = UIView(frame: outerFrame)
                container.addSubview(label)
                
                targetView = container
                
            } else if let label = targetView?.viewWithTag(labelTag) as? UILabel {
                targetView?.frame = outerFrame
                label.frame = labelFrame
                label.text = text
            }
            
            return targetView!
        }
    }
}
