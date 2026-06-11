import SwiftUI
import FlipcashCore

/// The production gold bar, shown in place of a bill for USDF cash: the amount is
/// stamped where a minted bar carries its weight, the USDF public key is the serial,
/// and the bill's Kik code is etched into the lower band.
struct GoldBarBillView: View {

    let fiat: FiatAmount
    let data: Data
    let canvasSize: CGSize

    var body: some View {
        GoldBarView(key: .usdfBill(fiat: fiat, codeData: data))
            .frame(width: canvasSize.width, height: canvasSize.height)
    }
}
