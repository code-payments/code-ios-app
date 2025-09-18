//
//  OnrampViewModel.swift
//  Code
//
//  Created by Dima Bart on 2025-08-11.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

@MainActor
class OnrampViewModel: ObservableObject {
    
    @Published var isOnrampPresented: Bool = false
    
    @Published var isShowingVerificationFlow: Bool = false {
        didSet {
            UIApplication.isInterfaceResetDisabled = isShowingVerificationFlow
            print("[Onramp] UI Reset: \(isShowingVerificationFlow ? "disabled" : "enabled")")
        }
    }
    
    @Published var isShowingAmountEntryScreen: Bool = false
    
    @Published var onrampPath: [OnrampPath] = [] {
        didSet {
            if onrampPath.isEmpty && !oldValue.isEmpty {
                reset()
            }
        }
    }
    
    @Published var emailVerificationDescription: VerificationDescription? {
        didSet {
            if emailVerificationDescription == nil {
                reset()
            }
        }
    }
    
    @Published var coinbaseOrder: OnrampOrderResponse?
    
    @Published var dialogItem: DialogItem?
    
    @Published var purchaseSuccess: DialogItem?
    
    @Published var enteredCode: String = ""
    @Published var enteredEmail: String = ""
    @Published var enteredAmount: String = ""
    
    @Published var selectedPreset: Int? {
        didSet {
            if selectedPreset != nil {
                enteredAmount = ""
            }
        }
    }
    
    @Published private(set) var isResending: Bool = false

    @Published private(set) var region: Region
    @Published private(set) var enteredPhone: String = ""
    
    @Published var payButtonState: ButtonState = .normal
    @Published private(set) var sendCodeButtonState: ButtonState = .normal
    @Published private(set) var sendEmailCodeState: ButtonState = .normal
    @Published private(set) var confirmCodeButtonState: ButtonState = .normal
    @Published private(set) var confirmEmailButtonState: ButtonState = .normal
    
    let codeLength = 6
    
    var enteredFiat: ExchangedFiat? {
        var amount: String = ""
        
        if !enteredAmount.isEmpty {
            amount = enteredAmount
        } else if let selectedPreset {
            amount = "\(selectedPreset)"
        }
        
        guard let amount = NumberFormatter.decimal(from: amount) else {
//            trace(.failure, components: "[Onramp] Failed to parse amount string: \(amount)")
            return nil
        }
        
        let currency = ratesController.entryCurrency
        
        guard let rate = ratesController.rate(for: currency) else {
            trace(.failure, components: "[Onramp] Rate not found for: \(currency)")
            return nil
        }
        
        guard let converted = try? Fiat(fiatDecimal: amount, currencyCode: currency) else {
            trace(.failure, components: "[Onramp] Invalid amount for entry")
            return nil
        }
        
        return try! ExchangedFiat(converted: converted, rate: rate)
    }
    
    var regionFlagStyle: Flag.Style {
        .fiat(region)
    }
    
    var countryCode: String {
        "+\(phoneFormatter.countryCode(for: region)!)"
    }
    
    var phone: Phone? {
        Phone(enteredPhone)
    }
    
    var canSendVerificationCode: Bool {
        phone != nil
    }
    
    var canSendEmailVerification: Bool {
        isEmailValid
    }
    
    var isCodeComplete: Bool {
        enteredCode.count >= codeLength
    }
    
    var isEmailValid: Bool {
        let e = enteredEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !e.isEmpty, e.utf8.count <= 254 else {
            return false
        }
        
        return e.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil
    }
    
    var hasSelectedAmount: Bool {
        selectedPreset != nil || enteredFiat != nil
    }
    
    private let container: Container
    private let session: Session
    private let ratesController: RatesController
    private let flipClient: FlipClient
    private let owner: KeyPair
    
    private lazy var coinbase = Coinbase(configuration: .init(bearerTokenProvider: fetchCoinbaseJWT))
    
    private let phoneFormatter = PhoneFormatter()
    
    private var hasResetIdentity: Bool = false
    
    private var isPhoneVerified: Bool {
        session.profile?.isPhoneVerified ?? false
    }
    
    private var isEmailVerified: Bool {
        session.profile?.isEmailVerified ?? false
    }
    
    private var isAccountVerified: Bool {
        isPhoneVerified && isEmailVerified
    }
    
    // MARK: - Init -
    
    init(container: Container, session: Session, ratesController: RatesController) {
        self.container = container
        self.session = session
        self.ratesController = ratesController
        self.owner = session.ownerKeyPair
        self.flipClient = container.flipClient
        
        _region = Published(initialValue: phoneFormatter.currentRegion)
    }
    
