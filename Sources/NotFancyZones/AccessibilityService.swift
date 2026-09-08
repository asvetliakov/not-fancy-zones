import AppKit
import ApplicationServices
import ZonesCore

struct AccessibleWindow {
    let element: AXUIElement
    let pid: pid_t
    let identity: WindowIdentity
    let frame: CGRect
    let minimized: Bool
    let fullScreen: Bool
}

struct FitResult {
    let frame: CGRect?
    let succeeded: Bool
    let exact: Bool
}

/// All cross-process AX messages run on one utility queue, never in a mouse callback or on the UI thread.
final class AccessibilityService {
    private let queue = DispatchQueue(label: "app.notfancyzones.accessibility", qos: .userInitiated)
    private var observers: [pid_t: AXObserver] = [:]
    private var watched: [pid_t: [AXUIElement]] = [:]
    var onNotification: ((pid_t, String, AXUIElement) -> Void)?
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    static func elementAttribute(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let position = attribute(element, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
              let size = attribute(element, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: point, size: dimensions)
    }

    static func snapshot(_ element: AXUIElement, bundleID: String, pid: pid_t) -> AccessibleWindow? {
        AXUIElementSetMessagingTimeout(element, 0.15)
        guard (attribute(element, kAXRoleAttribute) as? String) == kAXWindowRole,
              (attribute(element, kAXSubroleAttribute) as? String) == kAXStandardWindowSubrole,
              let frame = frame(element), frame.width > 0, frame.height > 0 else { return nil }
        return AccessibleWindow(element: element, pid: pid,
            identity: WindowIdentity(bundleID: bundleID,
                identifier: attribute(element, kAXIdentifierAttribute) as? String ?? "",
                document: attribute(element, kAXDocumentAttribute) as? String ?? "",
                title: attribute(element, kAXTitleAttribute) as? String ?? ""),
            frame: frame,
            minimized: attribute(element, kAXMinimizedAttribute) as? Bool ?? false,
            fullScreen: attribute(element, "AXFullScreen") as? Bool ?? false)
    }

    func window(at point: CGPoint, token: WorkToken? = nil, completion: @escaping (AccessibleWindow?) -> Void) {
        queue.async { [self] in
            guard token?.isValid != false else { DispatchQueue.main.async { completion(nil) }; return }
            let system = AXUIElementCreateSystemWide()
            AXUIElementSetMessagingTimeout(system, 0.15)
            var hit: AXUIElement?
            AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit)
            var result: AccessibleWindow?
            var resolvedWindow = false
            if let hit {
                let window = (Self.attribute(hit, kAXRoleAttribute) as? String) == kAXWindowRole ? hit : Self.elementAttribute(hit, kAXWindowAttribute)
                if let window {
                    resolvedWindow = true
                    var pid: pid_t = 0; AXUIElementGetPid(window, &pid)
                    if token?.isValid != false, pid != ownPID, let bundle = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier {
                        result = Self.snapshot(window, bundleID: bundle, pid: pid)
                    }
                }
            }
            // Some custom interfaces (including Telegram) expose AXWindows but return
            // AXError.notImplemented from hit testing. Never guess a focused/background window.
            if !resolvedWindow, token?.isValid != false { result = Self.windowFromWindowList(at: point, excludingPID: ownPID, token: token) }
            let resolved = result
            DispatchQueue.main.async { completion(token?.isValid == false ? nil : resolved) }
        }
    }

    /// One-shot fallback on the AX worker queue. Window-server metadata needs no
    /// screen capture; names/content are unused. Keep occluding panels in the list.
    static func windowFromWindowList(at point: CGPoint, excludingPID: pid_t, token: WorkToken? = nil) -> AccessibleWindow? {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        let candidates = info.compactMap { item -> WindowHitCandidate? in
            guard let bounds = item[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds),
                  let pid = item[kCGWindowOwnerPID as String] as? Int32,
                  let layer = item[kCGWindowLayer as String] as? Int else { return nil }
            return WindowHitCandidate(pid: pid, frame: frame, layer: layer,
                                      alpha: item[kCGWindowAlpha as String] as? Double ?? 1)
        }
        guard let candidate = WindowHitTesting.frontmost(at: point, in: candidates, excludingPID: excludingPID),
              let bundle = NSRunningApplication(processIdentifier: candidate.pid)?.bundleIdentifier else { return nil }
        let app = AXUIElementCreateApplication(candidate.pid)
        AXUIElementSetMessagingTimeout(app, 0.15)
        guard let windows = attribute(app, kAXWindowsAttribute) as? [AXUIElement], windows.count <= 32 else { return nil }
        // Require a unique geometry match to the actual frontmost window. This avoids
        // snapping an underlying main window when an inaccessible popup is clicked.
        var matches: [AXUIElement] = []
        let deadline = ProcessInfo.processInfo.systemUptime + 0.25
        for element in windows {
            // Abandon slow apps rather than queueing frame queries for all windows.
            // An individual in-flight AX message is also capped by its timeout.
            guard token?.isValid != false, ProcessInfo.processInfo.systemUptime < deadline else { return nil }
            AXUIElementSetMessagingTimeout(element, 0.15)
            if let frame = frame(element), WindowHitTesting.matches(frame, candidate.frame) { matches.append(element) }
            if matches.count > 1 { return nil }
        }
        guard token?.isValid != false, matches.count == 1, let window = snapshot(matches[0], bundleID: bundle, pid: candidate.pid),
              !window.minimized, !window.fullScreen else { return nil }
        return window
    }

