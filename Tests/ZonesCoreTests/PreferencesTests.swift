import Foundation
import ZonesCore

final class PreferencesTests {
    func testAtomicPersistenceRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = PreferencesFile(url: directory.appendingPathComponent("settings.json"))
        expectEqual(try file.read(), Preferences())
        var settings = Preferences()
        settings.displays = [DisplayLayout(id: "persistent-monitor-uuid", name: "Ultrawide", layout: GridLayout(columns: [57, 10]))]
        settings.placements = [Placement(window: WindowIdentity(bundleID: "example.app", title: "Document"), displayID: "persistent-monitor-uuid", zoneID: "0")]
        try file.write(settings)
        let loaded = try file.read()
        expectEqual(loaded.displays[0].layout.columns, [57, 43])
        expectEqual(loaded.placements, settings.placements)
        try file.write(loaded)
        expectEqual(try file.read(), loaded)
    }

    func testCorruptAndFutureVersionsAreNotSilentlyOverwritten() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("settings.json"), file = PreferencesFile(url: directory.appendingPathComponent("settings.json"))
        try Data("not json".utf8).write(to: url)
        expectThrows(try file.read())
        expectEqual(try String(contentsOf: url, encoding: .utf8), "not json")
        var future = Preferences(); future.version = 99
        expectThrows(try future.validated())
    }

    func testStableIdentifiersWinOverChangedTitles() {
        let old = WindowIdentity(bundleID: "editor", identifier: "window-A", title: "Old")
        let current = WindowIdentity(bundleID: "editor", identifier: "window-A", title: "New")
        let placement = Placement(window: old, displayID: "external", zoneID: "0")
        expectEqual(PlacementMatcher.match(current, candidates: [current], saved: [placement]), placement)
    }

    func testDocumentsDisambiguateIdenticalTitles() {
        let first = WindowIdentity(bundleID: "editor", document: "file:///a/readme", title: "readme")
        let second = WindowIdentity(bundleID: "editor", document: "file:///b/readme", title: "readme")
        let placement = Placement(window: second, displayID: "external", zoneID: "1")
        expectEqual(PlacementMatcher.match(second, candidates: [first, second], saved: [placement]), placement)
        expectNil(PlacementMatcher.match(first, candidates: [first, second], saved: [placement]))
    }

    func testAmbiguousWindowsAreNeverGuessed() {
        let identity = WindowIdentity(bundleID: "browser", title: "New Tab")
        let placement = Placement(window: identity, displayID: "external", zoneID: "1")
        expectNil(PlacementMatcher.match(identity, candidates: [identity, identity], saved: [placement]))
        expectNil(PlacementMatcher.match(identity, candidates: [identity], saved: [placement, placement]))
    }

    func testSingleWindowAppFallbackAndBundleIsolation() {
        let old = WindowIdentity(bundleID: "music", title: "Old Song")
        let current = WindowIdentity(bundleID: "music", title: "New Song")
        let placement = Placement(window: old, displayID: "external", zoneID: "1")
        expectEqual(PlacementMatcher.match(current, candidates: [current], saved: [placement]), placement)
        expectNil(PlacementMatcher.match(WindowIdentity(bundleID: "other"), candidates: [current], saved: [placement]))
    }
}
