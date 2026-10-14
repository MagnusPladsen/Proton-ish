import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let canvas: CGFloat = 1024
let center = CGPoint(x: canvas / 2, y: canvas / 2)
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
let coverage: CGFloat = 0.90

// Two crossed orbits around a wine drop, with one electron on the front of an orbit
let orbitRadiusX: CGFloat = 470
let orbitRadiusY: CGFloat = 150
let orbitAngles: [CGFloat] = [35, -35]
let strokeWidth: CGFloat = 40
let knockoutGap: CGFloat = 22
let dropRadius: CGFloat = 104
let dropShiftY: CGFloat = -40
let electronRadius: CGFloat = 40
let electronOrbit = 0
let electronAngle: CGFloat = -40

enum Element: String, CaseIterable {
    case orbitsBack = "Orbits Back"
    case drop = "Drop"
    case orbitsFront = "Orbits Front"
    case electron = "Electron"

    var fileName: String {
        rawValue.lowercased().replacingOccurrences(of: " ", with: "-") + ".png"
    }

    var depth: Double {
        switch self {
        case .orbitsBack: 0.40
        case .drop: 0.80
        case .orbitsFront: 0.95
        case .electron: 1.00
        }
    }

    var translucency: Double {
        switch self {
        case .orbitsBack: 0.30
        case .drop: 0.45
        case .orbitsFront: 0.30
        case .electron: 0.40
        }
    }
}

