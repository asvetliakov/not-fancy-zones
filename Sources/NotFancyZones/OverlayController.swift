import AppKit
import ZonesCore

struct ZoneTarget: Equatable {
    var displayID: String
    var zoneID: String
    var frame: CGRect
}

final class OverlayController {
    private var panels: [String: NSPanel] = [:]
    private var views: [String: OverlayView] = [:]
    private(set) var visible = false
    var panelCount: Int { panels.count }
    private var highlighted: ZoneTarget?

    func show(displays: [DisplayInfo], layout: (String) -> GridLayout) {
        guard !visible else { return }
        visible = true
        for display in displays {
            let panel = NSPanel(contentRect: display.appKitFrame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
            panel.isOpaque = false; panel.backgroundColor = .clear
            panel.hasShadow = false; panel.ignoresMouseEvents = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
            panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
            let zones = layout(display.id).zones(in: display.workArea)
            let view = OverlayView(frame: CGRect(origin: .zero, size: display.frame.size))
            view.zones = zones.map { zone in
                Zone(cells: zone.cells, frame: zone.frame.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY),
                     hitFrame: zone.hitFrame.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY))
            }
            panel.contentView = view
            panels[display.id] = panel; views[display.id] = view
            panel.orderFrontRegardless()
        }
    }

    func highlight(_ target: ZoneTarget?) {
        guard target != highlighted else { return }
        if let old = highlighted { views[old.displayID]?.highlightedID = nil }
        highlighted = target
        if let target { views[target.displayID]?.highlightedID = target.zoneID }
    }

    func hide() {
        guard visible else { return }
        for panel in panels.values { panel.orderOut(nil); panel.close() }
        panels.removeAll(); views.removeAll(); highlighted = nil; visible = false
    }
}

private final class OverlayView: NSView {
    override var isFlipped: Bool { true }
    var zones: [Zone] = []
    var highlightedID: String? { didSet { if oldValue != highlightedID { needsDisplay = true } } }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill(); dirtyRect.fill(using: .copy)
        for (index, zone) in zones.enumerated() {
            let selected = zone.id == highlightedID
            let path = NSBezierPath(roundedRect: zone.frame.insetBy(dx: 1.5, dy: 1.5), xRadius: 10, yRadius: 10)
            NSColor.controlAccentColor.withAlphaComponent(selected ? 0.30 : 0.09).setFill(); path.fill()
            NSColor.controlAccentColor.withAlphaComponent(selected ? 0.95 : 0.55).setStroke()
            path.lineWidth = selected ? 3 : 1.5; path.stroke()
            let text = "\(index + 1)" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 26, weight: .semibold),
                .foregroundColor: NSColor.white
            ]
            let size = text.size(withAttributes: attributes)
            let badge = CGRect(x: zone.frame.midX - max(48, size.width + 24) / 2, y: zone.frame.midY - 24,
                               width: max(48, size.width + 24), height: 48)
            NSColor.controlAccentColor.withAlphaComponent(selected ? 1 : 0.8).setFill()
            NSBezierPath(roundedRect: badge, xRadius: 12, yRadius: 12).fill()
            text.draw(at: CGPoint(x: badge.midX - size.width / 2, y: badge.midY - size.height / 2), withAttributes: attributes)
        }
    }
}
