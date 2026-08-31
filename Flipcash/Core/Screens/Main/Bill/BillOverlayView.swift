//
//  BillOverlayView.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// Renders the cash bill / tipcard (plus the bill designer and the
/// received-cash / send-tip sheets) at the app root, so a presented bill appears
/// over ANY content — mirroring Android's app-root `BillOverlay`. It is driven
/// entirely by the app-scoped `session.billState`, so a cash-link push or deep
/// link that sets a bill while the user is on the Wallet/Chat/Tip Card tab now
/// renders on screen instead of in the buried Scan tab.
///
/// Mounted once by `ContainerScreen`, above both the v1 scanner root and the v2
/// `HomeTabView`. It is transparent and non-interactive when no bill is present.
struct BillOverlayView: View {

    @Environment(SessionContainer.self) private var sessionContainer

    var body: some View {
        BillOverlayContent(sessionContainer: sessionContainer)
    }
}

private struct BillOverlayContent: View {

    @Environment(AppRouter.self) private var router
    @Environment(BetaFlags.self) private var betaFlags

    @Bindable private var session: Session
    private let sessionContainer: SessionContainer

    /// Primary bill-action button loading state; outlives individual bills.
    @State private var sendButtonState: ButtonState = .normal
    @State private var sendButtonTask: Task<Void, Never>?
    @State private var billDesignerColors: [Color] = ColorEditorControl.randomDerivedColors()
    /// The Send-a-Tip sheet's measured height, used to raise the tipcard clear of it.
    @State private var tipSheetHeight: CGFloat = 0

    init(sessionContainer: SessionContainer) {
        self.sessionContainer = sessionContainer
        self.session          = sessionContainer.session
    }

    var body: some View {
        // The bill surface keeps `.ignoresSafeArea()` on itself, not on this root:
        // as a sibling of the tab NavigationStacks, an overlay whose *root* ignored
        // the safe area would flatten the Liquid Glass of the nav bars beneath it
        // on iOS 26. Nested one level down, the bill still fills the screen while
        // the bars keep their glass. The received-cash / send-tip sheets host here
        // (a `.sheet` modifier adds nothing to the layer tree until it presents).
        ZStack {
            billSurface
        }
        // Reset button state on bill dismissal — `sendButtonState` outlives
        // individual bills.
        .onChange(of: session.billState.bill) { _, newBill in
            guard newBill == nil else { return }
            sendButtonTask?.cancel()
            sendButtonTask = nil
            sendButtonState = .normal
        }
        .sheet(item: $session.valuation) { valuation in
            PartialSheet(background: .clear, canAccessBackground: true) {
                ModalCashReceived(
                    title: "You received",
                    fiat: valuation.exchangedFiat.nativeAmount,
                    currencyName: valuation.mintMetadata?.name ?? "currency",
                    currencyImageURL: valuation.mintMetadata?.imageURL,
                    actionTitle: "Put in Wallet",
                    dismissAction: putInWallet
                )
            }
            .interactiveDismissDisabled()
        }
        // Send a Tip over the scanned tipcard. A swipe-down cancels the whole
        // flow — the card comes down with the sheet.
        .sheet(isPresented: Binding(
            get: { sessionContainer.tipFlow.isSheetPresented },
            set: { isPresented in
                if !isPresented {
                    sessionContainer.tipFlow.cancel()
                }
            }
        )) {
            PartialSheet(
                background: Color(red: 0.1, green: 0.1, blue: 0.1).opacity(0.7),
                canAccessBackground: true
            ) {
                SendTipSheet(tipFlow: sessionContainer.tipFlow)
                    // The sheet content's intrinsic height — the value
                    // `PartialSheet` feeds its `.height` detent, so the sheet's
                    // top sits at `screenHeight` minus this. Measured on the
                    // content (not the detent-driven container, which briefly
                    // fills the screen on present) so the tipcard's clearance is
                    // stable and the card is nudged rather than flung.
                    .background {
                        GeometryReader { proxy in
                            Color.clear
                                .onAppear { tipSheetHeight = proxy.size.height }
                                .onChange(of: proxy.size.height) { _, height in tipSheetHeight = height }
                        }
                    }
            }
        }
    }

    // MARK: - Surface -

    /// A dimmed backdrop is drawn behind a bill/tipcard when it is presented over
    /// a non-scanner surface (a wallet/chat push, a received cash link) so the
    /// underlying screen recedes, matching Android. Over the scanner the camera
    /// stays visible instead — no scrim.
    private var showsScrim: Bool {
        session.isShowingBill && !session.isScannerForeground
    }

    /// How the scrim enters. For an outgoing give, snap it in (`.identity`
    /// insertion) so it masks the amount-entry popping back to the currency info
    /// behind the sliding bill — instead of letting it flash through mid-slide.
    /// A received bill / cash link (presented with `.pop`) keeps the ramp that
    /// arrives with the bill. Both fade out on dismiss.
    private var scrimTransition: AnyTransition {
        presentationStyle == .slide
            ? .asymmetric(insertion: .identity, removal: .opacity)
            : .opacity
    }

    /// The presenting style of the current bill: `.slide` for an outgoing give,
    /// `.pop` for a received bill / cash link or tipcard.
    private var presentationStyle: PresentationState.Style {
        switch session.presentationState {
        case .visible(let style), .hidden(let style): style
        }
    }