    // MARK: - Setters -
    
    private func reset() {
        enteredPhone  = ""
        enteredCode   = ""
        enteredEmail  = ""
        enteredAmount = ""
        
        isResending = false
        
        coinbaseOrder = nil
        selectedPreset = nil
        
        navigateToRoot()
    }
    
    func setRegion(_ region: Region) {
        self.region = region
    }
    
    // MARK: - Bindings -
    
    var adjustingPhoneNumberBinding: Binding<String> {
        Binding { [weak self] in
            guard let self = self else { return "" }
            return self.enteredPhone
            
        } set: { [weak self] newValue in
            guard let self = self else { return }
            let cleanPhoneNumber = newValue.filter { character in
                CharacterSet.numbers.contains(character.unicodeScalars.first!)
            }
            
            let countryCode = self.phoneFormatter.countryCode(for: self.region)!
            self.enteredPhone = self.phoneFormatter.format("+\(countryCode)\(cleanPhoneNumber)")
        }
    }
    
    var adjustingCodeBinding: Binding<String> {
        Binding { [weak self] in
            guard let self = self else { return "" }
            return self.enteredCode
            
        } set: { [weak self] newValue in
            guard let self = self else { return }
            
            if newValue.count > self.codeLength {
                self.enteredCode = String(newValue.prefix(self.codeLength))
            } else {
                self.enteredCode = newValue
            }
        }
    }
    
    var adjustingSelectedPreset: Binding<GridAmounts.SelectedAction?> {
        Binding { [weak self] in
            guard let preset = self?.selectedPreset else { return nil }
            return .amount(preset)
            
        } set: { [weak self] newValue in
            guard let self = self else { return }
            switch newValue {
            case .amount(let amount):
                self.selectedPreset = amount
            case .more:
                break
            case .none:
                break
            }
        }
    }
    
    // MARK: - Root -
    
    func applePayWebView() -> AnyView {
        if let order = coinbaseOrder {
            AnyView(
                ApplePayWebView(url: order.paymentLink.url) { [weak self] event in
                    self?.didReceiveApplePayEvent(event: event)
                }
                .frame(width: 300, height: 300)
                .opacity(0)
                .id(order.id)
            )
        } else {
            AnyView(EmptyView())
        }
    }
    
    // MARK: - Navigation -
    
    func presentRoot() {
        reset()
        isOnrampPresented = true
    }
    
    func navigateToRoot() {
        onrampPath = []
    }
    
    func navigateToInitialVerification() {
        navigateToAmount(from: .info)
    }
    
    private func navigateToAmount(from origin: Origin) {
        if origin.rawValue < Origin.info.rawValue, (!isPhoneVerified || !isEmailVerified) {
            onrampPath.append(.info)
            return
        }
        
        if origin.rawValue < Origin.phone.rawValue, !isPhoneVerified {
            onrampPath.append(.enterPhoneNumber)
            return
        }
        
        if origin.rawValue < Origin.email.rawValue, !isEmailVerified {
            onrampPath.append(.enterEmail)
            return
        }
        
        navigateToVerificationOrPurchase()
    }
    
    private func navigateToVerificationOrPurchase() {
        // If we need to verify the phone or
        // email, we'll need to open up the
        // verification flow, otherwise, we
        // can jump straight to the purchase
        if isAccountVerified {
            isShowingVerificationFlow = false
            createOrder()
        } else {
            isShowingVerificationFlow = true
        }
    }
    
    private func resetIdentityAndVerify() -> Bool {
        guard !hasResetIdentity else {
            return false
        }
        
        hasResetIdentity = true
        
        Task {
            try await session.unlinkProfile()
            navigateToVerificationOrPurchase()
        }
        
        return true
    }
    
    // MARK: - Actions -
    
    func addCashWithDebitCardAction() {
        reset()
        navigateToAmount(from: .root)
    }
    
    func addWithApplePayAction() {
        let selectedPreset  = selectedPreset
        let enteredAmount   = enteredAmount
        reset()
        self.selectedPreset = selectedPreset
        self.enteredAmount  = enteredAmount
        
        navigateToVerificationOrPurchase()
    }
    
    func customAmountAction() {
        selectedPreset = nil
        isShowingAmountEntryScreen = true
    }
    
    func customAmountEnteredAction() {
        guard let exchangedFiat = enteredFiat else {
            return
        }
        
        guard let limit = session.singleTransactionLimitFor(currency: exchangedFiat.converted.currencyCode) else {
            return
        }
        
        guard exchangedFiat.converted.quarks <= limit.quarks else {
            showAmountTooLargeError()
            return
        }
        
        isShowingAmountEntryScreen = false
        
        Task {
            addWithApplePayAction()
        }
    }
    
