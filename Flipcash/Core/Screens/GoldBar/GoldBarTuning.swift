import Foundation

/// The bar's adjustable look. `standard` is the tuned production look and the
/// demo sliders' starting values.
struct GoldBarTuning: Equatable {
    var lightIntensity: Double
    var environmentIntensity: Double
    var relief: Double
    /// Rest position of the key light (x lateral, y elevation).
    var lightAnchor: SIMD2<Double>
    /// Base bar rotation in degrees: x turns left/right, y tilts up/down;
    /// device motion adds a slight lean on top of this.
    var barRotationDegrees: SIMD2<Double>

    static let standard = GoldBarTuning(
        lightIntensity: 1034,
        environmentIntensity: 3.73,
        relief: 2.0,
        lightAnchor: SIMD2(0, 0.36),
        barRotationDegrees: SIMD2(0, 0)
    )
}
