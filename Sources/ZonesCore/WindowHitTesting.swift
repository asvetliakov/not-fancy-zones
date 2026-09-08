import Foundation

public struct WindowHitCandidate {
    public let pid: Int32
    public let frame: CGRect
    public let layer: Int
    public let alpha: Double
    public init(pid: Int32, frame: CGRect, layer: Int, alpha: Double) {
        self.pid = pid; self.frame = frame; self.layer = layer; self.alpha = alpha
    }
}

public enum WindowHitTesting {
    /// Input must be in front-to-back stacking order. An unsupported foreground
    /// window blocks the fallback; it must not select a window behind it.
    public static func frontmost(at point: CGPoint, in windows: [WindowHitCandidate], excludingPID: Int32) -> WindowHitCandidate? {
        guard let window = windows.first(where: { $0.alpha > 0 && $0.frame.contains(point) }),
              window.layer == 0, window.pid > 0, window.pid != excludingPID else { return nil }
        return window
    }

    public static func matches(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) <= 2 && abs(lhs.minY - rhs.minY) <= 2 &&
        abs(lhs.width - rhs.width) <= 2 && abs(lhs.height - rhs.height) <= 2
    }
}
