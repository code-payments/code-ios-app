//
//  Image+Icon.swift
//  FlipcashUI
//

import SwiftUI
import UIKit

extension Image {
    /// A Central icon from the FlipcashUI catalog, drawn as a template image tinted by the caller.
    /// It's decorative, so an icon-only control names itself with `.accessibilityLabel`.
    public static func icon(_ icon: Icon) -> Image {
        Image(decorative: icon.rawValue, bundle: Bundle.module)
    }

    /// Sizes an icon to a square frame, since asset icons ignore `.font` the way SF Symbols don't.
    public func iconSize(_ size: CGFloat) -> some View {
        resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

extension UIImage {
    /// A Central icon from the FlipcashUI catalog as a template `UIImage`, for UIKit menus and cells.
    public static func icon(_ icon: Icon) -> UIImage {
        UIImage(named: icon.rawValue, in: Bundle.module, compatibleWith: nil)!
            .withRenderingMode(.alwaysTemplate)
    }
}

// MARK: - Icon -

/// The app's icon set: Central Icons (2px stroke, rounded), outlined unless the case says `Filled`.
public enum Icon: String, CaseIterable, Sendable {
    case airplane = "central/Airplane"
    case archive = "central/Archive"
    case arrowBottomTop = "central/ArrowBottomTop"
    case arrowBoxLeft = "central/ArrowBoxLeft"
    case arrowCornerLeftDown = "central/ArrowCornerLeftDown"
    case arrowDown = "central/ArrowDown"
    case arrowInbox = "central/ArrowInbox"
    case arrowLeft = "central/ArrowLeft"
    case arrowRight = "central/ArrowRight"
    case arrowRotateClockwise = "central/ArrowRotateClockwise"
    case arrowShareLeft = "central/ArrowShareLeft"
    case arrowShareLeftFilled = "central/ArrowShareLeftFilled"
    case arrowShareRight = "central/ArrowShareRight"
    case arrowUp = "central/ArrowUp"
    case arrowUpWall = "central/ArrowUpWall"
    case arrowWallDown = "central/ArrowWallDown"
    case arrowsRepeat = "central/ArrowsRepeat"
    case at = "central/At"
    case banknote1 = "central/Banknote1"
    case bell2 = "central/Bell2"
    case bell2Off = "central/Bell2Off"
    case bellOff = "central/BellOff"
    case bezierCurve = "central/BezierCurve"
    case bubble2 = "central/Bubble2"
    case bubbleAlert = "central/BubbleAlert"
    case bubbleCrossed = "central/BubbleCrossed"
    case bug = "central/Bug"
    case camera1 = "central/Camera1"
    case chainLink4 = "central/ChainLink4"
    case chatBubbles = "central/ChatBubbles"
    case chatBubblesFilled = "central/ChatBubblesFilled"
    case checklist = "central/Checklist"
    case checkmark1 = "central/Checkmark1"
    case chevronDownMedium = "central/ChevronDownMedium"
    case chevronLeftMedium = "central/ChevronLeftMedium"
    case chevronRightMedium = "central/ChevronRightMedium"
    case circleArrowDown = "central/CircleArrowDown"
    case circleBanSign = "central/CircleBanSign"
    case circleCheck = "central/CircleCheck"
    case circleDotted = "central/CircleDotted"
    case circleInfo = "central/CircleInfo"
    case circleMinus = "central/CircleMinus"
    case circlePerson = "central/CirclePerson"
    case circlePlus = "central/CirclePlus"
    case circleX = "central/CircleX"
    case circleXFilled = "central/CircleXFilled"
    case clipboard = "central/Clipboard"
    case clock = "central/Clock"
    case coins = "central/Coins"
    case coinsAdd = "central/CoinsAdd"
    case creditCard1 = "central/CreditCard1"
    case crossMedium = "central/CrossMedium"
    case crown = "central/Crown"
    case dotGrid1x3Horizontal = "central/DotGrid1x3Horizontal"
    case dotGrid1x3Vertical = "central/DotGrid1x3Vertical"
    case email1 = "central/Email1"
    case emojiAddReaction = "central/EmojiAddReaction"
    case exclamationCircle = "central/ExclamationCircle"
    case exclamationTriangle = "central/ExclamationTriangle"
    case faceId = "central/FaceId"
    case fileBend = "central/FileBend"
    case fileDownload = "central/FileDownload"
    case fileText = "central/FileText"
    case fingerPrint1 = "central/FingerPrint1"
    case flag1 = "central/Flag1"
    case folder1 = "central/Folder1"
    case gift1 = "central/Gift1"
    case globe = "central/Globe"
    case grid = "central/Grid"
    case group1 = "central/Group1"
    case group3 = "central/Group3"
    case hand5Finger = "central/Hand5Finger"
    case history = "central/History"
    case images1 = "central/Images1"
    case images3 = "central/Images3"
    case invite = "central/Invite"
    case key1 = "central/Key1"
    case kikCode = "central/KikCode"
    case kikCodeFilled = "central/KikCodeFilled"
    case lightningBolt = "central/LightningBolt"
    case lightningBoltOff = "central/LightningBoltOff"
    case lock = "central/Lock"
    case magnifyingGlass = "central/MagnifyingGlass"
    case maintenance = "central/Maintenance"
    case paperPlaneTopRight = "central/PaperPlaneTopRight"
    case pencil2 = "central/Pencil2"
    case people = "central/People"
    case peopleCircle = "central/PeopleCircle"
    case peopleCircleFilled = "central/PeopleCircleFilled"
    case peopleGear = "central/PeopleGear"
    case peopleIdCard = "central/PeopleIdCard"
    case phone = "central/Phone"
    case plusLarge = "central/PlusLarge"
    case qrCode = "central/QrCode"
    case questionmarkCircle = "central/QuestionmarkCircle"
    case send = "central/Send"
    case settingsGear2 = "central/SettingsGear2"
    case settingsSliderThree = "central/SettingsSliderThree"
    case shareOs = "central/ShareOs"
    case squareBehindSquare1 = "central/SquareBehindSquare1"
    case squareX = "central/SquareX"
    case textSize = "central/TextSize"
    case trashCan = "central/TrashCan"
    case trophy = "central/Trophy"
    case user = "central/User"
    case userAdd = "central/UserAdd"
    case volumeOff = "central/VolumeOff"
    case wallet1 = "central/Wallet1"
    case wallet5 = "central/Wallet5"
    case wallet5Filled = "central/Wallet5Filled"
}
