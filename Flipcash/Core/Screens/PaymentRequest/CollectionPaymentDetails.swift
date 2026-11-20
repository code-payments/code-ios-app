//
//  CollectionPaymentDetails.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// What the pay sheet draws for a collection that conversions fund: the fee line under the amount,
/// the short line over the Add button, and the Payment Details page their ⓘ opens.
nonisolated struct CollectionPaymentSheetContent: Equatable, Sendable {

    struct Line: Equatable, Sendable {
        /// The currency's id, its mint in base58.
        let currency: String
        let name: String
        let amount: String
        let sublabels: [String]
    }

    static let title = "Payment Details"
    static let payHeading = "You’ll Pay"
    static let useHeading = "You’ll Use"

    /// The short state's lines when the balances can't cover the payment without adding Dollars:
    /// "You’re $4.00 Short", "Add $5.00 and Pay $10.00", and the Apple Pay minimum.
    struct TopUp: Equatable, Sendable {
        /// What the button adds, in the request currency's micros.
        let micros: Int64
        let shortBy: String
        let button: String
        let footnote: String
    }

    /// "plus ~$0.02 of conversion fees" or "no conversion fees", from the plan after any top-up
    /// (8.2). `nil` when nothing converts.
    let feeLine: String?

    /// The short state, or nil when the balances cover the payment.
    let topUp: TopUp?

    /// The Request screen's button when no balance funds any of the payment, so tapping it adds
    /// money with Apple Pay and pays with no sheet: "Pay $10.00" when the top-up is the amount
    /// (1.1), else "Add $5.00 and Pay $2.00" over the Apple Pay minimum (2.1).
    struct RequestTopUp: Equatable, Sendable {
        /// What the button adds, in the request currency's micros.
        let micros: Int64
        let title: String
        let footnote: String?
    }

    /// Set when the top-up covers the whole payment; nil when a balance funds any of it, and the
    /// sheet opens as before.
    let requestTopUp: RequestTopUp?

    /// The paying currency's id.
    let payingCurrency: String

    /// "You’ll Pay": the paying currency and the amount.
    let pay: Line

    /// "You’ll Use": a line per leg, in the order the display gives.
    let use: [Line]

    /// "Total": the amounts sold, fees included.
    let total: CollectionFundingDisplay.Row

    /// A pay sheet line that ends in ⓘ and opens Payment Details.
    enum DetailsEntry: Equatable, Sendable {
        /// "plus ~$0.02 of conversion fees" (5.2).
        case feeLine
        /// "You’re $2.04 Short", the only way to 7.3, since 7.2 draws no fee line.
        case shortLine
    }

    /// The lines that open Payment Details, top to bottom; both open the same sheet. Empty when the
    /// payment converts nothing and isn't short.
    var detailsEntries: [DetailsEntry] {
        var entries: [DetailsEntry] = []
        if feeLine != nil { entries.append(.feeLine) }
        if topUp != nil { entries.append(.shortLine) }
        return entries
    }

    init(plan: CollectionFundingPlan, display: CollectionFundingDisplay, currency: CurrencyCode) {
        feeLine = display.modalFee
        let topUp = plan.payableWithoutTopUp ? nil : Self.topUp(plan: plan, currency: currency)
        self.topUp = topUp
        requestTopUp = topUp.flatMap { Self.requestTopUp(plan: plan, topUp: $0, currency: currency) }
        payingCurrency = display.payCurrency
        pay = Line(currency: display.payCurrency, name: display.pay.label, amount: display.pay.amount, sublabels: [])
        use = zip(display.useCurrencies, display.use).map { currency, row in
            Line(currency: currency, name: row.label, amount: row.amount, sublabels: row.sublabels)
        }
        total = display.total
    }

    /// The strings `CollectionFundingDisplay` gives in English, built from its amounts so each
    /// sentence localizes whole. The shortfall rounds up to the minor unit.
    private static func topUp(plan: CollectionFundingPlan, currency: CurrencyCode) -> TopUp {
        let unit = Int64(pow(10.0, Double(6 - currency.maximumFractionDigits)))
        let shortfall = (plan.shortfallMicros + unit - 1) / unit * unit
        let short = CollectionFundingDisplay.amountText(micros: shortfall, currency: currency)
        let added = CollectionFundingDisplay.amountText(micros: plan.topUpMicros, currency: currency)
        let paid = CollectionFundingDisplay.amountText(micros: plan.amountMicros, currency: currency)
        return TopUp(
            micros: plan.topUpMicros,
            shortBy: String(localized: "You’re \(short) Short", comment: "Pay sheet: how much the viewer's balances fall short of a payment"),
            button: String(localized: "Add \(added) and Pay \(paid)", comment: "Pay sheet button: add money with Apple Pay, then pay the request"),
            footnote: String(localized: "The minimum you can add with Apple Pay is $5.", comment: "Pay sheet footnote under the add-and-pay button")
        )
    }

    /// The Request screen's button, when the top-up alone funds the payment. The planner has
    /// already dropped balances under the dust floor, so a dust balance doesn't count.
    private static func requestTopUp(plan: CollectionFundingPlan, topUp: TopUp, currency: CurrencyCode) -> RequestTopUp? {
        guard plan.fundedByTopUpAlone else { return nil }
        guard plan.topUpMicros > plan.amountMicros else {
            let paid = CollectionFundingDisplay.amountText(micros: plan.amountMicros, currency: currency)
            return RequestTopUp(
                micros: plan.topUpMicros,
                title: String(localized: "Pay \(paid)", comment: "Request screen button: add the amount with Apple Pay and pay the request"),
                footnote: nil
            )
        }
        return RequestTopUp(micros: plan.topUpMicros, title: topUp.button, footnote: topUp.footnote)
    }
}

