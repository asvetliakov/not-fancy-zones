import Foundation
import ZonesCore

func testWindowHitFallback() {
    let point = CGPoint(x: -400, y: 120)
    let frame = CGRect(x: -500, y: 100, width: 300, height: 400)
    let back = WindowHitCandidate(pid: 2, frame: frame, layer: 0, alpha: 1)
    let front = WindowHitCandidate(pid: 3, frame: frame, layer: 0, alpha: 1)
    expectEqual(WindowHitTesting.frontmost(at: point, in: [front, back], excludingPID: 1)?.pid, 3)
    // A panel, menu, or our own settings must block the window behind it.
    expectNil(WindowHitTesting.frontmost(at: point, in: [WindowHitCandidate(pid: 3, frame: frame, layer: 3, alpha: 1), back], excludingPID: 1))
    expectNil(WindowHitTesting.frontmost(at: point, in: [front, back], excludingPID: 3))
    expectEqual(WindowHitTesting.frontmost(at: point, in: [WindowHitCandidate(pid: 3, frame: frame, layer: 0, alpha: 0), back], excludingPID: 1)?.pid, 2)
    expectNil(WindowHitTesting.frontmost(at: .zero, in: [front], excludingPID: 1))
    expectTrue(WindowHitTesting.matches(frame, frame.offsetBy(dx: 1, dy: -1)))
    expectTrue(!WindowHitTesting.matches(frame, frame.offsetBy(dx: 10, dy: 0)))
    expectTrue(!WindowHitTesting.matches(frame, CGRect(x: -500, y: 100, width: 200, height: 400)))
}
