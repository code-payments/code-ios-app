//
//  GroupQRGeometry.swift
//  Flipcash
//

import CoreGraphics
import Foundation
import SwiftUI

/// The shapes of a group card's QR tile, in module units with the quiet zone included, so the
/// on-screen view, the PNG and the SVG all draw from one model.
///
/// Light modules on a dark rounded tile: runs of modules join into rounded shapes, the three
/// finder patterns are drawn as shapes of their own, and a 9 x 9 area at the centre is left clear
/// for the Flipcash mark.
nonisolated struct GroupQRGeometry {

    // MARK: - Style -

    /// The tile's colour, sampled from the reference design.
    static let tileHex = "#2E2E30"
    static let moduleHex = "#FFFFFF"

    static let tileColor = Color(red: 0x2E / 255, green: 0x2E / 255, blue: 0x30 / 255)

    /// Light modules around the symbol, inside the tile.
    static let quietZone = 4

    /// The tile's corner radius as a fraction of its width.
    static let tileCornerFraction: CGFloat = 0.12

    /// The side of the centre area whose modules are not drawn, and of the box the mark sits in.
    static let clearedSide = 9
    static let markSide: CGFloat = 5

    private static let moduleCornerRadius: CGFloat = 0.5
    private static let finderSide = 7

    // MARK: - Geometry -

    let modules: QRModules

    /// Modules per side of the tile: the symbol plus its quiet zone on both sides.
    var tileSide: Int { modules.size + 2 * Self.quietZone }

    /// The dark modules that are drawn as modules.
    var modulesPath: CGPath {
        let path = CGMutablePath()
        let drawn: (Int, Int) -> Bool = isDrawn
        for y in 0..<modules.size {
            for x in 0..<modules.size where drawn(x, y) {
                let corners = RoundedCorners.of(x: x, y: y, isSet: drawn)
                Self.addModule(
                    to: path,
                    x: CGFloat(x + Self.quietZone),
                    y: CGFloat(y + Self.quietZone),
                    corners: corners
                )
            }
        }
        return path
    }

    /// The three finder patterns: a 7 x 7 ring one module thick with a 3 x 3 centre. Filled even-odd.
    var findersPath: CGPath {
        let path = CGMutablePath()
        let far = CGFloat(modules.size - Self.finderSide + Self.quietZone)
        let near = CGFloat(Self.quietZone)
        for origin in [CGPoint(x: near, y: near), CGPoint(x: far, y: near), CGPoint(x: near, y: far)] {
            path.addPath(CGPath(
                roundedRect: CGRect(x: origin.x, y: origin.y, width: 7, height: 7),
                cornerWidth: 2, cornerHeight: 2, transform: nil
            ))
            path.addPath(CGPath(
                roundedRect: CGRect(x: origin.x + 1, y: origin.y + 1, width: 5, height: 5),
                cornerWidth: 1, cornerHeight: 1, transform: nil
            ))
            path.addPath(CGPath(
                roundedRect: CGRect(x: origin.x + 2, y: origin.y + 2, width: 3, height: 3),
                cornerWidth: 1, cornerHeight: 1, transform: nil
            ))
        }
        return path
    }

    /// The Flipcash mark, white, fitted to a 5 x 5 box at the centre. Filled even-odd.
    var logoPath: CGPath {
        let mark = FlipcashMark.path
        let scale = Self.markSide / FlipcashMark.bounds.height
        var transform = CGAffineTransform.identity
            .translatedBy(x: CGFloat(tileSide) / 2, y: CGFloat(tileSide) / 2)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -FlipcashMark.bounds.midX, y: -FlipcashMark.bounds.midY)
        return mark.copy(using: &transform) ?? mark
    }

    // MARK: - Masks -

    private func isFinder(_ x: Int, _ y: Int) -> Bool {
        let far = modules.size - Self.finderSide
        let nearX = x < Self.finderSide, farX = x >= far
        let nearY = y < Self.finderSide, farY = y >= far
        return (nearX && nearY) || (farX && nearY) || (nearX && farY)
    }

    private func isCleared(_ x: Int, _ y: Int) -> Bool {
        let low = (modules.size - Self.clearedSide) / 2
        let high = low + Self.clearedSide
        return (low..<high).contains(x) && (low..<high).contains(y)
    }

    /// Whether the module at `x`, `y` is a dark one drawn as a module: not under a finder shape,
    /// not in the cleared centre.
    func isDrawn(_ x: Int, _ y: Int) -> Bool {
        modules[x, y] && !isFinder(x, y) && !isCleared(x, y)
    }

    // MARK: - Rounding -

    /// Which corners of a module are rounded.
    struct RoundedCorners: OptionSet, Equatable {
        let rawValue: Int
        static let topLeading = RoundedCorners(rawValue: 1)
        static let topTrailing = RoundedCorners(rawValue: 2)
        static let bottomTrailing = RoundedCorners(rawValue: 4)
        static let bottomLeading = RoundedCorners(rawValue: 8)

        /// A corner is rounded when neither of the two orthogonal neighbours that share it is set,
        /// so adjacent modules join into one continuous shape.
        static func of(x: Int, y: Int, isSet: (Int, Int) -> Bool) -> RoundedCorners {
            let up = isSet(x, y - 1), down = isSet(x, y + 1)
            let left = isSet(x - 1, y), right = isSet(x + 1, y)
            var corners: RoundedCorners = []
            if !up && !left { corners.insert(.topLeading) }
            if !up && !right { corners.insert(.topTrailing) }
            if !down && !right { corners.insert(.bottomTrailing) }
            if !down && !left { corners.insert(.bottomLeading) }
            return corners
        }
    }

    /// A unit square at `x`, `y` with `corners` rounded to half a module, wound clockwise.
    private static func addModule(to path: CGMutablePath, x: CGFloat, y: CGFloat, corners: RoundedCorners) {
        let r = moduleCornerRadius
        let (minX, minY, maxX, maxY) = (x, y, x + 1, y + 1)

        path.move(to: CGPoint(x: corners.contains(.topLeading) ? minX + r : minX, y: minY))
        corner(.topTrailing, at: CGPoint(x: maxX, y: minY), toward: CGPoint(x: maxX, y: maxY))
        corner(.bottomTrailing, at: CGPoint(x: maxX, y: maxY), toward: CGPoint(x: minX, y: maxY))
        corner(.bottomLeading, at: CGPoint(x: minX, y: maxY), toward: CGPoint(x: minX, y: minY))
        corner(.topLeading, at: CGPoint(x: minX, y: minY), toward: CGPoint(x: maxX, y: minY))
        path.closeSubpath()

        func corner(_ flag: RoundedCorners, at point: CGPoint, toward next: CGPoint) {
            if corners.contains(flag) {
                path.addArc(tangent1End: point, tangent2End: next, radius: r)
            } else {
                path.addLine(to: point)
            }
        }
    }
}