    func sendPhoneNumberCodeAction() {
        guard let phone else {
            return
        }
        
        Task {
            sendCodeButtonState = .loading
            defer {
                sendCodeButtonState = .normal
            }
            
            do {
                try await flipClient.sendVerificationCode(
                    phone: phone.e164,
                    owner: owner
                )
                try await Task.delay(milliseconds: 500)
                sendCodeButtonState = .success
                
                try await Task.delay(milliseconds: 500)
                onrampPath.append(.confirmPhoneNumberCode)
                
                try await Task.delay(milliseconds: 500)
            }
            
            catch
                ErrorSendVerificationCode.invalidPhoneNumber,
                ErrorSendVerificationCode.unsupportedPhoneType
            {
                showUnsupportedPhoneNumberError()
            }
            
            catch {
                ErrorReporting.captureError(error)
                showGenericError()
            }
        }
    }
    
    func resendCodeAction() async throws {
        guard let phone else {
            return
        }
        
        isResending = true
        defer {
            isResending = false
        }
        
        do {
            try await flipClient.sendVerificationCode(
                phone: phone.e164,
                owner: owner
            )
        } catch {
            ErrorReporting.captureError(error)
        }
    }
    
    func confirmPhoneNumberCodeAction() {
        guard let phone else {
            return
        }
        
        guard isCodeComplete else {
            return
        }
        
        Task {
            confirmCodeButtonState = .loading
            defer {
                confirmCodeButtonState = .normal
            }
            
            do {
                try await flipClient.checkVerificationCode(
                    phone: phone.e164,
                    code: enteredCode,
                    owner: owner
                )
                
                try? await session.updateProfile()
                
                try await Task.delay(milliseconds: 500)
                confirmCodeButtonState = .success
                
                try await Task.delay(milliseconds: 500)
                navigateToAmount(from: .phone)
                
                try await Task.delay(milliseconds: 500)
            }
            
            catch ErrorCheckVerificationCode.invalidCode {
                showInvalidCodeError()
            }
            
            catch ErrorCheckVerificationCode.noVerification {
                showGenericError()
            }
            
            catch {
                ErrorReporting.captureError(error)
            }
        }
    }
    
    func sendEmailCodeAction() {
        guard isEmailValid else {
            return
        }
        
        Task {
            sendEmailCodeState = .loading
            defer {
                sendEmailCodeState = .normal
            }
            
            do {
                try await flipClient.sendEmailVerification(
                    email: enteredEmail,
                    owner: owner
                )
                try await Task.delay(milliseconds: 500)
                sendEmailCodeState = .success
                
                try await Task.delay(milliseconds: 500)
                onrampPath.append(.confirmEmailCode)
                
                try await Task.delay(milliseconds: 500)
            }
            
            catch ErrorSendEmailCode.invalidEmailAddress {
                showInvalidEmailError()
            }
            
            catch {
                ErrorReporting.captureError(error)
                showGenericError()
            }
        }
    }
    
    func resendEmailCodeAction() async throws {
        guard isEmailValid else {
            return
        }
        
        isResending = true
        defer {
            isResending = false
        }
        
        do {
            try await flipClient.sendEmailVerification(
                email: enteredEmail,
                owner: owner
            )
        } catch {
            ErrorReporting.captureError(error)
        }
    }
    
    func confirmEmailFromDeeplinkAction(verification: VerificationDescription) {
        // Check to see if the user is already in the
        // verification flow. If not, we'll skip them
        // over to the email confirmation screen
        if !isShowingVerificationFlow {
            // TODO: Verify this works
            emailVerificationDescription = verification
            onrampPath = [.confirmEmailCode]
            enteredEmail = verification.email
        }
        
        Task {
            confirmEmailButtonState = .loading
            defer {
                confirmEmailButtonState = .normal
            }
            
            do {
//                try await Task.delay(milliseconds: 500)
                if !isEmailVerified {
                    try await flipClient.checkEmailCode(
                        email: verification.email,
                        code: verification.code,
                        owner: owner
                    )
                    
                    try? await session.updateProfile()
                }
                
                try await Task.delay(milliseconds: 500)
                confirmEmailButtonState = .success
                
                try await Task.delay(milliseconds: 500)
                navigateToAmount(from: .email)
                
                try await Task.delay(milliseconds: 500)
            }
            
            catch ErrorCheckEmailCode.invalidCode {
                showInvalidVerificationLinkError { [weak self] in
                    Task {
                        try await self?.resendEmailCodeAction()
                    }
                } cancel: { [weak self] in
                    self?.emailVerificationDescription = nil
                }
            }
            
            catch ErrorCheckEmailCode.noVerification {
                showExpiredVerificationLinkError { [weak self] in
                    Task {
                        try await self?.resendEmailCodeAction()
                    }
                } cancel: { [weak self] in
                    self?.emailVerificationDescription = nil
                }
            }
            
            catch {
                ErrorReporting.captureError(error)
                showGenericError()
            }
        }
    }
    
