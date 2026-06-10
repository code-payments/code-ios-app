import SwiftUI
import FlipcashUI

/// Renders the bill's circular Kik code (`CodeView`) into a bitmap the material baker
/// etches into the bar face. `ImageRenderer` is main-actor-bound; the resulting image
/// is immutable and feeds the off-main bake.
enum GoldBarCodeRenderer {

    /// Dark code on a transparent background; the logo center is punched out so the
    /// gold shows through it.
    static func image(for data: Data, side: CGFloat) -> UIImage {
        let renderer = ImageRenderer(
            content: CodeView(data: data)
                .foregroundStyle(Color(white: 0.06))
                .frame(width: side, height: side)
        )
        renderer.scale = 1
        return renderer.uiImage ?? UIImage()
    }
}