    func readFrame(_ element: AXUIElement, token: WorkToken? = nil, completion: @escaping (CGRect?) -> Void) {
        queue.async {
            guard token?.isValid != false else { DispatchQueue.main.async { completion(nil) }; return }
            let frame = Self.frame(element)
            DispatchQueue.main.async { completion(token?.isValid == false ? nil : frame) }
        }
    }

    func scan(pid: pid_t, bundleID: String, completion: @escaping ([AccessibleWindow]) -> Void) {
        guard pid != ownPID else { completion([]); return }
        queue.async { [self] in
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.15)
            let elements = Self.attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
            let windows = elements.compactMap { Self.snapshot($0, bundleID: bundleID, pid: pid) }
            installObserver(app: app, pid: pid, windows: windows.map(\.element))
            DispatchQueue.main.async { completion(windows) }
        }
    }

    private func installObserver(app: AXUIElement, pid: pid_t, windows: [AXUIElement]) {
        if observers[pid] == nil {
            var observer: AXObserver?
            let callback: AXObserverCallback = { _, element, notification, context in
                guard let context else { return }
                let service = Unmanaged<AccessibilityService>.fromOpaque(context).takeUnretainedValue()
                var pid: pid_t = 0; AXUIElementGetPid(element, &pid)
                DispatchQueue.main.async { service.onNotification?(pid, notification as String, element) }
            }
            guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return }
            observers[pid] = observer
            let context = Unmanaged.passUnretained(self).toOpaque()
            for notification in [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification] {
                AXObserverAddNotification(observer, app, notification as CFString, context)
            }
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        guard let observer = observers[pid] else { return }
        let previous = watched[pid] ?? []
        let notifications = [kAXUIElementDestroyedNotification, kAXTitleChangedNotification, kAXWindowDeminiaturizedNotification]
        let context = Unmanaged.passUnretained(self).toOpaque()
        for window in windows where !previous.contains(where: { CFEqual($0, window) }) {
            for name in notifications { AXObserverAddNotification(observer, window, name as CFString, context) }
        }
        for window in previous where !windows.contains(where: { CFEqual($0, window) }) {
            for name in notifications { AXObserverRemoveNotification(observer, window, name as CFString) }
        }
        watched[pid] = windows
    }

    func remove(pid: pid_t) {
        queue.async { [self] in
            if let observer = observers.removeValue(forKey: pid) {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            }
            watched.removeValue(forKey: pid)
        }
    }

    func removeAll() {
        queue.async { [self] in
            for observer in observers.values {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            }
            observers.removeAll(); watched.removeAll()
        }
    }

    func fit(_ window: AccessibleWindow, to target: CGRect, token: WorkToken? = nil, completion: @escaping (FitResult) -> Void) {
        queue.async {
            let element = window.element
            guard token?.isValid != false,
                  !(Self.attribute(element, kAXMinimizedAttribute) as? Bool ?? false),
                  !(Self.attribute(element, "AXFullScreen") as? Bool ?? false) else {
                DispatchQueue.main.async { completion(FitResult(frame: nil, succeeded: false, exact: false)) }; return
            }
            var settable = DarwinBoolean(false)
            guard AXUIElementIsAttributeSettable(element, kAXPositionAttribute as CFString, &settable) == .success, settable.boolValue else {
                DispatchQueue.main.async { completion(FitResult(frame: nil, succeeded: false, exact: false)) }; return
            }
            let result: FitResult = {
                // Enhanced accessibility can animate each separate position/size write,
                // causing later writes to use stale geometry (observed in Telegram).
                // Suspend it only for this transaction, then restore its original value.
                let app = AXUIElementCreateApplication(window.pid)
                AXUIElementSetMessagingTimeout(app, 0.15)
                let enhancedAttribute = "AXEnhancedUserInterface" as CFString
                let enhanced = Self.attribute(app, enhancedAttribute as String) as? Bool == true
                if enhanced { AXUIElementSetAttributeValue(app, enhancedAttribute, kCFBooleanFalse) }
                defer {
                    // Telegram changes this flag even when the setter reports
                    // notImplemented. Restore after every attempt, not only success.
                    if enhanced { AXUIElementSetAttributeValue(app, enhancedAttribute, kCFBooleanTrue) }
                }
                let before = Self.frame(element)
                func setPosition(_ point: CGPoint) -> AXError {
                    guard token?.isValid != false else { return .failure }
                    var point = point
                    guard let value = AXValueCreate(.cgPoint, &point) else { return .failure }
                    return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
                }
                func setSize(_ size: CGSize) -> AXError {
                    guard token?.isValid != false else { return .failure }
                    var size = size
                    guard let value = AXValueCreate(.cgSize, &size) else { return .failure }
                    return AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value)
                }
                // Shrink before crossing displays; resize again after moving because macOS constrains sizes per display.
                _ = setSize(target.size)
                let moved = setPosition(target.origin)
                let resized = setSize(target.size)
                _ = setPosition(target.origin)
                let actual = Self.frame(element)
                let exact = actual.map { Self.near($0, target) } ?? false
                let changed = actual != nil && actual != before
                let success = exact || (moved == .success && (resized == .success || changed))
                return FitResult(frame: actual, succeeded: success, exact: exact)
            }()
            // The transaction's defer has restored enhanced UI before callers run.
            DispatchQueue.main.async { completion(result) }
        }
    }

    static func near(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(lhs.minX - rhs.minX) <= tolerance && abs(lhs.minY - rhs.minY) <= tolerance &&
        abs(lhs.width - rhs.width) <= tolerance && abs(lhs.height - rhs.height) <= tolerance
    }
}
