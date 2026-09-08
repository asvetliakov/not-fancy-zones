import AppKit

/// Opt-in reproduction of apps that expose AXWindows but no hit-test element.
final class FixtureApplication: NSApplication {
    private let disableHitTest = ProcessInfo.processInfo.environment["NFZ_FIXTURE_NO_HIT_TEST"] == "1"
    override func accessibilityHitTest(_ point: NSPoint) -> Any? {
        disableHitTest ? nil : super.accessibilityHitTest(point)
    }
}

final class FixtureDelegate: NSObject, NSApplicationDelegate {
    var windows: [NSWindow] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSWindow.allowsAutomaticWindowTabbing = false
        let screen = NSScreen.screens[0].visibleFrame
        for index in 0..<2 {
            let window = NSWindow(contentRect: NSRect(x: screen.minX + 60 + CGFloat(index * 40), y: screen.midY - 160 - CGFloat(index * 40), width: 520, height: 320),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = index == 0 ? "NFZ Test — Resizable" : "NFZ Test — Minimum Size"
            window.tabbingMode = .disallowed
            window.setAccessibilityIdentifier("nfz-fixture-\(index)")
            window.minSize = index == 0 ? NSSize(width: 120, height: 100) : NSSize(width: 600, height: 450)
            window.isReleasedWhenClosed = false
            let label = NSTextField(labelWithString: "Not Fancy Zones test window\nDrag this title bar while holding Shift.\nThis fixture contains no user data.")
            label.frame = NSRect(x: 24, y: 140, width: 450, height: 100)
            window.contentView?.addSubview(label)
            window.makeKeyAndOrderFront(nil); windows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeKeyAndOrderFront(nil)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
let app = FixtureApplication.shared
let delegate = FixtureDelegate()
app.delegate = delegate
app.run()
