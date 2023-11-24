//
//  QRCode.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

#if canImport(UIKit)

import SwiftUI
import CoreImage.CIFilterBuiltins

public struct QRCode: View {
    
    @Binding public var isBlurred: Bool
    
    public var data: Data
    public var label: String?
    public var padding: CGFloat
    public var codeColor: Color
    public var backgroundColor: Color
    public var labelColor: Color
    public var centerImage: Image?
    public var correctionLevel: CorrectionLevel
    
    public init(isBlurred: Binding<Bool> = .constant(false), string: String, showLabel: Bool = true, padding: CGFloat = 10, codeColor: Color = .black, backgroundColor: Color = .white, labelColor: Color = .black, centerImage: Image? = nil, correctionLevel: CorrectionLevel = .medium) {
        self.init(
            isBlurred: isBlurred,
            data: Data(string.utf8),
            label: showLabel ? string : nil,
            padding: padding,
            codeColor: codeColor,
            backgroundColor: backgroundColor,
            labelColor: labelColor,
            centerImage: centerImage,
            correctionLevel: correctionLevel
        )
    }
    
    public init(isBlurred: Binding<Bool> = .constant(false), data: Data, label: String? = nil, padding: CGFloat = 10, codeColor: Color = .black, backgroundColor: Color = .white, labelColor: Color = .black, centerImage: Image? = nil, correctionLevel: CorrectionLevel = .medium) {
        self._isBlurred = isBlurred
        self.data  = data
        self.label = label
        self.padding = padding
        self.codeColor = codeColor
        self.backgroundColor = backgroundColor
        self.labelColor = labelColor
        self.centerImage = centerImage
        self.correctionLevel = correctionLevel
    }
    
    public var body: some View {
        if let image = code(for: data) {
            VStack(spacing: 0) {
                ZStack {
                    image
                        .resizable()
                        .interpolation(.none)
                        .blur(radius: isBlurred ? 5 : 0)
                    if let image = centerImage {
                        GeometryReader { geometry in
                            ZStack {
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .foregroundColor(.white)
                                    .frame(
                                        width:  geometry.size.width  * 0.25,
                                        height: geometry.size.height * 0.25
                                    )
                                    .padding(6)
                                    .background(
                                        Rectangle()
                                            .fill(backgroundColor)
                                    )
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
                if let label = label {
                    Text(label)
                        .font(.appTextSmall)
                        .foregroundColor(labelColor)
                        .truncationMode(.middle)
                        .lineLimit(1)
                        .padding([.leading, .trailing], 2)
                }
            }
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(backgroundColor)
            )
        }
    }
    
    private func code(for data: Data) -> Image? {
        let context = CIContext()
        
        // CIFilter reference
        // https://developer.apple.com/library/archive/documentation/GraphicsImaging/Reference/CoreImageFilterReference/index.html#//apple_ref/doc/filter/ci/CIQRCodeGenerator
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = correctionLevel.rawValue
        
        guard let output = filter.outputImage else {
            return nil
        }
        
        let colors = [
            "inputColor0": CIColor(color: UIColor(codeColor)),
            "inputColor1": CIColor(color: UIColor(backgroundColor)),
        ]
        
        let adjustedOutput = output.applyingFilter("CIFalseColor", parameters: colors)
        
        guard let qrcode = context.createCGImage(adjustedOutput, from: output.extent) else {
            return nil
        }
        
        return Image(uiImage: UIImage(cgImage: qrcode))
    }
}

extension QRCode {
    public enum CorrectionLevel: String {
        case low      = "L"
        case medium   = "M"
        case quartile = "Q"
        case high     = "H"
    }
}

// MARK: - Previews -

struct QRCode_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            QRCode(string: "1E99423A4ED27608A15A2616A2B0E9E52CED330AC530EDCC32C8FFC6A526AEDD", showLabel: false)
            QRCode(string: "1E99423A4ED27608A15A2616A2B0E9E52CED330AC530EDCC32C8FFC6A526AEDD", showLabel: true)
            QRCode(data: Data([0xFF, 0xDD, 0xEE, 0x77]), label: "This is 4-byte QR code")
        }
        .previewLayout(.fixed(width: 200, height: 200))
    }
}

#endif
