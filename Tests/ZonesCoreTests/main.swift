import Foundation

// Command Line Tools ship the compiler/SDK but not XCTest or Swift Testing.
// A tiny dependency-free executable lets this suite run on that supported setup.
var failures = 0
var tests = 0
func fail(_ message: String, file: StaticString, line: UInt) {
    failures += 1; print("  FAIL \(file):\(line): \(message)")
}
func expectTrue(_ condition: @autoclosure () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
    if !condition() { fail("Expected true", file: file, line: line) }
}
func expectNil<T>(_ value: @autoclosure () -> T?, file: StaticString = #filePath, line: UInt = #line) {
    if value() != nil { fail("Expected nil", file: file, line: line) }
}
func expectEqual<T: Equatable>(_ lhs: @autoclosure () throws -> T, _ rhs: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
    do {
        let a = try lhs(), b = try rhs()
        if a != b { fail("\(a) != \(b)", file: file, line: line) }
    } catch { fail("Unexpected error: \(error)", file: file, line: line) }
}
func expectEqual<T: BinaryFloatingPoint>(_ lhs: T, _ rhs: T, accuracy: T, file: StaticString = #filePath, line: UInt = #line) {
    if abs(lhs - rhs) > accuracy { fail("\(lhs) differs from \(rhs)", file: file, line: line) }
}
func expectThrows<T>(_ body: @autoclosure () throws -> T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try body(); fail("Expected an error: \(message)", file: file, line: line) } catch {}
}
func run(_ name: String, _ body: () throws -> Void) {
    tests += 1
    let before = failures
    do { try body() } catch { failures += 1; print("  FAIL \(name): \(error)") }
    print("\(before == failures ? "PASS" : "FAIL") \(name)")
}

run("Window hit fallback respects occlusion and geometry", testWindowHitFallback)
let layout = LayoutTests()
run("Drag versus content/resize classification", layout.testDragClassification)
run("Percentage remainder correction", layout.testRemainderCorrection)
run("Invalid percentages", layout.testRejectInvalidInput)
run("Four equal zones", layout.testFourEqualZonesCoverScreen)
run("Requested large-left merged layout", layout.testRequestedMergedLayout)
run("Reject nonrectangular merges", layout.testMergeRejectsLShapesAndDisjointCells)
run("Merge existing merges", layout.testCanMergePreviouslyMergedZones)
run("Margins and gaps", layout.testMarginsAndGapsAreNotDoubled)
run("No gaps inside merges", layout.testMergedZoneHasNoInternalGaps)
run("Negative display origins", layout.testCoordinateConversionForDisplaysAboveAndLeft)
run("Reject corrupt layouts", layout.testCorruptMergesAndMarginsRejected)
run("Extreme margins", layout.testExtremeMarginsNeverProduceNegativeFrames)
run("144 grid geometries", layout.testManyLayoutsTileWithoutHolesOrOverlaps)
let preferences = PreferencesTests()
run("Atomic persistence round trip", preferences.testAtomicPersistenceRoundTrip)
run("Corrupt and future settings", preferences.testCorruptAndFutureVersionsAreNotSilentlyOverwritten)
run("Stable window identifier", preferences.testStableIdentifiersWinOverChangedTitles)
run("Document matching", preferences.testDocumentsDisambiguateIdenticalTitles)
run("Ambiguous windows", preferences.testAmbiguousWindowsAreNeverGuessed)
run("Single-window fallback and bundle isolation", preferences.testSingleWindowAppFallbackAndBundleIsolation)
print("\n\(tests) tests, \(failures) failures")
exit(failures == 0 ? 0 : 1)
