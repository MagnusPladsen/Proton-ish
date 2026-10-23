import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let canvas: CGFloat = 1024
let center = CGPoint(x: canvas / 2, y: canvas / 2)
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
let coverage: CGFloat = 0.76

// A wine glass inside two crossed orbits, with the orbits' front halves passing over the glass
let orbitCenter = CGPoint(x: canvas / 2, y: 556)
let orbitRadiusX: CGFloat = 380
let orbitRadiusY: CGFloat = 118
let orbitStroke: CGFloat = 32
let knockoutGap: CGFloat = 16
let rimY: CGFloat = 756
let bowlHalfWidth: CGFloat = 180
let bowlDepth: CGFloat = 330
let glassStroke: CGFloat = 34
let stemLength: CGFloat = 190
let baseHalfWidth: CGFloat = 130
let wineLevel: CGFloat = 0.42
let bowlBottom = rimY - bowlDepth
let stemBottom = bowlBottom - stemLength

enum Orbit: CaseIterable {
    case sky, lavender

    var angle: CGFloat { self == .sky ? -24 : 24 }

    var fill: String {
        switch self {
        case .sky: "srgb:0.49020,0.82745,0.98824,1.00000"
        case .lavender: "srgb:0.76863,0.70980,0.99216,1.00000"
        }
    }
}

enum Element: CaseIterable {
    case orbitBack(Orbit)
    case wine
    case glass
    case orbitFront(Orbit)

    static var allCases: [Element] {
        Orbit.allCases.map(orbitBack) + [.wine, .glass] + Orbit.allCases.map(orbitFront)
    }

    var name: String {
        switch self {
        case .orbitBack(let orbit): "Orbit Back \(orbit == .sky ? "Sky" : "Lavender")"
        case .wine: "Wine"
        case .glass: "Glass"
        case .orbitFront(let orbit): "Orbit Front \(orbit == .sky ? "Sky" : "Lavender")"
        }
    }

    var fileName: String {
        name.lowercased().replacingOccurrences(of: " ", with: "-") + ".png"
    }

    var fill: String {
        switch self {
        case .orbitBack(let orbit), .orbitFront(let orbit): orbit.fill
        case .wine: "srgb:0.88235,0.11373,0.28235,1.00000"
        case .glass: "srgb:1.00000,1.00000,1.00000,1.00000"
        }
    }
}

// Icon Composer groups, back to front, each with its layers; icon.json lists them front to back
struct Group {
    let name: String
    let elements: [Element]
    let depth: Double
    let translucency: Double
}

let groups = [
    Group(name: "Orbits Back", elements: Orbit.allCases.map(Element.orbitBack), depth: 0.40, translucency: 0.15),
    Group(name: "Wine", elements: [.wine], depth: 0.70, translucency: 0.10),
    Group(name: "Glass", elements: [.glass], depth: 0.85, translucency: 0.35),
    Group(name: "Orbits Front", elements: Orbit.allCases.map(Element.orbitFront), depth: 0.95, translucency: 0.15),
]

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

func orbitPath(_ orbit: Orbit) -> CGPath {
    var transform = CGAffineTransform(translationX: orbitCenter.x, y: orbitCenter.y)
        .rotated(by: orbit.angle * .pi / 180)
    let box = CGRect(
        x: -orbitRadiusX,
        y: -orbitRadiusY,
        width: orbitRadiusX * 2,
        height: orbitRadiusY * 2
    )
    return CGPath(ellipseIn: box, transform: &transform)
}

// The orbits pass in front of the glass below their centre and behind it above
func halfPlane(front: Bool) -> CGRect {
    let overlap: CGFloat = 6
    return front
        ? CGRect(x: 0, y: 0, width: canvas, height: orbitCenter.y + overlap)
        : CGRect(x: 0, y: orbitCenter.y - overlap, width: canvas, height: canvas - orbitCenter.y + overlap)
}

func bowlPath() -> CGPath {
    let left = center.x - bowlHalfWidth
    let right = center.x + bowlHalfWidth
    let path = CGMutablePath()
    path.move(to: CGPoint(x: left, y: rimY))
    path.addLine(to: CGPoint(x: right, y: rimY))
    path.addCurve(
        to: CGPoint(x: center.x, y: bowlBottom),
        control1: CGPoint(x: right + 6, y: rimY - bowlDepth * 0.62),
        control2: CGPoint(x: center.x + bowlHalfWidth * 0.62, y: bowlBottom)
    )
    path.addCurve(
        to: CGPoint(x: left, y: rimY),
        control1: CGPoint(x: center.x - bowlHalfWidth * 0.62, y: bowlBottom),
        control2: CGPoint(x: left - 6, y: rimY - bowlDepth * 0.62)
    )
    path.closeSubpath()
    return path
}

