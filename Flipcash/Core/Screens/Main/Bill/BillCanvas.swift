//
//  BillCanvas.swift
//  Code
//
//  Created by Dima Bart on 2021-02-05.
//

import SwiftUI
import FlipcashUI

struct BillCanvas: UIViewControllerRepresentable {
    
    var state: PresentationState
    var centerOffset: CGSize
    var preferredCanvasSize: CGSize
    var bill: BillState.Bill?
    var action: VoidAction?
    var dismissHandler: VoidAction?
    
    init(state: PresentationState, centerOffset: CGSize = .zero, preferredCanvasSize: CGSize, bill: BillState.Bill?, action: VoidAction? = nil, dismissHandler: VoidAction? = nil) {
        self.state               = state
        self.centerOffset        = centerOffset
        self.preferredCanvasSize = preferredCanvasSize
        self.bill                = bill
        self.action              = action
        self.dismissHandler      = dismissHandler
    }
    
    func makeUIViewController(context: Context) -> UIViewController {
        _BillCanvasController(
            centerOffset: centerOffset,
            presentationState: state,
            preferredCanvasSize: preferredCanvasSize,
            bill: bill
        )
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        if let canvas = uiViewController as? _BillCanvasController {
            canvas.action = action
            canvas.dismissHandler = dismissHandler
            canvas.update(presentationState: state, bill: bill)
        }
    }
}

// MARK: - _BillCanvasController -

private class _BillCanvasController: UIViewController {
    
    var action: VoidAction?
    var dismissHandler: VoidAction?
    
    private var centerOffset: CGSize
    private var presentationState: PresentationState
    private var preferredCanvasSize: CGSize
    private var bill: BillState.Bill?
    private var host: UIHostingController<AnyView>?
    
    private var dragGesture: UIPanGestureRecognizer?
    
    private var animator: UIViewPropertyAnimator?
    
    private var state: State = .center
    private var didAppear = false
    
    private let dragMultiplier: CGFloat = 0.5
    
    // MARK: - Init -
    
    required init?(coder: NSCoder) { fatalError() }
    
    init(centerOffset: CGSize = .zero, presentationState: PresentationState, preferredCanvasSize: CGSize, bill: BillState.Bill?) {
        self.centerOffset        = centerOffset
        self.presentationState   = presentationState
        self.preferredCanvasSize = preferredCanvasSize
        self.bill                = bill
        
        super.init(nibName: nil, bundle: nil)
    }
    
    // MARK: - Content -
    
    private func updateContent(bill: BillState.Bill) {
        if let host = host {
            self.bill = bill
            host.rootView = AnyView(content(bill: bill))
            resize()
        }
    }
    
    @ViewBuilder private func content(bill: BillState.Bill?) -> some View {
        if let bill = bill {
            switch bill {
            case .cash(let payload):
                BillView(
                    fiat: payload.fiat,
                    data: payload.codeData(),
                    canvasSize: canvasSize(),
                    action: action
                )
            }
            
        } else {
            BillView(
                fiat: 0,
                data: Data(),
                canvasSize: canvasSize(),
                action: action
            )
        }
    }
    
    private func canvasSize() -> CGSize {
        var rect = CGRect(origin: .zero, size: preferredCanvasSize)
        
        rect.size.height -= view.safeAreaInsets.top
        rect.size.height -= view.safeAreaInsets.bottom
        rect.size.width  -= view.safeAreaInsets.left
        rect.size.width  -= view.safeAreaInsets.right
        
        return rect.size
    }
    