    // MARK: - Coinbase -
    
    private func createOrder() {
        guard let exchangedFiat = enteredFiat else {
            return
        }
        
        guard let profile = session.profile, profile.canCreateCoinbaseOrder else {
            return
        }
        
        Task {
            try await createOnrampOrder(
                profile: profile,
                exchangedFiat: exchangedFiat
            )
        }
    }
    
    private func createOnrampOrder(profile: Profile, exchangedFiat: ExchangedFiat) async throws {
        let id       = UUID()
        let email    = profile.email!
        let phone    = profile.phone!.e164
        let userRef  = "\(email):\(phone)"
        let orderRef = "\(userRef):\(id)"
        
        payButtonState = .loading
        
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        
        let ref = BetaFlags.shared.hasEnabled(.coinbaseSandbox) ? "sandbox-\(userRef)" : userRef
        
        do {
            let response = try await coinbase.createOrder(request: .init(
                paymentAmount: nil,
                paymentCurrency: "USD",
                purchaseAmount: f.string(from: exchangedFiat.converted.decimalValue),
                purchaseCurrency: "USDC",
                isQuote: false,
                destinationAddress: session.owner.depositPublicKey,
                email: email,
                phoneNumber: phone,
                partnerOrderRef: orderRef,
                partnerUserRef: ref,
                phoneNumberVerifiedAt: .now,
                agreementAcceptedAt: .now
            ))
            
            coinbaseOrder = response
        }
        
        catch let error as OnrampErrorResponse {
            if error.errorType == .guestRegionForbidden {
                let resetStarted = resetIdentityAndVerify()
                // In the event that reset identity has been
                // ignored (ie. the reset already happened, etc)
                // we'll want to show the error
                if !resetStarted {
                    showCoinbaseError(
                        title: error.title,
                        subtitle: error.subtitle
                    )
                }
            } else if error.errorType != .unknown {
                showCoinbaseError(
                    title: error.title,
                    subtitle: error.subtitle
                )
            }
            
            ErrorReporting.captureError(error)
            payButtonState = .normal
        }
        
        catch {
            ErrorReporting.captureError(error)
            payButtonState = .normal
        }
    }
    
    private func didReceiveApplePayEvent(event: ApplePayEvent) {
        trace(.warning, components: "[Coinbase]: \(event.event?.rawValue ?? "unknown")")
        
        func handleEventError(_ event: ApplePayEvent) {
            payButtonState = .normal
            coinbaseOrder = nil
            
            showGenericError() { [weak self] in
                self?.isOnrampPresented = false
            }
            
            ErrorReporting.captureError(event.event!)
        }
        
        switch event.event {
        case .loadPending:
            break
        case .loadSuccess:
            break
        case .loadError:
            handleEventError(event)
            
        case .commitSuccess:
            break
        case .commitError:
            handleEventError(event)
        case .pollingStart:
            break
        case .pollingSuccess:
            Task {
                try await Task.delay(milliseconds: 2000)
                coinbaseOrder = nil
                payButtonState = .success
                try await Task.delay(milliseconds: 500)
                isOnrampPresented = false
                try await Task.delay(milliseconds: 650)
                
                let status = await PushController.fetchStatus()
                
                payButtonState = .normal
                purchaseSuccess = .init(
                    style: .success,
                    title: "Your Cash Will Be Available Soon",
                    subtitle: "It should be available in a few minutes. If you have any issues please contact support@flipcash.com",
                    dismissable: true,
                ) {
                    if status == .notDetermined {
                        .standard("Notify Me") { [weak self] in
                            self?.isOnrampPresented = false
                            Task {
                                do {
                                    try await PushController.authorizeAndRegister()
                                } catch {}
                            }
                        };
                        .dismiss(kind: .subtle) { [weak self] in
                            self?.isOnrampPresented = false
                        }
                    } else {
                        .okay(kind: .standard, options: .priorityAction) { [weak self] in
                            self?.isOnrampPresented = false
                        }
                    }
                }
            }
        case .pollingError:
            handleEventError(event)
        case .cancelled:
            coinbaseOrder = nil
            payButtonState = .normal
        case .none:
            break
        }
    }
    