// MARK: - Mark -

/// The Flipcash mark: the two bars and the dot of Android's `ic_logo_round_white`, without its
/// outer disc, in that drawable's 62 x 62 viewport.
nonisolated enum FlipcashMark {

    /// The mark's extent in the viewport, fixed rather than measured from the Bézier control points.
    static let bounds = CGRect(x: 20, y: 15, width: 44.057 - 20, height: 49 - 15)

    static let pathData = "M24.843,15L24.811,15C22.154,15 20,17.154 20,19.811C20,22.469 22.154,24.623 24.811,24.623L24.811,24.623L34.434,24.623L34.434,24.623L37.642,24.623L39.245,24.623L39.246,24.623C41.903,24.623 44.057,22.469 44.057,19.812C44.057,17.154 41.903,15 39.246,15L39.245,15L37.642,15L34.434,15L34.434,15L24.843,15ZM34.434,27.188L36.038,27.188L36.038,27.188C38.695,27.188 40.849,29.342 40.849,32C40.849,34.657 38.695,36.811 36.038,36.811L36.038,36.811L34.434,36.811L24.858,36.811L24.811,36.811C22.154,36.811 20,34.657 20,32C20,29.343 22.154,27.188 24.811,27.188L24.811,27.188L24.811,27.188L34.434,27.188ZM29.623,44.189C29.623,41.531 27.469,39.377 24.811,39.377C22.154,39.377 20,41.531 20,44.189C20,46.846 22.154,49 24.811,49C27.469,49 29.623,46.846 29.623,44.189Z"

    static var path: CGPath { parse(pathData) }

    /// Reads absolute `M`, `L`, `C` and `Z` commands, the only ones the mark uses.
    static func parse(_ data: String) -> CGPath {
        let path = CGMutablePath()
        var command: Character = "M"
        var numbers: [CGFloat] = []
        var token = ""

        func flushNumber() {
            if let value = Double(token) { numbers.append(CGFloat(value)) }
            token = ""
        }

        func flushCommand() {
            flushNumber()
            defer { numbers.removeAll() }
            switch command {
            case "M":
                var index = 0
                while index + 1 < numbers.count {
                    let point = CGPoint(x: numbers[index], y: numbers[index + 1])
                    index == 0 ? path.move(to: point) : path.addLine(to: point)
                    index += 2
                }
            case "L":
                var index = 0
                while index + 1 < numbers.count {
                    path.addLine(to: CGPoint(x: numbers[index], y: numbers[index + 1]))
                    index += 2
                }
            case "C":
                var index = 0
                while index + 5 < numbers.count {
                    path.addCurve(
                        to: CGPoint(x: numbers[index + 4], y: numbers[index + 5]),
                        control1: CGPoint(x: numbers[index], y: numbers[index + 1]),
                        control2: CGPoint(x: numbers[index + 2], y: numbers[index + 3])
                    )
                    index += 6
                }
            case "Z":
                path.closeSubpath()
            default:
                break
            }
        }

        for character in data {
            switch character {
            case "M", "L", "C", "Z":
                flushCommand()
                command = character
            case ",", " ":
                flushNumber()
            case "-" where !token.isEmpty:
                flushNumber()
                token.append(character)
            default:
                token.append(character)
            }
        }
        flushCommand()
        return path
    }
}

