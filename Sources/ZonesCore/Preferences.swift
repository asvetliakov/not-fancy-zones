import Foundation

public struct DisplayLayout: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var layout: GridLayout
    public init(id: String, name: String, layout: GridLayout = GridLayout()) {
        self.id = id; self.name = name; self.layout = layout
    }
}

public struct WindowIdentity: Codable, Equatable {
    public var bundleID: String
    public var identifier: String
    public var document: String
    public var title: String
    public init(bundleID: String, identifier: String = "", document: String = "", title: String = "") {
        self.bundleID = bundleID; self.identifier = identifier; self.document = document; self.title = title
    }
}

public struct Placement: Codable, Equatable, Identifiable {
    public var id: UUID
    public var window: WindowIdentity
    public var displayID: String
    public var zoneID: String
    public var updatedAt: Date
    public init(id: UUID = UUID(), window: WindowIdentity, displayID: String, zoneID: String, updatedAt: Date = Date()) {
        self.id = id; self.window = window; self.displayID = displayID; self.zoneID = zoneID; self.updatedAt = updatedAt
    }
}

public enum PlacementMatcher {
    /// Never guess between identically named windows. Live windows are tracked by their AX object.
    public static func match(_ window: WindowIdentity, candidates: [WindowIdentity], saved: [Placement]) -> Placement? {
        let appSaved = saved.filter { $0.window.bundleID == window.bundleID }
        let appWindows = candidates.filter { $0.bundleID == window.bundleID }
        for key in [\WindowIdentity.identifier, \WindowIdentity.document, \WindowIdentity.title] {
            let value = window[keyPath: key]
            guard !value.isEmpty else { continue }
            let matches = appSaved.filter { $0.window[keyPath: key] == value }
            if matches.count == 1, appWindows.filter({ $0[keyPath: key] == value }).count == 1 { return matches[0] }
        }
        // Single-window applications can restore even if their title changes between launches.
        if appWindows.count == 1, appSaved.count == 1 { return appSaved[0] }
        return nil
    }
}

public struct Preferences: Codable, Equatable {
    public var version = 1
    public var displays: [DisplayLayout] = []
    public var placements: [Placement] = []
    public var restoreWindows = true
    public init() {}

    public func validated() throws -> Preferences {
        guard version == 1 else { throw CocoaError(.fileReadCorruptFile) }
        guard Set(displays.map(\.id)).count == displays.count else { throw CocoaError(.fileReadCorruptFile) }
        var result = self
        result.displays = try displays.map { DisplayLayout(id: $0.id, name: $0.name, layout: try $0.layout.validated()) }
        result.placements = Array(placements.sorted { $0.updatedAt > $1.updatedAt }.prefix(500))
        return result
    }
}

public final class PreferencesFile {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func read() throws -> Preferences {
        guard FileManager.default.fileExists(atPath: url.path) else { return Preferences() }
        return try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: url)).validated()
    }
    public func write(_ preferences: Preferences) throws {
        let data = try JSONEncoder().encode(preferences.validated())
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