    private func fetchCoinbaseJWT() async throws -> String {
        let coinbaseApiKey = try! InfoPlist.value(for: "coinbase").value(for: "apiKey").string()
        
        return try await flipClient.fetchCoinbaseOnrampJWT(
            apiKey: coinbaseApiKey,
            owner: owner
        )
    }
    
    // MARK: - Clipboard -
    
    func pasteCodeFromClipboardIfPossible() {
        guard let code = codeFromClipboard() else {
            return
        }
        
        enteredCode = code
    }
    
    private func codeFromClipboard() -> String? {
        if let codeString = UIPasteboard.general.string, codeString.count == codeLength {
            let digits: [Int] = codeString.utf8.compactMap { char in
                let digit = Int(char)
                if digit >= 48 && digit <= 57 {
                    return digit
                }
                return nil
            }
            
            if digits.count == codeLength {
                return codeString
            }
        }
        return nil
    }
    
    // MARK: - Errors -
    
    private func showCoinbaseError(title: String, subtitle: String) {
        dialogItem = .init(
            style: .destructive,
            title: title,
            subtitle: subtitle,
            dismissable: true,
        ) {
            .okay(kind: .destructive)
        }
    }
    
//    private func showPurchaseSuccessful() {
//        dialogItem = .init(
//            style: .success,
//            title: "Success! Your Cash Is On Its Way",
//            subtitle: "It should be available in a few minutes. If you have any issues please contact support@flipcash.com",
//            dismissable: true,
//        ) {
//            .okay(kind: .standard, options: .priorityAction) { [weak self] in
//                self?.isOnrampPresented = false
//            }
//        }
//    }
    
    private func showGenericError(action: @escaping DialogAction.DialogActionHandler = {}) {
        dialogItem = .init(
            style: .destructive,
            title: "Something Went Wrong",
            subtitle: "Please try again later",
            dismissable: true,
        ) {
            .okay(kind: .destructive, action: action)
        }
    }
    
    private func showAmountTooLargeError() {
        dialogItem = .init(
            style: .destructive,
            title: "Amount Too Large",
            subtitle: "Please enter a smaller amount",
            dismissable: true,
        ) {
            .okay(kind: .destructive)
        }
    }
    
    private func showUnsupportedPhoneNumberError() {
        dialogItem = .init(
            style: .destructive,
            title: "Unsupported Phone Number",
            subtitle: "Please use a different phone number and try again",
            dismissable: true,
        ) {
            .okay(kind: .destructive)
        }
    }
    
    private func showInvalidEmailError() {
        dialogItem = .init(
            style: .destructive,
            title: "Invalid Email",
            subtitle: "Please enter a different email and try again",
            dismissable: true,
        ) {
            .okay(kind: .destructive)
        }
    }
    
    private func showInvalidCodeError() {
        dialogItem = .init(
            style: .destructive,
            title: "Invalid Code",
            subtitle: "Please enter the verification code that was sent to your phone number or request a new code",
            dismissable: true,
        ) {
            .okay(kind: .destructive)
        }
    }
    
    private func showInvalidVerificationLinkError(resendAction: @escaping () -> Void, cancel: @escaping () -> Void) {
        dialogItem = .init(
            style: .destructive,
            title: "Verification Link Invalid",
            subtitle: "This verification link is invalid. Please try again",
            dismissable: true,
        ) {
            .destructive("Resend Verification Code") {
                resendAction()
            };
            .cancel {
                cancel()
            }
        }
    }
    
    private func showExpiredVerificationLinkError(resendAction: @escaping () -> Void, cancel: @escaping () -> Void) {
        dialogItem = .init(
            style: .destructive,
            title: "Verification Link Expired",
            subtitle: "This verification link has expired. Please try again",
            dismissable: true,
        ) {
            .destructive("Resend Verification Code") {
                resendAction()
            };
            .cancel {
                cancel()
            }
        }
    }
}

// MARK: - Path -

enum OnrampPath {
    case info
    case enterPhoneNumber
    case confirmPhoneNumberCode
    case enterEmail
    case confirmEmailCode
    case enterAmount
    case success
}

private enum Origin: Int {
    case root
    case info
    case phone
    case email
    case payment
}

// MARK: - Profile -

extension Profile {
    var canCreateCoinbaseOrder: Bool {
        phone != nil && email?.isEmpty == false
    }
}

// MARK: - CharacterSet -

private extension CharacterSet {
    static let numbers: CharacterSet = CharacterSet(charactersIn: "0123456789")
}

// MARK: - Mock -

extension OnrampViewModel {
    static let mock: OnrampViewModel = .init(
        container: .mock,
        session: .mock,
        ratesController: .mock
    )
}
