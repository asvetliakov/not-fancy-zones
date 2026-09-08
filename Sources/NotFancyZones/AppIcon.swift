import AppKit

enum AppIcon {
    /// Decode lazily once. AppKit selects the appropriate representation from the ICNS.
    static let image: NSImage = {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) { return image }
        return NSImage(systemSymbolName: "rectangle.split.3x1", accessibilityDescription: "Not Fancy Zones") ?? NSImage()
    }()

    static let menuBarImage: NSImage = {
        let image = AppIcon.image.copy() as! NSImage
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = false
        image.accessibilityDescription = "Not Fancy Zones"
        return image
    }()
}
