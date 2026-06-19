//
//  ChatCashCardCell.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit

/// A recycled cell for a cash payment row: a fixed-size card (shared `BubbleBackgroundView`
/// chrome) with the token name + optional coin icon in the top-left and a centered
/// "You sent / You received" caption above the currency flag + amount. Aligns to the leading or
/// trailing edge by sender. Dumb — `configure(with:)` is the only input; the strings, flag name,
/// and icon URL all arrive on the `ChatMessage`.
public final class ChatCashCardCell: UICollectionViewCell {

    public static let reuseIdentifier = "ChatCashCardCell"

    /// The card's fixed footprint, matching the SwiftUI cash bubble.
    private static let cardSize = CGSize(width: 232, height: 170)

    private let card = BubbleBackgroundView()
    private let coinIcon = UIImageView()
    private let tokenLabel = UILabel()
    private let flag = UIImageView()
    private let captionLabel = UILabel()
    private let amountLabel = UILabel()
    private var leadingConstraint: NSLayoutConstraint!
    private var trailingConstraint: NSLayoutConstraint!
    private var iconTask: Task<Void, Never>?

    public override init(frame: CGRect) {
        super.init(frame: frame)

        card.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(card)

        configureCircle(coinIcon, diameter: 13)
        tokenLabel.font = .default(size: 12, weight: .bold) // .appTextHeading
        tokenLabel.textColor = UIColor.white.withAlphaComponent(0.5) // secondaryText

        let tokenRow = UIStackView(arrangedSubviews: [coinIcon, tokenLabel])
        tokenRow.spacing = 4
        tokenRow.alignment = .center
        tokenRow.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(tokenRow)

        captionLabel.font = .default(size: 12, weight: .bold) // .appTextCaption (bold in UIKit)
        captionLabel.textColor = UIColor.white.withAlphaComponent(0.5) // secondaryText

        configureCircle(flag, diameter: 30)
        amountLabel.font = .default(size: 38, weight: .bold) // amountFont
        amountLabel.textColor = .white // .textMain
        amountLabel.numberOfLines = 1
        amountLabel.adjustsFontSizeToFitWidth = true
        amountLabel.minimumScaleFactor = 0.5
        amountLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let amountRow = UIStackView(arrangedSubviews: [flag, amountLabel])
        amountRow.spacing = 11
        amountRow.alignment = .center

        let centerStack = UIStackView(arrangedSubviews: [captionLabel, amountRow])
        centerStack.axis = .vertical
        centerStack.spacing = 4
        centerStack.alignment = .center
        centerStack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(centerStack)

        leadingConstraint = card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12)
        trailingConstraint = card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: contentView.topAnchor),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            card.widthAnchor.constraint(equalToConstant: Self.cardSize.width),
            card.heightAnchor.constraint(equalToConstant: Self.cardSize.height),

            tokenRow.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 11),
            tokenRow.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),

            centerStack.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            centerStack.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            centerStack.leadingAnchor.constraint(greaterThanOrEqualTo: card.leadingAnchor, constant: 16),
            centerStack.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -16),
        ])
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func configureCircle(_ imageView: UIImageView, diameter: CGFloat) {
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = diameter / 2
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: diameter),
            imageView.heightAnchor.constraint(equalToConstant: diameter),
        ])
    }

    public override func prepareForReuse() {
        super.prepareForReuse()
        iconTask?.cancel()
        coinIcon.image = nil
    }

    public func configure(with message: ChatMessage) {
        guard case .cash(let cash) = message.content else { return }
        tokenLabel.text = cash.token
        captionLabel.text = message.sender == .me ? "You sent" : "You received"
        amountLabel.text = cash.amount

        let flagImage = cash.flagImageName.flatMap { UIImage(named: $0, in: .module, compatibleWith: nil) }
        flag.image = flagImage
        flag.isHidden = flagImage == nil

        iconTask?.cancel()
        coinIcon.image = nil
        coinIcon.isHidden = cash.iconURL == nil
        if let url = cash.iconURL {
            iconTask = Task { [weak self] in
                guard let data = try? await URLSession.shared.data(from: url).0,
                      let image = UIImage(data: data) else { return }
                self?.coinIcon.image = image
            }
        }

        card.apply(
            fill: BubbleBackgroundView.fill(isFromSelf: message.sender == .me),
            corners: BubbleBackgroundView.corners(
                isFromSelf: message.sender == .me,
                groupedAbove: message.isContinuationFromPrevious,
                groupedBelow: message.isContinuedByNext
            )
        )
        leadingConstraint.isActive = message.sender == .other
        trailingConstraint.isActive = message.sender == .me
    }
}

#Preview("Cash cards") {
    let layout = UICollectionViewFlowLayout()
    layout.estimatedItemSize = UICollectionViewFlowLayout.automaticSize
    layout.minimumLineSpacing = 4

    let samples: [ChatMessage] = [
        ChatMessage(id: "1", content: .cash(ChatCashContent(amount: "$5.00", token: "Cash", flagImageName: "us")), sender: .me),
        ChatMessage(id: "2", content: .cash(ChatCashContent(amount: "$12.50", token: "Cash", flagImageName: "us")), sender: .other),
    ]

    return ChatCashCardCellPreviewController(messages: samples, layout: layout)
}

private final class ChatCashCardCellPreviewController: UICollectionViewController {
    private let messages: [ChatMessage]

    init(messages: [ChatMessage], layout: UICollectionViewLayout) {
        self.messages = messages
        super.init(collectionViewLayout: layout)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        collectionView.backgroundColor = .black
        collectionView.register(ChatCashCardCell.self, forCellWithReuseIdentifier: ChatCashCardCell.reuseIdentifier)
    }

    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        messages.count
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ChatCashCardCell.reuseIdentifier, for: indexPath) as! ChatCashCardCell
        cell.configure(with: messages[indexPath.item])
        return cell
    }
}
#endif