    /// The full-screen bill surface. The `BillCanvas` is always mounted (parked
    /// off-screen when idle) so it can drive the slide/pop in and out animations.
    private var billSurface: some View {
        ZStack {
            if showsScrim {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                    .transition(scrimTransition)
            }

            billView()

            if session.billState.bill != nil {
                billActions()
                    .zIndex(1)
                    .transition(.opacity)
            }

            if session.isShowingBillDesigner {
                BillDesignerOverlay(colors: $billDesignerColors)
                    .zIndex(2)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.15), value: session.billState.bill == nil)
        // Governs the scrim's fade-out on dismiss, and its ramp-in everywhere
        // except an outgoing give, which snaps in via `.identity` (see
        // `scrimTransition`) so this doesn't animate its entrance there.
        .animation(.spring(response: 0.6, dampingFraction: 0.6), value: showsScrim)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: session.isShowingBillDesigner)
    }

    // MARK: - Bill -

    @ViewBuilder private func billView() -> some View {
        BillCanvas(
            state: session.presentationState,
            centerOffset: billCenterOffset(),
            preferredCanvasSize: preferredCanvasSize(),
            bill: session.billState.bill,
            dismissHandler: dismissBill
        )
        .allowsHitTesting(session.presentationState.isPresenting)
        .ignoresSafeArea()
    }

    /// The resting vertical offset for a centered cash bill.
    private static let restingBillOffset = CGSize(width: 0, height: -30)

    /// The tipcard rests centered on screen when presented as the scan/deep-link
    /// overlay — and lifts only when the Send a Tip sheet comes up. (Cash bills
    /// sit slightly above center.)
    private static let restingTipcardOffset = CGSize(width: 0, height: 0)

    /// When the Send a Tip sheet is up, the card lifts so its top sits ~25% down
    /// the screen — pushed up clear of the sheet without floating too high above
    /// it, leaving the lower area for the sheet.
    private static let tipcardSheetTopInset: CGFloat = 0.25

    /// Floor gap kept between the card's bottom and the sheet's top, used only if
    /// a taller-than-designed sheet would otherwise crowd the card.
    private static let tipcardSheetGap: CGFloat = 24

    private func billCenterOffset() -> CGSize {
        switch session.billState.bill {
        case .tipcard where sessionContainer.tipFlow.isSheetPresented:
            tipcardSheetOffset()
        case .tipcard:
            Self.restingTipcardOffset
        case .cash, nil:
            Self.restingBillOffset
        }
    }

    private func tipcardSheetOffset() -> CGSize {
        guard tipSheetHeight > 0,
              let screen = UIApplication.shared.firstWindowScene?.screen.bounds else {
            return Self.restingTipcardOffset
        }

        // The card is centered on the full screen (the canvas ignores safe area),
        // so all edges are measured in screen coordinates from the top.
        let cardHeight = BillCanvas.tipcardSize(canvasWidth: preferredCanvasSize().width).height

        // Lift the card to the design's upper placement (card top ~25% down).
        let designOffset = screen.height * Self.tipcardSheetTopInset
            + cardHeight / 2 - screen.height / 2

        // …but rise further if a taller-than-designed sheet would still crowd it.
        let sheetTop = screen.height - tipSheetHeight
        let raised = sheetTop - Self.tipcardSheetGap - cardHeight / 2 - screen.height / 2

        return CGSize(width: 0, height: min(designOffset, raised))
    }

    private func preferredCanvasSize() -> CGSize {
        guard var rect = UIApplication.shared.firstWindowScene?.screen.bounds else {
            return .zero
        }

        rect.size.height -= 70.0 // Bottom bar / tab bar

        return rect.insetBy(dx: 20, dy: 20).size
    }

    // MARK: - Actions -

    @ViewBuilder private func billActions() -> some View {
        VStack {
            Spacer()

            GlassContainer(spacing: 30) {
                billActionButtons
            }
        }
        // The surface ignores the safe area, so lift the buttons clear of the
        // home indicator and up off the very bottom edge.
        .padding(.bottom, 48)
    }

    private var billActionButtons: some View {
        HStack(alignment: .center, spacing: 30) {
            if let primaryAction = session.billState.primaryAction {
                CapsuleButton(
                    state: sendButtonState,
                    asset: primaryAction.asset,
                    title: primaryAction.title
                ) {
                    sendButtonTask?.cancel()
                    sendButtonTask = Task {
                        sendButtonState = .loading
                        do {
                            try await primaryAction.action()
                            try await Task.delay(milliseconds: 1000)
                        } catch {}
                        sendButtonState = .normal
                    }
                }
            }

            if let secondaryAction = session.billState.secondaryAction {
                CapsuleButton(
                    state: .normal,
                    asset: secondaryAction.asset,
                    title: secondaryAction.title
                ) {
                    secondaryAction.action()
                }
                .accessibilityLabel(secondaryAction.title ?? "Cancel")
            }
        }
    }

    /// Takes a grabbed deposit to the wallet: the bill comes down and the wallet
    /// comes forward, where the balance is seen to rise.
    ///
    /// Only a scanned grab arms a deposit, so a claimed cash link takes the
    /// plain dismissal here, as does any receive with
    /// ``BetaFlags/Option/walletDepositArrival`` off. The single gate is here
    /// because everything downstream hangs off the release: an unreleased
    /// deposit is discarded by `dismissCashBill`, and the wallet only plays one
    /// it has been released.
    private func putInWallet() {
        guard betaFlags.hasEnabled(.walletDepositArrival),
              session.walletDeposit.isArmed else {
            session.dismissCashBill(style: .slide)
            return
        }

        // Released before the dismissal, which drops any deposit the user never
        // asked to see.
        session.walletDeposit.release()
        session.dismissCashBill(style: .slide)
        router.showWallet()
    }

    private func dismissBill() {
        switch session.billState.bill {
        case .tipcard:
            sessionContainer.tipFlow.cancel()
        case .cash, nil:
            session.dismissCashBill(style: .slide)
        }
    }
}