    // MARK: - View -
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if !didAppear {
            didAppear = true
            
            setupHostController()
            setupDragGesture()
            
            resize()
            setState(.bottom, animated: false)
        }
    }
    
    private func setupHostController() {
        let host = SafeHostingController(rootView: AnyView(content(bill: bill)))
        
        addChild(host)
        view.addSubview(host.view)
        host.didMove(toParent: self)
        
        view.backgroundColor = .clear
        host.view.backgroundColor = .clear
        
        self.host = host
        
//        view.backgroundColor = .red.withAlphaComponent(0.5)
//        host.view.backgroundColor = .blue.withAlphaComponent(0.5)
        
        resize()
        layoutCenter()
    }
    
    // MARK: - Layout -
    
    func update(presentationState: PresentationState, bill: BillState.Bill?) {
        if let bill = bill {
            updateContent(bill: bill)
        }
        
        // Disable user interaction when there is no interactive
        // content to prevent capturing touch events unnecessarily
        switch presentationState {
        case .visible: view.isUserInteractionEnabled = true
        case .hidden:  view.isUserInteractionEnabled = false
        }
        
        // Only animate if the state is different
        // from the previous presentation
        guard presentationState != self.presentationState else {
            return
        }
        
        self.presentationState = presentationState
        
        switch presentationState {
        case .visible(let style):
            switch style {
            case .pop:
                setState(.centerDeflated, animated: false)
                setState(.center, animated: true)
            case .slide:
                setState(.bottom, animated: false)
                setState(.center, animated: true)
            }
            
//            Task {
//                try await Task.delay(seconds: 3)
//                
//                let rect = host.view.bounds
//                let renderer = UIGraphicsImageRenderer(bounds: rect)
//                let image = renderer.image { _ in
//                    _ = host.view.drawHierarchy(in: rect, afterScreenUpdates: true)
//                }
//                
//                let pngData = image.pngData()!
//                let controller = UIActivityViewController(activityItems: [pngData], applicationActivities: nil)
//                UIApplication.shared.rootViewController?.present(controller, animated: true, completion: nil)
//            }
            
        case .hidden(let style):
            cancelDrag()
            
            switch style {
            case .pop:
                setState(.centerInflated, animated: true)
            case .slide:
                setState(.bottom, animated: true)
            }
        }
    }
    
    // MARK: - Gesture -
    
    private func setupDragGesture() {
        let dragGesture = UIPanGestureRecognizer(target: self, action: #selector(drag(_:)))
        dragGesture.maximumNumberOfTouches = 1
        dragGesture.minimumNumberOfTouches = 1
        host?.view.addGestureRecognizer(dragGesture)
        self.dragGesture = dragGesture
    }
    
    private func cancelDrag() {
        dragGesture?.isEnabled = false
        dragGesture?.isEnabled = true
    }
    
    @objc private func drag(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view)
        let velocity = gesture.velocity(in: view)
        
        switch gesture.state {
        case .began:
            setState(.dragging, animated: false)
            
        case .changed:
            layoutDrag(offset: translation.y * dragMultiplier)
        
        case .ended, .cancelled, .failed:
            
            let canSwipe = bill?.canSwipeToDismiss ?? true
            
            if shouldDismiss(translation: translation, velocity: velocity) && canSwipe {
                dismissHandler?()
                setState(.bottom, animated: true)
            } else {
                setState(.center, animated: true)
            }
            
        default:
            break
        }
    }
    
    private func shouldDismiss(translation: CGPoint, velocity: CGPoint) -> Bool {
        if velocity.y < -200.0 {
            return false
        }
        return translation.y > 200.0 || velocity.y > 200.0
    }
    
    // MARK: - State Changes -
    
    private func setState(_ state: State, animated: Bool) {
        guard state != self.state else {
//            print("setState(\(animated ? "animated" : "-")): unchanged")
            return
        }
        
//        print("setState(\(animated ? "animated" : "-")): \(self.state) -> \(state)")
        let oldState = self.state
        self.state = state
        
        transitionState(from: oldState, to: state, animated: animated, completion: nil)
    }
    
    private func transitionState(from fromState: State, to toState: State, animated: Bool, completion: VoidAction? = nil) {
        switch (fromState, toState) {
        case (.bottom, .center), (.dragging, .center):
            if animated {
                animator = animate(.spring, completion: completion) { [weak self] in
                    self?.applyState(toState)
                }
                
                animator?.startAnimation()
            } else {
                applyState(toState)
            }
            
        case (.center, .bottom), (.dragging, .bottom):
            if animated {
                animator = animate(.springTight, completion: completion) { [weak self] in
                    self?.applyState(toState)
                }
                
                animator?.startAnimation()
            } else {
                applyState(toState)
            }
            
        case (.centerDeflated, .center):
            if animated {
                animator = animate(.springPop, completion: completion) { [weak self] in
                    self?.applyState(toState)
                }
                
                animator?.startAnimation()
                Haptics.vibrate()
                
            } else {
                applyState(toState)
            }
            
        case (.center, .centerInflated):
            if animated {
                animator = animate(.linearFast, completion: completion) { [weak self] in
                    self?.applyState(toState)
                }
                
                animator?.startAnimation()
                Haptics.vibrate()
                
            } else {
                applyState(toState)
            }
            
        default:
            applyState(toState)
        }
    }
    
    private func applyState(_ state: State) {
        switch state {
        case .dragging:
            break // No-op
        case .bottom:
            layoutBottom()
        case .center:
            layoutCenter()
        case .centerDeflated:
            layoutDeflatedCenter()
        case .centerInflated:
            layoutInflatedCenter()
        }
    }
    
    private func animate(_ curve: Curve, completion: VoidAction? = nil, animations: @escaping VoidAction) -> UIViewPropertyAnimator {
        let animator: UIViewPropertyAnimator
        switch curve {
        case .linearFast:
            animator = UIViewPropertyAnimator(duration: 0.1, curve: .linear, animations: animations)
        case .spring:
            animator = UIViewPropertyAnimator(duration: 0.6, dampingRatio: 0.6, animations: animations)
        case .springPop:
            animator = UIViewPropertyAnimator(duration: 0.4, dampingRatio: 0.4, animations: animations)
        case .springTight:
            animator = UIViewPropertyAnimator(duration: 0.6, dampingRatio: 0.9, animations: animations)
        }
        
        if let completion = completion {
            animator.addCompletion { _ in
                completion()
            }
        }
        
        return animator
    }
    
    // MARK: - Layout -
    
    private func layoutCenter() {
        host?.view.layer.opacity   = 1.0
        host?.view.layer.position  = view.center + centerOffset
        host?.view.layer.transform = CATransform3DIdentity
    }
    
    private func layoutDeflatedCenter() {
        host?.view.layer.opacity   = 0.0
        host?.view.layer.position  = view.center + centerOffset
        host?.view.layer.transform = CATransform3DMakeScale(0.55, 0.55, 0.55)
    }
    
    private func layoutInflatedCenter() {
        host?.view.layer.opacity   = 0.0
        host?.view.layer.position  = view.center + centerOffset
        host?.view.layer.transform = CATransform3DMakeScale(1.1, 1.1, 1.1)
    }
    
    private func layoutBottom() {
        host?.view.layer.opacity   = 1.0
        host?.view.layer.transform = CATransform3DIdentity
        host?.view.layer.position  = CGPoint(
            x: view.center.x,
            y: view.bounds.maxY + (host?.view.bounds.midY ?? 0)
        )
    }
    
    private func layoutDrag(offset: CGFloat) {
        host?.view.layer.opacity   = 1.0
        host?.view.layer.transform = CATransform3DIdentity
        host?.view.layer.position  = CGPoint(
            x: view.center.x,
            y: view.center.y + offset
        ) + centerOffset
    }
    
    private func resize() {
//        host.view.sizeToFit()
        
        if let hostView = host?.view {
            var bounds = hostView.bounds
            bounds.size = canvasSize()
            hostView.bounds = bounds
        }
    }
    
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        
        if let _ = host?.view {
            resize()
//            print("Host view bounds: \(view.layer.frame), bounds: \(self.view.bounds)")
        }
    }
}

