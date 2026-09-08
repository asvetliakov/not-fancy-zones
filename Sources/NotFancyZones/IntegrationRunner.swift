import AppKit
import ApplicationServices
import ZonesCore

/// Opt-in tests operate only on a throwaway fixture app, with isolated preferences.
final class IntegrationRunner {
    let state: AppState
    let coordinator: WindowCoordinator
    let output: URL
    let fixture: URL
    var process: Process?
    var results: [[String: Any]] = []
    init(state: AppState, coordinator: WindowCoordinator, output: URL, fixture: URL) {
        self.state = state; self.coordinator = coordinator; self.output = output; self.fixture = fixture
    }

    func run() {
        guard AXIsProcessTrusted() else {
            record("Accessibility permission", false, "Enable the built Not Fancy Zones app in System Settings, then rerun scripts/e2e.sh.")
            finish(); return
        }
        coordinator.checkPermission()
        let process = Process(); process.executableURL = fixture
        do { try process.run(); self.process = process }
        catch { record("Launch fixture", false, error.localizedDescription); finish(); return }
        later(1.5) { self.scanFixture(attempt: 0) }
    }

    private func scanFixture(attempt: Int) {
        guard let process else { finish(); return }
        coordinator.accessibility.scan(pid: process.processIdentifier, bundleID: "app.notfancyzones.fixture") { windows in
            guard let window = windows.first(where: { $0.identity.title.contains("Resizable") }) else {
                if attempt < 4 { self.later(0.6) { self.scanFixture(attempt: attempt + 1) } }
                else { self.record("Discover fixture window", false, "AX did not expose the fixture."); self.finish() }
                return
            }
            self.record("Discover fixture window", true)
            self.record("Both independent fixture windows are exposed", windows.count == 2, "Found \(windows.count) standard windows")
            self.testCancelledWork(window, allWindows: windows)
        }
    }

    private func testCancelledWork(_ window: AccessibleWindow, allWindows: [AccessibleWindow]) {
        let token = WorkToken(); token.cancel()
        let point = CGPoint(x: window.frame.midX, y: window.frame.minY + 12)
        coordinator.accessibility.window(at: point, token: token) { hit in
            self.record("Cancelled hit test returns no window", hit == nil)
            self.coordinator.accessibility.readFrame(window.element, token: token) { frame in
                self.record("Cancelled frame query returns no frame", frame == nil)
                self.coordinator.accessibility.fit(window, to: window.frame.offsetBy(dx: 100, dy: 100), token: token) { result in
                    self.coordinator.accessibility.readFrame(window.element) { actual in
                        self.record("Cancelled placement cannot move a window", !result.succeeded && actual.map { AccessibilityService.near($0, window.frame) } == true)
                        self.testDisplay(index: 0, window: window, allWindows: allWindows)
                    }
                }
            }
        }
    }

    private func testDisplay(index: Int, window: AccessibleWindow, allWindows: [AccessibleWindow]) {
        guard index < state.displays.count else { testMinimumSize(allWindows, window: window); return }
        let display = state.displays[index]
        let layout = GridLayout(columns: [34, 33, 33], rows: [50, 50], merges: [[0, 1, 3, 4]], outerMargin: 12, gap: 10)
        try? state.setLayout(layout, for: display.id)
        let zone = layout.zones(in: display.workArea)[0]
        coordinator.snap(window, to: ZoneTarget(displayID: display.id, zoneID: zone.id, frame: zone.frame)) { result in
            self.later(0.5) {
                self.coordinator.accessibility.readFrame(window.element) { actual in
                    self.record("Snap fills merged zone on \(display.name)", actual.map { AccessibilityService.near($0, zone.frame) } ?? false,
                                "expected \(zone.frame); actual \(String(describing: actual)); AX success \(result.succeeded)")
                    self.testDisplay(index: index + 1, window: window, allWindows: allWindows)
                }
            }
        }
    }

    private func testMinimumSize(_ windows: [AccessibleWindow], window: AccessibleWindow) {
        guard let constrained = windows.first(where: { $0.identity.title.contains("Minimum Size") }), let display = state.displays.first else {
            record("App minimum-size test", false, "Missing independent constrained fixture window")
            testReconnect(window); return
        }
        let small = CGRect(x: display.workArea.minX + 25, y: display.workArea.minY + 25, width: 220, height: 180)
        coordinator.accessibility.fit(constrained, to: small) { result in
            self.record("App minimum size is respected without a resize loop", result.succeeded && !result.exact && (result.frame?.width ?? 0) >= 599)
            self.testReconnect(window)
        }
    }

