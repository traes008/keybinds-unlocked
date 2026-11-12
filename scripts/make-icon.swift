// Draws an app icon at 1024x1024 following the macOS icon grid (824pt rounded square, 100pt margin).
// Usage: make-icon <docksnug|keybinds> <output.png>
import AppKit

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}
func rounded(_ rect: NSRect, _ radius: CGFloat) -> NSBezierPath { NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius) }

func background(top: UInt32, bottom: UInt32) {
    let plate = rounded(NSRect(x: 100, y: 100, width: 824, height: 824), 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.shadowBlurRadius = 20
    shadow.set()
    color(bottom).setFill()
    plate.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: color(top), ending: color(bottom))!.draw(in: plate, angle: -90)
}

func softShadow(_ draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    shadow.shadowOffset = NSSize(width: 0, height: -8)
    shadow.shadowBlurRadius = 24
    shadow.set()
    draw()
    NSGraphicsContext.restoreGraphicsState()
}

/// A window sitting snugly on top of a Dock.
func dockSnug() {
    background(top: 0x58A8FF, bottom: 0x1F58D6)

    let dock = NSRect(x: 262, y: 226, width: 500, height: 96)
    color(0xFFFFFF, 0.32).setFill()
    rounded(dock, 30).fill()
    let tiles: [UInt32] = [0xFF6B5E, 0xFFC542, 0x3DDC84, 0xFFFFFF, 0xB98CFF]
    for (index, tile) in tiles.enumerated() {
        color(tile).setFill()
        rounded(NSRect(x: dock.minX + 30 + CGFloat(index) * 92, y: dock.minY + 18, width: 60, height: 60), 16).fill()
    }

    let window = NSRect(x: 222, y: dock.maxY + 10, width: 580, height: 446)
    softShadow {
        color(0xFFFFFF).setFill()
        rounded(window, 40).fill()
    }
    NSGraphicsContext.saveGraphicsState()
    rounded(window, 40).addClip()
    color(0xE6ECF7).setFill()
    NSRect(x: window.minX, y: window.maxY - 84, width: window.width, height: 84).fill()
    NSGraphicsContext.restoreGraphicsState()
    for (index, light) in ([0xFF5F57, 0xFEBC2E, 0x28C840] as [UInt32]).enumerated() {
        color(light).setFill()
        NSBezierPath(ovalIn: NSRect(x: window.minX + 40 + CGFloat(index) * 50, y: window.maxY - 58, width: 32, height: 32)).fill()
    }
    color(0xD5DDEC).setFill()
    for (index, width) in ([400, 320, 360] as [CGFloat]).enumerated() {
        rounded(NSRect(x: window.minX + 50, y: window.maxY - 160 - CGFloat(index) * 70, width: width, height: 28), 14).fill()
    }
}

/// A keycap with the Command symbol and an open padlock.
func keybinds() {
    background(top: 0x4A5162, bottom: 0x1D2029)

    let side = NSRect(x: 232, y: 236, width: 560, height: 540)
    softShadow {
        color(0xA9B0BF).setFill()
        rounded(side, 96).fill()
    }
    let face = NSRect(x: 232, y: 286, width: 560, height: 500)
    NSGradient(starting: color(0xFFFFFF), ending: color(0xE4E8F0))!.draw(in: rounded(face, 96), angle: -90)

    let symbol = NSAttributedString(string: "⌘", attributes: [
        .font: NSFont.systemFont(ofSize: 330, weight: .semibold), .foregroundColor: color(0x262A33),
    ])
    let size = symbol.size()
    symbol.draw(at: NSPoint(x: face.midX - size.width / 2, y: face.midY - size.height / 2))

    let badge = NSRect(x: 628, y: 170, width: 220, height: 220)
    softShadow {
        color(0xFFC53D).setFill()
        NSBezierPath(ovalIn: badge).fill()
    }
    let configuration = NSImage.SymbolConfiguration(pointSize: 110, weight: .bold).applying(.init(paletteColors: [color(0x3A2A00)]))
    if let lock = NSImage(systemSymbolName: "lock.open.fill", accessibilityDescription: nil)?.withSymbolConfiguration(configuration) {
        let lockSize = lock.size
        lock.draw(in: NSRect(x: badge.midX - lockSize.width / 2 + 6, y: badge.midY - lockSize.height / 2, width: lockSize.width, height: lockSize.height))
    }
}

let arguments = CommandLine.arguments
guard arguments.count == 3, ["docksnug", "keybinds"].contains(arguments[1]) else {
    print("usage: make-icon <docksnug|keybinds> <output.png>")
    exit(1)
}
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4,
                              hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
arguments[1] == "docksnug" ? dockSnug() : keybinds()
NSGraphicsContext.current?.flushGraphics()
try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: arguments[2]))