// MARK: - Style -

private enum Curve {
    case linearFast
    case spring
    case springPop
    case springTight
}

// MARK: - State -

private enum State: Equatable {
    case dragging
    case bottom
    case center
    case centerDeflated
    case centerInflated
}

// MARK: - View -

private extension UIView {
    func shake() {
        let shake = CAKeyframeAnimation(keyPath: "transform.translation.x")
        shake.timingFunction = CAMediaTimingFunction(name: .easeOut)
        shake.duration = 0.8
        shake.values = [-5.0, -20.0, 20.0, -20.0, 20.0, -10.0, 10.0, -5.0, 5.0, 0.0]
        
        layer.add(shake, forKey: "shake")
    }
}

// MARK: - CGPoint -

extension CGPoint {
    static func +(lhs: CGPoint, rhs: CGSize) -> CGPoint {
        CGPoint(
            x: lhs.x + rhs.width,
            y: lhs.y + rhs.height
        )
    }
}

// MARK: - SafeHostingController -

private class SafeHostingController<Content> : UIHostingController<Content> where Content : View {
    override public init(rootView: Content) {
        super.init(rootView: rootView)
        
        disableSafeArea()
    }
    
    required init?(coder aDecoder: NSCoder) { fatalError() }
    
    func disableSafeArea() {
        guard let viewClass = object_getClass(view) else { return }
        
        let viewSubclassName = String(cString: class_getName(viewClass)).appending("_IgnoreSafeArea")
        if let viewSubclass = NSClassFromString(viewSubclassName) {
            object_setClass(view, viewSubclass)
        } else {
            guard let viewClassNameUtf8 = (viewSubclassName as NSString).utf8String else { return }
            guard let viewSubclass = objc_allocateClassPair(viewClass, viewClassNameUtf8, 0) else { return }
            
            if let method = class_getInstanceMethod(UIView.self, #selector(getter: UIView.safeAreaInsets)) {
                let safeAreaInsets: @convention(block) (AnyObject) -> UIEdgeInsets = { _ in
                    return .zero
                }
                class_addMethod(viewSubclass, #selector(getter: UIView.safeAreaInsets), imp_implementationWithBlock(safeAreaInsets), method_getTypeEncoding(method))
            }
            
            objc_registerClassPair(viewSubclass)
            object_setClass(view, viewSubclass)
        }
    }
}