func makeContext(size: CGFloat) -> CGContext {
    let context = CGContext(
        data: nil,
        width: Int(size),
        height: Int(size),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setAllowsAntialiasing(true)
    context.interpolationQuality = .high
    return context
}

func orbitFrame(_ angle: CGFloat) -> CGAffineTransform {
    CGAffineTransform(translationX: center.x, y: center.y)
        .rotated(by: angle * .pi / 180)
}

func orbitPath(_ angle: CGFloat) -> CGPath {
    var transform = orbitFrame(angle)
    let box = CGRect(
        x: -orbitRadiusX,
        y: -orbitRadiusY,
        width: orbitRadiusX * 2,
        height: orbitRadiusY * 2
    )
    return CGPath(ellipseIn: box, transform: &transform)
}

// The half of an orbit's plane that passes in front of the drop
func halfPlane(_ angle: CGFloat, front: Bool) -> CGPath {
    let big = canvas * 2
    let overlap: CGFloat = 6
    let rect = front
        ? CGRect(x: -big, y: -big, width: big * 2, height: big + overlap)
        : CGRect(x: -big, y: -overlap, width: big * 2, height: big + overlap)
    var transform = orbitFrame(angle)
    return CGPath(rect: rect, transform: &transform)
}

// A teardrop: round bottom, point at the top
func dropPath(grownBy grow: CGFloat = 0) -> CGPath {
    let r = dropRadius + grow
    let cx = center.x
    let cy = center.y + dropShiftY
    let tip = CGPoint(x: cx, y: cy + r * 2.1)
    let path = CGMutablePath()
    path.move(to: tip)
    path.addCurve(
        to: CGPoint(x: cx + r, y: cy),
        control1: CGPoint(x: cx + r * 0.35, y: cy + r * 1.4),
        control2: CGPoint(x: cx + r, y: cy + r * 0.75)
    )
    path.addArc(center: CGPoint(x: cx, y: cy), radius: r, startAngle: 0, endAngle: .pi, clockwise: true)
    path.addCurve(
        to: tip,
        control1: CGPoint(x: cx - r, y: cy + r * 0.75),
        control2: CGPoint(x: cx - r * 0.35, y: cy + r * 1.4)
    )
    path.closeSubpath()
    return path
}

func electronCenter() -> CGPoint {
    let t = electronAngle * .pi / 180
    return CGPoint(x: orbitRadiusX * cos(t), y: orbitRadiusY * sin(t))
        .applying(orbitFrame(orbitAngles[electronOrbit]))
}

func strokeHalves(front: Bool, into context: CGContext) {
    for angle in orbitAngles {
        context.saveGState()
        context.addPath(halfPlane(angle, front: front))
        context.clip()
        context.setLineWidth(strokeWidth)
        context.addPath(orbitPath(angle))
        context.strokePath()
        context.restoreGState()
    }
}

func cutFrontHalves(from context: CGContext) {
    context.saveGState()
    context.setBlendMode(.clear)
    for angle in orbitAngles {
        context.saveGState()
        context.addPath(halfPlane(angle, front: true))
        context.clip()
        context.setLineWidth(strokeWidth + knockoutGap * 2)
        context.addPath(orbitPath(angle))
        context.strokePath()
        context.restoreGState()
    }
    context.restoreGState()
}

func draw(_ element: Element, into context: CGContext) {
    context.setStrokeColor(white)
    context.setFillColor(white)

    switch element {
    case .orbitsBack:
        strokeHalves(front: false, into: context)
        context.setBlendMode(.clear)
        context.addPath(dropPath(grownBy: knockoutGap))
        context.fillPath()
        context.setBlendMode(.normal)

    case .drop:
        context.addPath(dropPath())
        context.fillPath()
        cutFrontHalves(from: context)

    case .orbitsFront:
        strokeHalves(front: true, into: context)
        let e = electronCenter()
        let gap = electronRadius + knockoutGap
        context.setBlendMode(.clear)
        context.fillEllipse(in: CGRect(x: e.x - gap, y: e.y - gap, width: gap * 2, height: gap * 2))
        context.setBlendMode(.normal)

    case .electron:
        let e = electronCenter()
        context.fillEllipse(in: CGRect(
            x: e.x - electronRadius, y: e.y - electronRadius,
            width: electronRadius * 2, height: electronRadius * 2
        ))
    }
}

func render(_ elements: [Element]) -> CGImage {
    let context = makeContext(size: canvas)
    for element in elements {
        draw(element, into: context)
    }
    return context.makeImage()!
}

func inkBounds(_ image: CGImage) -> CGRect {
    let width = image.width
    let height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    pixels.withUnsafeMutableBytes { buffer in
        let scan = CGContext(
            data: buffer.baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        scan.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    var minX = width, minY = height, maxX = -1, maxY = -1
    for y in 0..<height {
        for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 8 {
            if x < minX { minX = x }
            if x > maxX { maxX = x }
            if y < minY { minY = y }
            if y > maxY { maxY = y }
        }
    }
    guard maxX >= minX, maxY >= minY else {
        return CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
    }
    return CGRect(
        x: CGFloat(minX),
        y: CGFloat(minY),
        width: CGFloat(maxX - minX + 1),
        height: CGFloat(maxY - minY + 1)
    )
}

func normalized(_ image: CGImage, sharedInk ink: CGRect) -> CGImage {
    let scale = canvas * coverage / max(ink.width, ink.height)
    let context = makeContext(size: canvas)
    context.translateBy(x: canvas / 2, y: canvas / 2)
    context.scaleBy(x: scale, y: scale)
    context.translateBy(x: -ink.midX, y: -ink.midY)
    context.draw(image, in: CGRect(x: 0, y: 0, width: canvas, height: canvas))
    return context.makeImage()!
}

func write(_ image: CGImage, to url: URL) throws {
    guard
        let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        )
    else {
        throw CocoaError(.fileWriteUnknown)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw CocoaError(.fileWriteUnknown)
    }
}

func group(for element: Element) -> [String: Any] {
    [
        "blur-material": NSNull(),
        "layers": [
            [
                "fill": ["solid": "srgb:1.00000,1.00000,1.00000,1.00000"],
                "image-name": element.fileName,
                "name": element.rawValue,
            ]
        ],
        "opacity": 1,
        "refractivity": ["depth": element.depth, "enabled": true, "strength": 0.005],
        "shadow": ["kind": "neutral", "opacity": 0.5],
        "specular": "inside",
        "translucency": ["enabled": true, "value": element.translucency],
    ]
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write("usage: icon <output.icon>\n".data(using: .utf8)!)
    exit(2)
}

let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let assets = root.appendingPathComponent("Assets", isDirectory: true)
try? FileManager.default.removeItem(at: root)
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)

let sharedInk = inkBounds(render(Element.allCases))
for element in Element.allCases {
    let layer = normalized(render([element]), sharedInk: sharedInk)
    try write(layer, to: assets.appendingPathComponent(element.fileName))
}

let document: [String: Any] = [
    "features": ["refractivity", "specular-location"],
    "fill": [
        "linear-gradient": [
            "srgb:0.10196,0.52941,0.52941,1.00000",
            "srgb:0.04706,0.27059,0.30196,1.00000",
        ]
    ],
    "groups": Element.allCases.map(group(for:)),
    "supported-platforms": ["circles": ["watchOS"], "squares": "shared"],
]
try JSONSerialization
    .data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
    .write(to: root.appendingPathComponent("icon.json"))