func winePath() -> CGPath {
    let surface = rimY - bowlDepth * wineLevel
    let half = bowlHalfWidth * (1 - pow(wineLevel, 2.2) * 0.18)
    let bottom = bowlBottom + 4
    let shoulder = surface - (surface - bottom) * 0.55
    let path = CGMutablePath()
    path.move(to: CGPoint(x: center.x - half, y: surface))
    path.addLine(to: CGPoint(x: center.x + half, y: surface))
    path.addCurve(
        to: CGPoint(x: center.x, y: bottom),
        control1: CGPoint(x: center.x + half, y: shoulder),
        control2: CGPoint(x: center.x + bowlHalfWidth * 0.6, y: bottom)
    )
    path.addCurve(
        to: CGPoint(x: center.x - half, y: surface),
        control1: CGPoint(x: center.x - bowlHalfWidth * 0.6, y: bottom),
        control2: CGPoint(x: center.x - half, y: shoulder)
    )
    path.closeSubpath()
    return path
}

// The glass outline, stem and base, thickened by grow for knockouts
func fillGlass(grownBy grow: CGFloat, in context: CGContext) {
    let width = glassStroke + grow
    context.setLineWidth(width)
    context.setLineJoin(.round)
    context.addPath(bowlPath())
    context.strokePath()
    context.fill(CGRect(x: center.x - width / 2, y: stemBottom, width: width, height: stemLength))
    let base = CGRect(
        x: center.x - baseHalfWidth - grow / 2,
        y: stemBottom - width / 2,
        width: baseHalfWidth * 2 + grow,
        height: width
    )
    context.addPath(CGPath(roundedRect: base, cornerWidth: width / 2, cornerHeight: width / 2, transform: nil))
    context.fillPath()
}

func strokeOrbit(_ orbit: Orbit, front: Bool, width: CGFloat, in context: CGContext) {
    context.saveGState()
    context.clip(to: halfPlane(front: front))
    context.setLineWidth(width)
    context.addPath(orbitPath(orbit))
    context.strokePath()
    context.restoreGState()
}

func cutFrontOrbits(from context: CGContext) {
    context.saveGState()
    context.setBlendMode(.clear)
    for orbit in Orbit.allCases {
        strokeOrbit(orbit, front: true, width: orbitStroke + knockoutGap * 2, in: context)
    }
    context.restoreGState()
}

func draw(_ element: Element, into context: CGContext) {
    context.setStrokeColor(white)
    context.setFillColor(white)

    switch element {
    case .orbitBack(let orbit):
        strokeOrbit(orbit, front: false, width: orbitStroke, in: context)
        context.setBlendMode(.clear)
        fillGlass(grownBy: knockoutGap * 2, in: context)
        context.addPath(bowlPath())
        context.fillPath()
        context.setBlendMode(.normal)

    case .wine:
        context.addPath(winePath())
        context.fillPath()
        context.setBlendMode(.clear)
        fillGlass(grownBy: 0, in: context)
        context.setBlendMode(.normal)
        cutFrontOrbits(from: context)

    case .glass:
        fillGlass(grownBy: 0, in: context)
        cutFrontOrbits(from: context)

    case .orbitFront(let orbit):
        strokeOrbit(orbit, front: true, width: orbitStroke, in: context)
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

func iconGroup(_ group: Group) -> [String: Any] {
    [
        "blur-material": NSNull(),
        "layers": group.elements.reversed().map { element -> [String: Any] in
            [
                "fill": ["solid": element.fill],
                "image-name": element.fileName,
                "name": element.name,
            ]
        },
        "name": group.name,
        "opacity": 1,
        "refractivity": ["depth": group.depth, "enabled": true, "strength": 0.005],
        "shadow": ["kind": "neutral", "opacity": 0.5],
        "specular": "inside",
        "translucency": ["enabled": true, "value": group.translucency],
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
            "srgb:0.16471,0.18431,0.41961,1.00000",
            "srgb:0.07059,0.05882,0.18039,1.00000",
        ]
    ],
    "groups": groups.reversed().map(iconGroup),
    "supported-platforms": ["circles": ["watchOS"], "squares": "shared"],
]
try JSONSerialization
    .data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
    .write(to: root.appendingPathComponent("icon.json"))