// MARK: - SwiftUI -

/// One layer of the QR tile as a SwiftUI shape, scaled to fill the rect it is given.
nonisolated struct GroupQRLayer: Shape {

    enum Kind {
        case modules, finders, logo
    }

    let geometry: GroupQRGeometry
    let kind: Kind

    func path(in rect: CGRect) -> Path {
        let source: CGPath = switch kind {
        case .modules: geometry.modulesPath
        case .finders: geometry.findersPath
        case .logo: geometry.logoPath
        }
        let scale = min(rect.width, rect.height) / CGFloat(geometry.tileSide)
        let transform = CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: scale, y: scale)
        return Path(source).applying(transform)
    }
}

/// The QR tile on screen: the dark rounded tile with its symbol, edge to edge.
struct GroupQRTile: View {

    let geometry: GroupQRGeometry

    var body: some View {
        ZStack {
            GeometryReader { proxy in
                RoundedRectangle(
                    cornerRadius: proxy.size.width * GroupQRGeometry.tileCornerFraction,
                    style: .circular
                )
                .fill(GroupQRGeometry.tileColor)
            }
            GroupQRLayer(geometry: geometry, kind: .modules).fill(Color.white)
            GroupQRLayer(geometry: geometry, kind: .finders).fill(Color.white, style: FillStyle(eoFill: true))
            GroupQRLayer(geometry: geometry, kind: .logo).fill(Color.white, style: FillStyle(eoFill: true))
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
