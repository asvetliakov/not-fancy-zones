import Foundation
import CoreGraphics
import ZonesCore

final class LayoutTests {
    func testDragClassification() {
        let original = CGRect(x: 100, y: 100, width: 800, height: 600)
        expectTrue(!DragMotion.isTranslation(from: original, to: original))
        expectTrue(!DragMotion.isTranslation(from: original, to: original.offsetBy(dx: 1, dy: 1)))
        expectTrue(DragMotion.isTranslation(from: original, to: original.offsetBy(dx: -1700, dy: -200)))
        expectTrue(!DragMotion.isTranslation(from: original, to: CGRect(x: 50, y: 50, width: 850, height: 650)))
        expectTrue(!DragMotion.isTranslation(from: original, to: CGRect(x: 100, y: 100, width: 900, height: 700)))
    }

    func testRemainderCorrection() throws {
        expectEqual(try Percentages.parse("57 10"), [57, 43])
        expectEqual(try Percentages.parse("50 30"), [50, 50])
        expectEqual(try Percentages.parse("70 30"), [70, 30])
        expectEqual(try Percentages.parse("34, 33, 10"), [34, 33, 33])
        expectEqual(try Percentages.parse("20"), [100])
        expectEqual(Percentages.format([100, 50, 33.3333, 0]), "100 50 33.3333 0")
    }

    func testRejectInvalidInput() {
        for text in ["", "0 100", "-1 101", "100 20", "70 40 30", "nan 20", "inf", "hello", Array(repeating: "1", count: 13).joined(separator: " ")] {
            expectThrows(try Percentages.parse(text), text)
        }
    }

    func testFourEqualZonesCoverScreen() {
        let layout = GridLayout(columns: [50, 50], rows: [50, 50], outerMargin: 0, gap: 0)
        let zones = layout.zones(in: CGRect(x: 0, y: 0, width: 5120, height: 1440))
        expectEqual(zones.map(\.frame), [
            CGRect(x: 0, y: 0, width: 2560, height: 720), CGRect(x: 2560, y: 0, width: 2560, height: 720),
            CGRect(x: 0, y: 720, width: 2560, height: 720), CGRect(x: 2560, y: 720, width: 2560, height: 720)
        ])
    }

    func testRequestedMergedLayout() throws {
        var layout = GridLayout(columns: [34, 33, 33], rows: [50, 50], outerMargin: 0, gap: 0)
        try layout.merge(zoneIDs: ["0", "1", "3", "4"])
        let zones = layout.zones(in: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        expectEqual(zones.count, 3)
        expectEqual(zones[0].frame, CGRect(x: 0, y: 0, width: 670, height: 1000))
        expectEqual(zones[1].frame, CGRect(x: 670, y: 0, width: 330, height: 500))
        expectEqual(zones[2].frame, CGRect(x: 670, y: 500, width: 330, height: 500))
        layout.unmerge(zoneIDs: [zones[0].id])
        expectEqual(layout.groups.count, 6)
    }

    func testMergeRejectsLShapesAndDisjointCells() {
        var layout = GridLayout(columns: [34, 33, 33], rows: [50, 50])
        expectThrows(try layout.merge(zoneIDs: ["0", "1", "3"]))
        expectThrows(try layout.merge(zoneIDs: ["0", "2"]))
        expectThrows(try layout.merge(zoneIDs: ["0"]))
        expectEqual(layout.groups.count, 6)
    }

    func testCanMergePreviouslyMergedZones() throws {
        var layout = GridLayout(columns: [50, 50], rows: [50, 50])
        try layout.merge(zoneIDs: ["0", "1"])
        try layout.merge(zoneIDs: ["2", "3"])
        try layout.merge(zoneIDs: ["0-1", "2-3"])
        expectEqual(layout.groups, [[0, 1, 2, 3]])
    }

    func testMarginsAndGapsAreNotDoubled() {
        let layout = GridLayout(columns: [50, 50], rows: [50, 50], outerMargin: 10, gap: 8)
        let bounds = CGRect(x: -1000, y: -800, width: 1000, height: 800)
        let zones = layout.zones(in: bounds)
        expectEqual(zones[0].frame.minX, bounds.minX + 10)
        expectEqual(zones[0].frame.minY, bounds.minY + 10)
        expectEqual(zones[1].frame.minX - zones[0].frame.maxX, 8)
        expectEqual(zones[2].frame.minY - zones[0].frame.maxY, 8)
        expectEqual(zones[3].frame.maxX, bounds.maxX - 10)
        expectEqual(zones[3].frame.maxY, bounds.maxY - 10)
    }

    func testMergedZoneHasNoInternalGaps() {
        let layout = GridLayout(columns: [50, 50], rows: [50, 50], merges: [[0, 2]], outerMargin: 10, gap: 8)
        let zones = layout.zones(in: CGRect(x: 0, y: 0, width: 1000, height: 800))
        expectEqual(zones[0].frame.height, 780)
        expectEqual(zones[1].frame.minX - zones[0].frame.maxX, 8)
    }

    func testCoordinateConversionForDisplaysAboveAndLeft() {
        expectEqual(ScreenCoordinates.accessibilityRect(fromAppKit: CGRect(x: -1920, y: 1080, width: 1920, height: 1080), primaryHeight: 1080),
                       CGRect(x: -1920, y: -1080, width: 1920, height: 1080))
        expectEqual(ScreenCoordinates.accessibilityRect(fromAppKit: CGRect(x: 0, y: 60, width: 1920, height: 995), primaryHeight: 1080),
                       CGRect(x: 0, y: 25, width: 1920, height: 995))
    }

    func testCorruptMergesAndMarginsRejected() {
        for merges in [[[0, 0]], [[0, 1], [1, 2]], [[0, 99]], [[-1, 0]]] {
            expectThrows(try GridLayout(merges: merges).validated())
        }
        expectThrows(try GridLayout(outerMargin: -.infinity).validated())
        expectThrows(try GridLayout(gap: 201).validated())
    }

    func testExtremeMarginsNeverProduceNegativeFrames() {
        let zones = GridLayout(columns: [1, 99], rows: [1, 99], outerMargin: 200, gap: 200)
            .zones(in: CGRect(x: 0, y: 0, width: 100, height: 80))
        expectEqual(zones.count, 4)
        expectTrue(zones.allSatisfy { $0.frame.width > 0 && $0.frame.height > 0 })
    }

    func testManyLayoutsTileWithoutHolesOrOverlaps() {
        for columns in 1...12 {
            for rows in 1...12 {
                let cs = Array(repeating: 100.0 / Double(columns), count: columns)
                let rs = Array(repeating: 100.0 / Double(rows), count: rows)
                let bounds = CGRect(x: -1500, y: -400, width: 5120, height: 1440)
                let zones = GridLayout(columns: cs, rows: rs, outerMargin: 0, gap: 0).zones(in: bounds)
                expectEqual(zones.count, columns * rows)
                expectEqual(zones.reduce(0) { $0 + $1.frame.width * $1.frame.height }, bounds.width * bounds.height, accuracy: 0.001)
                for a in zones.indices {
                    expectTrue(bounds.insetBy(dx: -0.001, dy: -0.001).contains(zones[a].frame))
                    for b in zones.indices where b > a {
                        let intersection = zones[a].frame.intersection(zones[b].frame)
                        expectTrue(intersection.isNull || intersection.width < 0.001 || intersection.height < 0.001)
                    }
                }
            }
        }
    }
}
