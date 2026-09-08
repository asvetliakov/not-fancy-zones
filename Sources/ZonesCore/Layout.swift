import Foundation
import CoreGraphics

public enum LayoutError: Error, LocalizedError, Equatable {
    case invalidPercentages, tooManyTracks, noRemainder, invalidMerge, invalidMargin
    public var errorDescription: String? {
        switch self {
        case .invalidPercentages: return "Enter positive percentages separated by spaces, for example 34 33 33."
        case .tooManyTracks: return "Use between 1 and 12 columns or rows."
        case .noRemainder: return "The percentages before the last value must add up to less than 100."
        case .invalidMerge: return "Select adjacent zones that together form a rectangle."
        case .invalidMargin: return "Margins must be between 0 and 200 points."
        }
    }
}

public enum Percentages {
    public static func parse(_ text: String) throws -> [Double] {
        let parts = text.split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == ";" })
        guard !parts.isEmpty, parts.count <= 12 else { throw LayoutError.tooManyTracks }
        let values = try parts.map { part -> Double in
            guard let value = Double(part), value.isFinite, value > 0 else { throw LayoutError.invalidPercentages }
            return value
        }
        return try corrected(values)
    }

    public static func corrected(_ values: [Double]) throws -> [Double] {
        guard !values.isEmpty, values.count <= 12 else { throw LayoutError.tooManyTracks }
        guard values.allSatisfy({ $0.isFinite && $0 > 0 }) else { throw LayoutError.invalidPercentages }
        if values.count == 1 { return [100] }
        let leading = values.dropLast().reduce(0, +)
        guard leading < 100 - 0.0001 else { throw LayoutError.noRemainder }
        return Array(values.dropLast()) + [100 - leading]
    }

    public static func format(_ values: [Double]) -> String {
        values.map { String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), $0)
            .replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression) }.joined(separator: " ")
    }
}

public struct Zone: Equatable, Identifiable {
    public var cells: [Int]
    public var frame: CGRect
    /// Bounds before gaps; used for continuous drag hit testing.
    public var hitFrame: CGRect
    public var id: String { cells.map(String.init).joined(separator: "-") }
    public init(cells: [Int], frame: CGRect, hitFrame: CGRect) {
        self.cells = cells; self.frame = frame; self.hitFrame = hitFrame
    }
}

public struct GridLayout: Codable, Equatable {
    public var columns: [Double]
    public var rows: [Double]
    public var merges: [[Int]]
    public var outerMargin: Double
    public var gap: Double

    public init(columns: [Double] = [50, 50], rows: [Double] = [100], merges: [[Int]] = [], outerMargin: Double = 8, gap: Double = 8) {
        self.columns = columns; self.rows = rows; self.merges = merges
        self.outerMargin = outerMargin; self.gap = gap
    }

    public func validated() throws -> GridLayout {
        var result = self
        result.columns = try Percentages.corrected(columns)
        result.rows = try Percentages.corrected(rows)
        guard outerMargin.isFinite, gap.isFinite, (0...200).contains(outerMargin), (0...200).contains(gap) else {
            throw LayoutError.invalidMargin
        }
        var used = Set<Int>()
        for group in merges {
            guard group.count > 1, Set(group).count == group.count,
                  group.allSatisfy({ $0 >= 0 && $0 < columns.count * rows.count }),
                  used.isDisjoint(with: group), isRectangle(group) else { throw LayoutError.invalidMerge }
            used.formUnion(group)
        }
        return result
    }

    public var groups: [[Int]] {
        let merged = Set(merges.flatMap { $0 })
        return (merges.map { $0.sorted() } + (0..<(columns.count * rows.count)).filter { !merged.contains($0) }.map { [$0] })
            .sorted { $0[0] < $1[0] }
    }

    public func isRectangle(_ cells: [Int]) -> Bool {
        guard !cells.isEmpty, !columns.isEmpty else { return false }
        let xs = cells.map { $0 % columns.count }, ys = cells.map { $0 / columns.count }
        return (xs.max()! - xs.min()! + 1) * (ys.max()! - ys.min()! + 1) == Set(cells).count
    }

    public mutating func merge(zoneIDs: Set<String>) throws {
        let selected = groups.filter { zoneIDs.contains($0.map(String.init).joined(separator: "-")) }
        let cells = selected.flatMap { $0 }.sorted()
        guard selected.count >= 2, isRectangle(cells) else { throw LayoutError.invalidMerge }
        let selectedCells = Set(cells)
        merges.removeAll { !selectedCells.isDisjoint(with: $0) }
        merges.append(cells)
    }

    public mutating func unmerge(zoneIDs: Set<String>) {
        merges.removeAll { zoneIDs.contains($0.sorted().map(String.init).joined(separator: "-")) }
    }

    /// Coordinates have a top-left origin, matching Accessibility and CGEvent.
    public func zones(in bounds: CGRect) -> [Zone] {
        guard bounds.width > 0, bounds.height > 0, let safe = try? validated() else { return [] }
        let margin = min(safe.outerMargin, max(0, (min(bounds.width, bounds.height) - 1) / 2))
        let inner = bounds.insetBy(dx: margin, dy: margin)
        func stops(_ tracks: [Double], origin: CGFloat, length: CGFloat) -> [CGFloat] {
            var result = [origin]
            for value in tracks { result.append(result.last! + length * value / 100) }
            result[result.count - 1] = origin + length
            return result
        }
        let x = stops(safe.columns, origin: inner.minX, length: inner.width)
        let y = stops(safe.rows, origin: inner.minY, length: inner.height)
        // Cap excessive gaps so even a narrow track remains a usable rectangle.
        let minTrack = min(zip(x.dropFirst(), x).map(-).min()!, zip(y.dropFirst(), y).map(-).min()!)
        let actualGap = min(safe.gap, max(0, minTrack - 1))
        return safe.groups.map { cells in
            let xs = cells.map { $0 % safe.columns.count }, ys = cells.map { $0 / safe.columns.count }
            let left = xs.min()!, right = xs.max()! + 1, top = ys.min()!, bottom = ys.max()! + 1
            let hit = CGRect(x: x[left], y: y[top], width: x[right] - x[left], height: y[bottom] - y[top])
            let l = left == 0 ? 0 : actualGap / 2, r = right == safe.columns.count ? 0 : actualGap / 2
            let t = top == 0 ? 0 : actualGap / 2, b = bottom == safe.rows.count ? 0 : actualGap / 2
            let frame = CGRect(x: hit.minX + l, y: hit.minY + t, width: hit.width - l - r, height: hit.height - t - b)
            return Zone(cells: cells, frame: frame, hitFrame: hit)
        }
    }
}

public enum DragMotion {
    public static func isTranslation(from original: CGRect, to current: CGRect) -> Bool {
        let moved = abs(current.minX - original.minX) > 2 || abs(current.minY - original.minY) > 2
        let sameSize = abs(current.width - original.width) < 3 && abs(current.height - original.height) < 3
        return moved && sameSize
    }
}

public enum ScreenCoordinates {
    /// The primary screen is NSScreen.screens[0], not NSScreen.main (the focused screen).
    public static func accessibilityRect(fromAppKit rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}