/// What a funded collection's pay sheet shows.
nonisolated enum CollectionPaySheetPage: Equatable, Sendable {
    /// The payee, the amount, the paying currency, and the swipe or Add button (5.2, 7.2).
    case pay
    /// Payment Details, pushed over the pay content inside the same sheet (5.3, 7.3).
    case details
    /// "Finishing Payment" while the payment runs.
    case finishing

    /// `wantsDetails` is set by the fee or short line's ⓘ and cleared by Payment Details' back
    /// chevron. Details show only while a line can open them, and a running payment wins over both.
    init(wantsDetails: Bool, isFinishing: Bool, content: CollectionPaymentSheetContent?) {
        if isFinishing {
            self = .finishing
        } else if wantsDetails, content?.detailsEntries.isEmpty == false {
            self = .details
        } else {
            self = .pay
        }
    }

    /// Where `CollectionPaySheetPager` stands for this page: 0 on the pay content, 1 on Payment Details.
    var pagerProgress: CGFloat {
        switch self {
        case .pay, .finishing: 0
        case .details: 1
        }
    }
}

/// Lays its subviews out as pages, one container width apart, and takes the height of the page
/// `progress` stands on. Animating `progress` slides the pages across and moves the height between
/// theirs in step, so `PartialSheet`, which sizes its detent from its content, resizes with the
/// slide. Every page stays mounted, so one keeps its state while another covers it, and each page's
/// height is known before it slides in.
struct CollectionPaySheetPager: Layout {

    /// The page showing: 0 for the first, 1 for the second, fractions between them mid-slide.
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    /// The height at `progress`, between the heights of the pages either side of it.
    nonisolated static func height(of pageHeights: [CGFloat], at progress: CGFloat) -> CGFloat {
        guard let last = pageHeights.indices.last else { return 0 }
        let position = min(max(progress, 0), CGFloat(last))
        let lower = Int(position.rounded(.down))
        let upper = min(lower + 1, last)
        let fraction = position - CGFloat(lower)
        return pageHeights[lower] + (pageHeights[upper] - pageHeights[lower]) * fraction
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        return CGSize(width: width, height: Self.height(of: heights, at: progress))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let fitted = ProposedViewSize(width: bounds.width, height: nil)
        for (index, page) in subviews.enumerated() {
            page.place(
                at: CGPoint(x: bounds.minX + (CGFloat(index) - progress) * bounds.width, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: page.sizeThatFits(fitted).height)
            )
        }
    }
}

/// Clips `CollectionPaySheetPager`'s sides, so the page off to one side doesn't show. Its top and
/// bottom stay open: Payment Details' list draws into the sheet's bottom inset, as a scroll view
/// that reaches the safe area does, and clipping there cuts off its last line.
nonisolated struct CollectionPaySheetSides: Shape {
    func path(in rect: CGRect) -> Path {
        Path(rect.insetBy(dx: 0, dy: -rect.height))
    }
}

/// A pay sheet line that ends in the info affordance and opens Payment Details when tapped
/// anywhere: the fee line, and the short line in `font`. The ⓘ draws the same on both.
struct CollectionPaymentInfoLine: View {

    let text: String
    var font: Font = .appTextCaption
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(text)
                    .font(font)
                Image.system(.info)
                    .font(.appTextCaption)
            }
            .foregroundStyle(Color.textSecondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(text), Payment Details")
    }
}