    private func testReconnect(_ window: AccessibleWindow) {
        let original = state.displays
        guard original.count > 1, let external = original.max(by: { $0.frame.width < $1.frame.width }),
              let fallbackDisplay = original.first(where: { $0.id != external.id }) else {
            record("Simulated disconnect/reconnect", true, "Skipped: only one display connected."); testDrag(window); return
        }
        let zone = state.layout(for: external.id).zones(in: external.workArea)[0]
        coordinator.snap(window, to: ZoneTarget(displayID: external.id, zoneID: zone.id, frame: zone.frame)) { _ in
            self.state.displays = [fallbackDisplay]
            self.coordinator.restoreAll()
            self.later(0.8) {
                self.coordinator.accessibility.readFrame(window.element) { frame in
                    let fallback = self.state.layout(for: external.id).zones(in: fallbackDisplay.workArea)[0].frame
                    self.record("Simulated disconnect fits primary display", frame.map { AccessibilityService.near($0, fallback) } ?? false)
                    self.record("Disconnect preserves home monitor", self.state.preferences.placements.contains { $0.displayID == external.id })
                    self.state.displays = original; self.coordinator.restoreAll()
                    self.later(0.8) {
                        self.coordinator.accessibility.readFrame(window.element) { frame in
                            self.record("Simulated reconnect restores full zone", frame.map { AccessibilityService.near($0, zone.frame) } ?? false)
                            self.testDrag(window)
                        }
                    }
                }
            }
        }
    }

