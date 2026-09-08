import AppKit
import Combine
import ApplicationServices
import ZonesCore

struct DisplayInfo: Identifiable, Equatable {
    var id: String
    var name: String
    var frame: CGRect
    var workArea: CGRect
    var appKitFrame: CGRect
    var pixels: CGSize
    var scale: CGFloat
}

final class AppState: ObservableObject {
    @Published var preferences: Preferences
    @Published var displays: [DisplayInfo] = []
    @Published var accessibilityGranted = AXIsProcessTrusted()
    @Published var checkingAccessibility = false
    @Published var permissionFeedback: String?
    @Published var permissionCheckedAt: String?
    @Published var restarting = false
    @Published var paused = false
    @Published var status = "Hold Shift while dragging a window to snap it."
    @Published var storageError: String?
    var onLayoutChanged: (() -> Void)?
    private let file: PreferencesFile
    private let writer = DispatchQueue(label: "app.notfancyzones.preferences", qos: .utility)
    private var pendingWrite: DispatchWorkItem?

    init(configurationURL: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        file = PreferencesFile(url: configurationURL ?? base.appendingPathComponent("NotFancyZones/settings.json"))
        do { preferences = try file.read() }
        catch {
            preferences = Preferences()
            // Preserve unreadable settings before allowing any future save.
            let backup = file.url.deletingPathExtension().appendingPathExtension("unreadable-\(Int(Date().timeIntervalSince1970)).json")
            do {
                try FileManager.default.copyItem(at: file.url, to: backup)
                storageError = "Settings could not be read. A backup was saved to \(backup.path)."
            } catch {
                storageError = "Settings could not be read or backed up. Saving is disabled until the file is repaired: \(file.url.path)"
                savingDisabled = true
            }
        }
        refreshDisplays()
    }

    private var savingDisabled = false
    var configurationURL: URL { file.url }

    func refreshDisplays() {
        let screens = NSScreen.screens
        let primaryHeight = screens.first?.frame.height ?? 0
        displays = screens.map { screen in
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            let displayID = CGDirectDisplayID(number?.uint32Value ?? 0)
            let uuid = CGDisplayCreateUUIDFromDisplayID(displayID).map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String }
            return DisplayInfo(
                id: uuid ?? "display-\(CGDisplayVendorNumber(displayID))-\(CGDisplayModelNumber(displayID))-\(CGDisplaySerialNumber(displayID))",
                name: screen.localizedName,
                frame: ScreenCoordinates.accessibilityRect(fromAppKit: screen.frame, primaryHeight: primaryHeight),
                workArea: ScreenCoordinates.accessibilityRect(fromAppKit: screen.visibleFrame, primaryHeight: primaryHeight),
                appKitFrame: screen.frame,
                pixels: CGSize(width: CGDisplayPixelsWide(displayID), height: CGDisplayPixelsHigh(displayID)),
                scale: screen.backingScaleFactor
            )
        }
        var changed = false
        for display in displays {
            if let index = preferences.displays.firstIndex(where: { $0.id == display.id }) {
                if preferences.displays[index].name != display.name {
                    preferences.displays[index].name = display.name; changed = true
                }
            } else {
                let wide = display.frame.width / max(1, display.frame.height) > 2.5
                preferences.displays.append(DisplayLayout(id: display.id, name: display.name,
                    layout: wide ? GridLayout(columns: [34, 33, 33]) : GridLayout()))
                changed = true
            }
        }
        if changed { save() }
    }

    func layout(for id: String) -> GridLayout {
        preferences.displays.first(where: { $0.id == id })?.layout ?? GridLayout()
    }

    func setLayout(_ layout: GridLayout, for id: String) throws {
        let valid = try layout.validated()
        guard let index = preferences.displays.firstIndex(where: { $0.id == id }) else { return }
        preferences.displays[index].layout = valid
        save(); onLayoutChanged?()
    }

    func save() {
        guard !savingDisabled else { return }
        pendingWrite?.cancel()
        let snapshot = preferences, destination = file
        let work = DispatchWorkItem { [weak self] in
            do { try destination.write(snapshot) }
            catch { DispatchQueue.main.async { self?.storageError = "Could not save settings: \(error.localizedDescription)" } }
        }
        pendingWrite = work
        writer.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func flush() {
        pendingWrite?.cancel()
        guard !savingDisabled else { return }
        let snapshot = preferences
        do { try writer.sync { try file.write(snapshot) } }
        catch { storageError = "Could not save settings: \(error.localizedDescription)" }
    }

    func remember(_ placement: Placement) {
        preferences.placements.removeAll { $0.id == placement.id }
        preferences.placements.append(placement)
        preferences.placements = Array(preferences.placements.sorted { $0.updatedAt > $1.updatedAt }.prefix(500))
        save()
    }

    func forget(_ id: UUID) {
        preferences.placements.removeAll { $0.id == id }; save()
    }
}
