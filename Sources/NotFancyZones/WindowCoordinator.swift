import AppKit
import ApplicationServices
import ZonesCore

private final class ManagedWindow {
    var window: AccessibleWindow
    var placement: Placement
    var lastTarget: CGRect?
    var applying = false
    init(window: AccessibleWindow, placement: Placement) { self.window = window; self.placement = placement }
}

final class WindowCoordinator {
    let state: AppState
    let accessibility = AccessibilityService()
    let overlay = OverlayController()
    private var monitor: Any?
    private var notificationTokens: [NSObjectProtocol] = []
    private var scanJobs: [pid_t: DispatchWorkItem] = [:]
    private var managed: [ManagedWindow] = []
    private var topologyJob: DispatchWorkItem?
    private var topologyGeneration = 0
    private var started = false
    private var dragID = UUID()
    private var dragWork = WorkToken()
    private var mouseDown = false
    private var dragWindow: AccessibleWindow?
    private var isMoving = false
    private var isChecking = false
    private var lastCheck: TimeInterval = 0
    private var startPoint = CGPoint.zero
    private var pointer = CGPoint.zero
    private var shiftHeld = false
    private var didDrag = false
    private var target: ZoneTarget?
    private var previewJob: DispatchWorkItem?
    private var restoreAfterDrag = false
    private var placementToken = WorkToken()
    private var geometry: [(display: DisplayInfo, zones: [Zone])] = []
    private var scansInFlight = Set<pid_t>()
    private var scanAgain = Set<pid_t>()