    private func testDrag(_ window: AccessibleWindow) {
        guard let display = state.displays.first else { finish(); return }
        // A small window leaves room to drag its title bar into either half.
        let initial = CGRect(x: display.workArea.minX + 35, y: display.workArea.minY + 75, width: 420, height: 270)
        coordinator.forgetAll()
        try? state.setLayout(GridLayout(columns: [50, 50], outerMargin: 8, gap: 8), for: display.id)
        coordinator.accessibility.fit(window, to: initial) { _ in
            NSRunningApplication(processIdentifier: window.pid)?.activate(options: [])
            self.later(0.5) {
                self.coordinator.accessibility.readFrame(window.element) { frame in
                    guard let frame else { self.record("Shift drag", false, "No fixture frame"); self.finish(); return }
                    let start = CGPoint(x: frame.minX + 160, y: frame.minY + 12)
                    if ProcessInfo.processInfo.environment["NFZ_FIXTURE_NO_HIT_TEST"] == "1" {
                        var hit: AXUIElement?
                        let error = AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(start.x), Float(start.y), &hit)
                        self.record("Fixture reproduces unavailable AX hit testing", error == .notImplemented && hit == nil, "AX error \(error.rawValue); hit present \(hit != nil)")
                    }
                    let zones = self.state.layout(for: display.id).zones(in: display.workArea)
                    let destination = CGPoint(x: zones[1].hitFrame.midX, y: zones[1].hitFrame.midY)
                    self.post(.mouseMoved, point: start)
                    self.post(.leftMouseDown, point: start)
                    self.dragStep(0, start: start, end: destination) {
                        self.record("Shift drag shows overlay", self.coordinator.overlay.visible)
                        self.record("Overlay covers every connected monitor", self.coordinator.overlay.panelCount == self.state.displays.count)
                        self.post(.leftMouseUp, point: destination, shift: true)
                        self.later(0.8) {
                            self.coordinator.accessibility.readFrame(window.element) { actual in
                                self.record("Shift drop fills target zone", actual.map { AccessibilityService.near($0, zones[1].frame) } ?? false,
                                            "expected \(zones[1].frame); actual \(String(describing: actual))")
                                self.record("Overlay closes after drop", !self.coordinator.overlay.visible)
                                self.record("No overlay panels remain allocated", self.coordinator.overlay.panelCount == 0)
                                self.record("Snapped placement persists", self.state.preferences.placements.count == 1)
                                self.testContentDrag(window, expected: zones[1].frame)
                            }
                        }
                    }
                }
            }
        }
    }

    private func testContentDrag(_ window: AccessibleWindow, expected: CGRect) {
        let start = CGPoint(x: expected.minX + 180, y: expected.minY + 130)
        let end = CGPoint(x: start.x + 120, y: start.y + 100)
        post(.leftMouseDown, point: start)
        dragStep(0, start: start, end: end) {
            self.record("Content drag does not show zones", !self.coordinator.overlay.visible)
            self.post(.leftMouseUp, point: end, shift: true)
            self.later(0.5) {
                self.coordinator.accessibility.readFrame(window.element) { frame in
                    self.record("Content drag does not move the window", frame.map { AccessibilityService.near($0, expected) } ?? false)
                    self.testRelaunch(expected: expected)
                }
            }
        }
    }

    private func testRelaunch(expected: CGRect) {
        process?.terminate()
        later(0.8) {
            let next = Process(); next.executableURL = self.fixture
            do { try next.run(); self.process = next }
            catch { self.record("Relaunch fixture", false, error.localizedDescription); self.finish(); return }
            self.later(2) {
                self.coordinator.accessibility.scan(pid: next.processIdentifier, bundleID: "app.notfancyzones.fixture") { windows in
                    guard let window = windows.first(where: { $0.identity.title.contains("Resizable") }) else {
                        self.record("Restore after app relaunch", false, "Window missing"); self.finish(); return
                    }
                    self.record("Restore after app relaunch fills remembered zone", AccessibilityService.near(window.frame, expected),
                                "expected \(expected); actual \(window.frame)")
                    self.testReleaseShift(window)
                }
            }
        }
    }

    private func testReleaseShift(_ window: AccessibleWindow) {
        let frame = window.frame
        let start = CGPoint(x: frame.minX + 180, y: frame.minY + 12)
        let end = CGPoint(x: start.x - 250, y: start.y + 130)
        post(.leftMouseDown, point: start)
        dragStep(0, start: start, end: end, releaseAt: 18) {
            self.record("Releasing Shift hides zones during the drag", !self.coordinator.overlay.visible)
            self.post(.leftMouseUp, point: end)
            self.later(0.6) {
                self.coordinator.accessibility.readFrame(window.element) { actual in
                    self.record("Ordinary drop releases remembered assignment", self.state.preferences.placements.isEmpty)
                    self.record("Ordinary drop retains the manually moved size", actual.map { abs($0.width - frame.width) < 2 && abs($0.height - frame.height) < 2 && $0.minX < frame.minX - 100 } ?? false)
                    self.finish()
                }
            }
        }
    }

    private func dragStep(_ step: Int, start: CGPoint, end: CGPoint, releaseAt: Int? = nil, completion: @escaping () -> Void) {
        guard step <= 24 else { completion(); return }
        let fraction = CGFloat(step) / 24
        post(.leftMouseDragged, point: CGPoint(x: start.x + (end.x - start.x) * fraction, y: start.y + (end.y - start.y) * fraction), shift: step >= 4 && step < (releaseAt ?? 25))
        later(0.045) { self.dragStep(step + 1, start: start, end: end, releaseAt: releaseAt, completion: completion) }
    }

    private func post(_ type: CGEventType, point: CGPoint, shift: Bool = false) {
        let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
        event?.flags = shift ? .maskShift : []
        if type == .leftMouseDown || type == .leftMouseUp { event?.setIntegerValueField(.mouseEventClickState, value: 1) }
        event?.post(tap: .cghidEventTap)
    }
    private func later(_ delay: Double, _ body: @escaping () -> Void) { DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: body) }
    private func record(_ name: String, _ passed: Bool, _ detail: String = "") {
        results.append(["name": name, "passed": passed, "detail": detail])
    }
    private func finish() {
        coordinator.cancelDrag(); process?.terminate(); state.flush()
        let report: [String: Any] = ["passed": results.allSatisfy { $0["passed"] as? Bool == true }, "checks": results,
            "displays": state.displays.map { ["name": $0.name, "frame": "\($0.frame)", "workArea": "\($0.workArea)"] }]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: output, options: .atomic)
        }
        NSApp.terminate(nil)
    }
}