/// Payment Details (frames 5.3, 6.5, 9.3): what the payment pays and what it sells to get there.
struct CollectionPaymentDetailsView: View {

    let content: CollectionPaymentSheetContent
    /// The icon for a currency id, when the wallet has one.
    let imageURL: (String) -> URL?
    let onBack: () -> Void

    @State private var linesHeight: CGFloat = 0

    /// The tallest the list grows before it scrolls: a long list (9.3) takes the sheet up to just
    /// below the status bar. The list sizes itself from its lines rather than from the height it's
    /// proposed, so the pager reads this page's height before it slides in.
    private var maxListHeight: CGFloat {
        let window = UIApplication.shared.currentKeyWindow
        let height = window?.bounds.height ?? UIScreen.main.bounds.height
        let insets = window?.safeAreaInsets ?? .zero
        return height - insets.top - Self.topClearance - insets.bottom - Self.headerHeight
    }

    /// Keeps the sheet short of the large detent, which reaches the status bar. PartialSheet asks
    /// for a height detent, and a page taller than the sheet it's given runs off the bottom.
    private static let topClearance: CGFloat = 16
    /// What the page draws above its list: the sheet's 24-point top inset, the back button's row
    /// and the gap under it.
    private static let headerHeight: CGFloat = 24 + 44 + sectionSpacing

    var body: some View {
        VStack(alignment: .leading, spacing: Self.sectionSpacing) {
            HStack(spacing: 12) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.textMain)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")

                Text(CollectionPaymentSheetContent.title)
                    .font(.appTextXL)
                    .foregroundStyle(Color.textMain)
            }

            // Short lists (5.3, 6.5) fit; a long one (9.3) grows the sheet to the cap and scrolls.
            ScrollView {
                lines
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { linesHeight = $0 }
            }
            .frame(height: min(linesHeight, maxListHeight))
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
        }
    }

    // Sizes from frames 5.3 (node 13952:149) and 7.3 (node 14009:364).
    private static let iconSize: CGFloat = 34
    private static let iconSpacing: CGFloat = 12
    /// Between the title and the list, and between the list's sections.
    private static let sectionSpacing: CGFloat = 28
    /// Between a section's heading and its first row, and between rows.
    private static let rowSpacing: CGFloat = 16
    /// The divider and "Total" sit 8 points past the names.
    private static let totalInset: CGFloat = 54

    private var lines: some View {
        VStack(alignment: .leading, spacing: Self.sectionSpacing) {
            section(CollectionPaymentSheetContent.payHeading, lines: [content.pay])
            VStack(alignment: .leading, spacing: Self.rowSpacing) {
                section(CollectionPaymentSheetContent.useHeading, lines: content.use)

                VStack(alignment: .leading, spacing: 14) {
                    Rectangle()
                        .fill(Color.rowSeparator)
                        .frame(height: 1)

                    HStack {
                        Text(content.total.label)
                        Spacer()
                        Text(content.total.amount)
                    }
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textMain)
                    .frame(minHeight: 24)
                }
                .padding(.leading, Self.totalInset)
            }
        }
    }

    private func section(_ heading: String, lines: [CollectionPaymentSheetContent.Line]) -> some View {
        VStack(alignment: .leading, spacing: Self.rowSpacing) {
            Text(heading)
                .font(.appBarButton)
                .foregroundStyle(Color.textMain)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                row(line)
            }
        }
    }

    /// A row with one sublabel or none centres on its height (5.3); one with two lines under the
    /// name hangs from the top (7.3).
    private func row(_ line: CollectionPaymentSheetContent.Line) -> some View {
        let isTall = line.sublabels.count > 1
        let minHeight: CGFloat = switch line.sublabels.count {
        case 0: 40
        case 1: 52
        default: 68
        }
        return HStack(alignment: isTall ? .top : .center, spacing: Self.iconSpacing) {
            TokenIcon(url: imageURL(line.currency), monogramID: line.currency, size: Self.iconSize)
            VStack(alignment: .leading, spacing: 4) {
                Text(line.name)
                    .font(.appTextBody)
                    .foregroundStyle(Color.textMain)
                if !line.sublabels.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(line.sublabels, id: \.self) { sublabel in
                            Text(sublabel)
                                .font(.appTextCaption)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                }
            }
            Spacer()
            Text(line.amount)
                .font(.appTextMedium)
                .foregroundStyle(Color.textMain)
        }
        .frame(minHeight: minHeight, alignment: isTall ? .top : .center)
    }
}