    init(state: AppState) {
        self.state = state
        state.onLayoutChanged = { [weak self] in self?.layoutsChanged() }
        accessibility.onNotification = { [weak self] pid, name, element in
            guard let self else { return }
            if name == kAXUIElementDestroyedNotification {
                self.managed.removeAll { CFEqual($0.window.element, element) }
            }
            self.scheduleScan(pid: pid)
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didActivateApplicationNotification] {
            notificationTokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                self?.scheduleScan(pid: app.processIdentifier)
            })
        }
        notificationTokens.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.managed.removeAll { $0.window.pid == app.processIdentifier }
            self?.accessibility.remove(pid: app.processIdentifier)
            self?.scanJobs.removeValue(forKey: app.processIdentifier)?.cancel()
        })
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            notificationTokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.screensChanged() })
        }
        notificationTokens.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.screensChanged() })
    }

    func checkPermission(prompt: Bool = false) {
        let granted = prompt
            ? AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
            : AXIsProcessTrusted()
        applyPermission(granted)
    }

    func recheckPermission() {
        guard !state.checkingAccessibility else { return }
        state.checkingAccessibility = true
        state.permissionFeedback = "Checking macOS Accessibility permission…"
        // A single user-triggered query; no permission polling timer.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let granted = AXIsProcessTrusted()
            DispatchQueue.main.async {
                guard let self else { return }
                self.applyPermission(granted)
                self.state.checkingAccessibility = false
                self.state.permissionCheckedAt = Date().formatted(date: .omitted, time: .standard)
                self.state.permissionFeedback = granted
                    ? "Accessibility is enabled. Shift-drag snapping is ready."
                    : "macOS still reports no access for this running copy. If its switch is already on, restart the app. If access is still denied, remove the old entry and add the exact app shown below."
            }
        }
    }

    private func applyPermission(_ granted: Bool) {
        let changed = state.accessibilityGranted != granted
        state.accessibilityGranted = granted
        if granted {
            start()
            if changed { state.permissionFeedback = "Accessibility is enabled. Shift-drag snapping is ready." }
        } else {
            if changed { state.permissionFeedback = "macOS no longer recognizes Accessibility access for this running copy. Restart the app and check its entry in System Settings." }
            if started || monitor != nil {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil; started = false; cancelDrag()
                for job in scanJobs.values { job.cancel() }; scanJobs.removeAll()
                accessibility.removeAll()
            }
        }
    }

    private func start() {
        guard !started else { return }
        started = true
        rebuildGeometry()
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .flagsChanged]) { [weak self] in self?.handle($0) }
        scanAll()
    }

    private var currentPoint: CGPoint {
        let point = NSEvent.mouseLocation
        return CGPoint(x: point.x, y: (NSScreen.screens.first?.frame.height ?? 0) - point.y)
    }

    private func handle(_ event: NSEvent) {
        guard !state.paused else { cancelDrag(); return }
        pointer = currentPoint; shiftHeld = event.modifierFlags.contains(.shift)
        switch event.type {
        case .leftMouseDown:
            cancelDrag()
            previewJob?.cancel(); overlay.hide()
            mouseDown = true; startPoint = pointer; lastCheck = 0
            let token = dragID
            accessibility.window(at: pointer, token: dragWork) { [weak self] window in
                guard let self, self.dragID == token, self.mouseDown else { return }
                self.dragWindow = window
                if self.didDrag { self.checkMovement() }
            }
        case .leftMouseDragged:
            guard mouseDown else { return }
            didDrag = true
            if isMoving { updateOverlay() } else { checkMovement() }
        case .flagsChanged:
            if mouseDown && isMoving { updateOverlay() }
        case .leftMouseUp:
            finishDrag()
        default: break
        }
    }

    private func checkMovement() {
        guard !isChecking, let window = dragWindow, !window.minimized, !window.fullScreen,
              ProcessInfo.processInfo.systemUptime - lastCheck >= 1.0 / 15 else { return }
        isChecking = true; lastCheck = ProcessInfo.processInfo.systemUptime
        let token = dragID
        accessibility.readFrame(window.element, token: dragWork) { [weak self] frame in
            guard let self, self.dragID == token, self.mouseDown else { return }
            self.isChecking = false
            if let frame, self.isTranslation(from: window.frame, to: frame) {
                self.isMoving = true; self.updateOverlay()
            }
        }
    }

    private func isTranslation(from original: CGRect, to current: CGRect) -> Bool {
        DragMotion.isTranslation(from: original, to: current)
    }

    private func updateOverlay() {
        guard shiftHeld else { overlay.hide(); target = nil; return }
        overlay.show(displays: state.displays, layout: state.layout)
        target = targetAt(pointer)
        overlay.highlight(target)
    }

    func targetAt(_ point: CGPoint) -> ZoneTarget? {
        if geometry.isEmpty { rebuildGeometry() }
        guard let cached = geometry.first(where: { $0.display.workArea.contains(point) }) else { return nil }
        let display = cached.display, zones = cached.zones
        // Screen-edge margins select the nearest zone too.
        let zone = zones.first(where: { $0.hitFrame.contains(point) }) ?? zones.min {
            distance(point, to: $0.hitFrame) < distance(point, to: $1.hitFrame)
        }
        return zone.map { ZoneTarget(displayID: display.id, zoneID: $0.id, frame: $0.frame) }
    }

    private func distance(_ point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }

    private func finishDrag() {
        guard mouseDown else { return }
        let window = dragWindow, moved = isMoving, dragged = didDrag
        let droppedTarget = shiftHeld ? targetAt(pointer) : nil
        let token = dragID
        mouseDown = false; overlay.hide()
        guard let window, dragged else { cancelDrag(); return }
        // This final check also catches very quick drags and native edge tiling on release.
        accessibility.readFrame(window.element, token: dragWork) { [weak self] frame in
            guard let self, self.dragID == token else { return }
            let translated = frame.map { self.isTranslation(from: window.frame, to: $0) } ?? false
            if moved || translated {
                if let droppedTarget { self.snap(window, to: droppedTarget) }
                else { self.forget(window) }
            } else if let frame, !AccessibilityService.near(frame, window.frame) {
                // An intentional resize also releases the saved assignment.
                self.forget(window)
            }
            self.cancelDrag(invalidatePlacements: false)
            if self.restoreAfterDrag { self.restoreAfterDrag = false; self.restoreAll(force: true) }
        }
    }

    func cancelDrag(invalidatePlacements: Bool = true) {
        dragWork.cancel(); dragWork = WorkToken()
        if invalidatePlacements { placementToken.cancel(); placementToken = WorkToken() }
        dragID = UUID(); mouseDown = false; dragWindow = nil; isMoving = false
        isChecking = false; didDrag = false; target = nil; overlay.hide()
    }

    func preview() {
        cancelDrag(); previewJob?.cancel()
        overlay.show(displays: state.displays, layout: state.layout)
        let job = DispatchWorkItem { [weak self] in self?.overlay.hide() }
        previewJob = job; DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: job)
    }

    func snap(_ window: AccessibleWindow, to target: ZoneTarget, completion: ((FitResult) -> Void)? = nil) {
        let token = placementToken
        accessibility.fit(window, to: target.frame, token: token) { [weak self] result in
            guard let self, token.isValid else { completion?(FitResult(frame: nil, succeeded: false, exact: false)); return }
            if result.succeeded {
                let existing = self.managed.first { CFEqual($0.window.element, window.element) }
                let placement = Placement(id: existing?.placement.id ?? UUID(), window: window.identity, displayID: target.displayID, zoneID: target.zoneID)
                let entry = existing ?? ManagedWindow(window: window, placement: placement)
                entry.placement = placement; entry.lastTarget = target.frame
                if existing == nil { self.managed.append(entry) }
                self.state.remember(placement)
                self.scheduleScan(pid: window.pid)
                self.state.status = result.exact ? "Window snapped. Its monitor and zone are remembered." : "Window placed. This app limits its window size."
                // A single delayed correction handles applications that asynchronously settle their size.
                self.verifyFit(entry, target: target.frame)
            } else { self.state.status = "This window could not be moved or resized. It may be full-screen or protected by the app." }
            completion?(result)
        }
    }

    private func verifyFit(_ entry: ManagedWindow, target: CGRect) {
        let generation = topologyGeneration
        let token = placementToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self, weak entry] in
            guard let self, let entry, token.isValid, !self.mouseDown, !self.state.paused,
                  self.topologyGeneration == generation, entry.lastTarget == target,
                  self.managed.contains(where: { $0 === entry }) else { return }
            self.accessibility.readFrame(entry.window.element, token: token) { [weak self, weak entry] frame in
                guard let self, let entry, token.isValid, !self.mouseDown, entry.lastTarget == target,
                      self.managed.contains(where: { $0 === entry }),
                      let frame, !AccessibilityService.near(frame, target) else { return }
                self.accessibility.fit(entry.window, to: target, token: token) { _ in }
            }
        }
    }

    private func forget(_ window: AccessibleWindow) {
        let entries = managed.filter { CFEqual($0.window.element, window.element) }
        for entry in entries { state.forget(entry.placement.id) }
        managed.removeAll { CFEqual($0.window.element, window.element) }
        if !state.preferences.placements.contains(where: { $0.window.bundleID == window.identity.bundleID }) {
            accessibility.remove(pid: window.pid)
            scanJobs.removeValue(forKey: window.pid)?.cancel()
        }
    }

    func forgetAll() {
        placementToken.cancel(); placementToken = WorkToken()
        managed.removeAll(); state.preferences.placements.removeAll(); state.save()
        for job in scanJobs.values { job.cancel() }; scanJobs.removeAll()
        accessibility.removeAll()
    }

    private func scheduleScan(pid: pid_t) {
        guard started, !state.paused, state.preferences.restoreWindows,
              pid != ProcessInfo.processInfo.processIdentifier,
              let bundle = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier,
              state.preferences.placements.contains(where: { $0.window.bundleID == bundle }) else { return }
        scanJobs[pid]?.cancel()
        let job = DispatchWorkItem { [weak self] in self?.scanJobs.removeValue(forKey: pid); self?.scan(pid: pid) }
        scanJobs[pid] = job
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: job)
    }

    func scanAll() {
        guard started, !state.paused, state.preferences.restoreWindows else { return }
        let savedApps = Set(state.preferences.placements.map { $0.window.bundleID })
        guard !savedApps.isEmpty else { return }
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && savedApps.contains(app.bundleIdentifier ?? "") {
            scheduleScan(pid: app.processIdentifier)
        }
    }

    private func scan(pid: pid_t) {
        guard started, !state.paused, state.preferences.restoreWindows else { return }
        guard !scansInFlight.contains(pid) else { scanAgain.insert(pid); return }
        guard let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular,
              let bundleID = app.bundleIdentifier else { return }
        scansInFlight.insert(pid)
        accessibility.scan(pid: pid, bundleID: bundleID) { [weak self] windows in
            guard let self else { return }
            self.scansInFlight.remove(pid)
            if self.scanAgain.remove(pid) != nil { self.scheduleScan(pid: pid) }
            guard self.started, !self.state.paused, self.state.preferences.restoreWindows else { return }
            let identities = windows.map(\.identity)
            for window in windows {
                if let entry = self.managed.first(where: { CFEqual($0.window.element, window.element) }) {
                    entry.window = window
                    if entry.placement.window != window.identity {
                        entry.placement.window = window.identity; self.state.remember(entry.placement)
                    }
                    if entry.lastTarget == nil { self.restore(entry, force: false) }
                } else if self.state.preferences.restoreWindows,
                          let placement = PlacementMatcher.match(window.identity, candidates: identities, saved: self.state.preferences.placements),
                          !self.managed.contains(where: { $0.placement.id == placement.id }) {
                    let entry = ManagedWindow(window: window, placement: placement)
                    self.managed.append(entry); self.restore(entry, force: false)
                }
            }
        }
    }

    private func destination(for placement: Placement) -> ZoneTarget? {
        let display = state.displays.first { $0.id == placement.displayID } ?? state.displays.first
        guard let display else { return nil }
        // On disconnect, temporarily use the home layout on the primary screen. The home UUID is retained.
        let layout = state.layout(for: placement.displayID)
        let zones = layout.zones(in: display.workArea)
        let oldCells = Set(placement.zoneID.split(separator: "-").compactMap { Int($0) })
        let zone = zones.first { $0.id == placement.zoneID } ?? zones.max {
            Set($0.cells).intersection(oldCells).count < Set($1.cells).intersection(oldCells).count
        }
        return zone.map { ZoneTarget(displayID: display.id, zoneID: $0.id, frame: $0.frame) }
    }

    private func restore(_ entry: ManagedWindow, force: Bool) {
        guard started, state.preferences.restoreWindows, !state.paused else { return }
        guard !mouseDown else { restoreAfterDrag = true; return }
        guard !entry.applying, let target = destination(for: entry.placement),
              force || entry.lastTarget != target.frame else { return }
        guard !entry.window.minimized, !entry.window.fullScreen else { entry.lastTarget = nil; return }
        entry.applying = true
        let token = placementToken
        accessibility.fit(entry.window, to: target.frame, token: token) { [weak self, weak entry] result in
            guard let self, let entry else { return }
            entry.applying = false
            guard token.isValid else { entry.lastTarget = nil; return }
            if result.succeeded {
                entry.lastTarget = target.frame
                self.verifyFit(entry, target: target.frame)
            } else { entry.lastTarget = nil }
        }
    }

    func restoreAll(force: Bool = true) {
        guard started else { return }
        for entry in managed { restore(entry, force: force) }
        scanAll()
    }

    private func layoutsChanged() {
        cancelDrag(); topologyGeneration += 1; rebuildGeometry()
        restoreAll()
    }

    func restorationChanged() {
        if state.preferences.restoreWindows { restoreAll() }
        else {
            placementToken.cancel(); placementToken = WorkToken()
            for job in scanJobs.values { job.cancel() }; scanJobs.removeAll()
            accessibility.removeAll()
        }
    }

    private func screensChanged() {
        cancelDrag(); topologyGeneration += 1; topologyJob?.cancel()
        let job = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.state.refreshDisplays(); self.rebuildGeometry(); self.restoreAll()
            let generation = self.topologyGeneration
            // One bounded retry after macOS finishes its own window migration.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self, self.topologyGeneration == generation else { return }
                self.restoreAll()
            }
        }
        topologyJob = job
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: job)
    }

    private func rebuildGeometry() {
        geometry = state.displays.map { ($0, state.layout(for: $0.id).zones(in: $0.workArea)) }
    }
}
