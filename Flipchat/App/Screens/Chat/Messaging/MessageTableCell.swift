//
//  MessageTableCell.swift
//  Code
//
//  Created by Dima Bart on 2024-12-14.
//

import UIKit
import CodeUI

class MessageTableCell: UITableViewCell {
    
    private var panGesture: UIPanGestureRecognizer!
    private var longPressGesture: UILongPressGestureRecognizer!
    private var doubleTapGesture: UITapGestureRecognizer!
    
    private var startCenter: CGPoint = .zero
    private var didTap: Bool = false
    
    private let threshold:       CGFloat = 42
    private let dragCoefficient: CGFloat = 0.3
    private let snapDistance:    CGFloat = 8
    
    var swipeEnabled: Bool = false {
        didSet {
            panGesture.isEnabled = swipeEnabled
        }
    }
    
    var onSwipeToReply: (() -> Void)?
    var onLongPress: (() -> Void)?
    var onDoubleTap: (() -> Void)?
    
    private let arrowImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "arrowshape.turn.up.backward.fill")
        imageView.tintColor = .white
        imageView.alpha = 0
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    // MARK: - Init -
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
        panGesture.delegate = self
        addGestureRecognizer(panGesture)
        
        longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPressGesture.minimumPressDuration = 0.3
        addGestureRecognizer(longPressGesture)
        
        doubleTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTapGesture.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTapGesture)
        
        addSubview(arrowImageView)
        
        NSLayoutConstraint.activate([
            arrowImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            arrowImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: -15), // Outside the bounds
            arrowImageView.widthAnchor.constraint(equalToConstant: 20),
            arrowImageView.heightAnchor.constraint(equalToConstant: 20)
        ])
    }
    
    // MARK: - Drag -
    
    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            onLongPress?()
        }
    }
    
    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if gesture.state == .ended {
            onDoubleTap?()
        }
    }
    
    @objc private func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: gesture.view)
        let xOffset = translation.x * dragCoefficient
        let percentComplete = min(max(xOffset / threshold, 0), 1)
        
        switch gesture.state {
        case .began:
            startCenter = center
            didTap = false
            
        case .changed:
            if xOffset > threshold - snapDistance {
                if !didTap {
                    didTap = true
                    Feedback.tap()
                }
                center.x = startCenter.x + threshold
                
            } else {
                if didTap {
                    Feedback.medium()
                    didTap = false
                }
                center.x = max(startCenter.x + xOffset, startCenter.x)
            }
            self.arrowImageView.alpha = percentComplete
            self.arrowImageView.transform = .init(
                scaleX: 0.5 + (0.5 * percentComplete),
                y: 0.5 + (0.5 * percentComplete)
            )
            
        case .ended:
            if xOffset >= threshold - snapDistance {
                onSwipeToReply?()
            }
            animateToIdentity()
            
        case .cancelled:
            animateToIdentity()
            
        default:
            break
        }
    }
    
    private func animateToIdentity() {
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 1.5, options: .curveEaseOut) {
            self.center = self.startCenter
            self.arrowImageView.alpha = 0
        }
    }
    
    // MARK: - Gesture Delegate -
    
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer == panGesture {
            let t = panGesture.translation(in: panGesture.view)
            return abs(t.x) > abs(t.y)
        }
        return true
    }

    override func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer == panGesture || otherGestureRecognizer == panGesture {
            return false
        }
        return true
    }
}
