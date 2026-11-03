// Draws the disk image window's background at 1x and 2x from layout.json (#558). DRAFT art, for the owner's approval.
//
//   swift scripts/dmg/background.swift scripts/dmg/layout.json scripts/dmg
//
// writes background.png (1x) and background@2x.png beside the layout. Commit both with any change to this file or
// the layout; scripts/tests/test_dmg_layout.py checks their sizes against the layout. Colours are the website's
// light tokens (cachedrop-website handoff/design-system/tokens.css): Finder shows the same picture in light and dark.
import AppKit

struct Layout: Decodable {
    struct Size: Decodable { let width: Double; let height: Double }
    struct Item: Decodable { let name: String; let x: Double; let y: Double }
    struct Instruction: Decodable { let text: String; let y: Double; let pointSize: Double }
    let window: Size
    let iconSize: Double
    let app: Item
    let applications: Item
    let instruction: Instruction
    let colors: [String: String]
}

func color(_ hex: String) -> NSColor {
    let value = UInt32(hex.dropFirst(), radix: 16) ?? 0
    return NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                   blue: CGFloat(value & 0xFF) / 255, alpha: 1)
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write("usage: background.swift LAYOUT.json OUTPUT_DIR\n".data(using: .utf8)!)
    exit(2)
}
let layout = try JSONDecoder().decode(Layout.self, from: Data(contentsOf: URL(fileURLWithPath: arguments[1])))
let output = URL(fileURLWithPath: arguments[2])

func draw() {
    let width = layout.window.width, height = layout.window.height
    // Finder's coordinates run from the top left; AppKit's from the bottom left.
    func flipped(_ y: Double) -> Double { height - y }

    color(layout.colors["surface"]!).setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()

    // The arrow from the app towards Applications, clear of both icons.
    let gap = layout.iconSize / 2 + 28
    let startX = layout.app.x + gap, endX = layout.applications.x - gap, arrowY = flipped(layout.app.y)
    let head = 12.0
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: startX, y: arrowY))
    arrow.line(to: NSPoint(x: endX, y: arrowY))
    arrow.move(to: NSPoint(x: endX - head, y: arrowY + head))
    arrow.line(to: NSPoint(x: endX, y: arrowY))
    arrow.line(to: NSPoint(x: endX - head, y: arrowY - head))
    arrow.lineWidth = 4
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    color(layout.colors["accent"]!).setStroke()
    arrow.stroke()

    // The one line of instruction, centred above the icons.
    let font = NSFont.systemFont(ofSize: layout.instruction.pointSize, weight: .semibold)
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let text = NSAttributedString(string: layout.instruction.text, attributes: [
        .font: font, .foregroundColor: color(layout.colors["ink"]!), .paragraphStyle: paragraph,
    ])
    let lineHeight = text.size().height
    text.draw(in: NSRect(x: 0, y: flipped(layout.instruction.y) - lineHeight / 2, width: width, height: lineHeight))
}

for (scale, name) in [(1.0, "background.png"), (2.0, "background@2x.png")] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(layout.window.width * scale),
                               pixelsHigh: Int(layout.window.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
                               bitsPerPixel: 0)!
    rep.size = NSSize(width: layout.window.width, height: layout.window.height) // 72 dpi at 1x, 144 at 2x
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
}
