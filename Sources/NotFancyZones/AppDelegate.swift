import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private(set) var state: AppState!
    private(set) var coordinator: WindowCoordinator!
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var integration: IntegrationRunner?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSWindow.allowsAutomaticWindowTabbing = false
        if let index = CommandLine.arguments.firstIndex(of: "--integration-test"), CommandLine.arguments.count > index + 2 {
            let output = URL(fileURLWithPath: CommandLine.arguments[index + 1])
            let fixture = URL(fileURLWithPath: CommandLine.arguments[index + 2])
            state = AppState(configurationURL: output.deletingLastPathComponent().appendingPathComponent("integration-settings.json"))
            coordinator = WindowCoordinator(state: state)
            integration = IntegrationRunner(state: state, coordinator: coordinator, output: output, fixture: fixture)
            integration?.run(); return
        }
        if !CommandLine.arguments.contains("--allow-multiple"),
           NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "app.notfancyzones").count > 1 {
            NSApp.terminate(nil); return
        }
        state = AppState(); coordinator = WindowCoordinator(state: state)
        installMainMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = AppIcon.menuBarImage
        statusItem.button?.toolTip = "Not Fancy Zones — Shift + drag to snap"
        let menu = NSMenu(); menu.delegate = self; statusItem.menu = menu
        coordinator.checkPermission()
        if !state.accessibilityGranted || CommandLine.arguments.contains("--settings") { showSettings() }
    }

    func menuWillOpen(_ menu: NSMenu) {
        coordinator.checkPermission()
        menu.removeAllItems()
        let title = NSMenuItem(title: "Not Fancy Zones", action: nil, keyEquivalent: ""); title.isEnabled = false; menu.addItem(title)
        if !state.accessibilityGranted { add("Enable Accessibility…", action: #selector(accessibilitySettings), to: menu) }
        add("Settings…", action: #selector(showSettings), key: ",", to: menu)
        add("Preview zones (3 seconds)", action: #selector(preview), to: menu)
        add("Restore remembered windows", action: #selector(restore), to: menu)
        menu.addItem(.separator())
        let pause = add("Pause snapping", action: #selector(togglePause), to: menu)
        pause.state = state.paused ? .on : .off
        menu.addItem(.separator())
        add("Quit Not Fancy Zones", action: #selector(quit), key: "q", to: menu)
    }

    @discardableResult private func add(_ title: String, action: Selector, key: String = "", to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = self; menu.addItem(item); return item
    }

    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu(title: "Not Fancy Zones"); appItem.submenu = appMenu
        add("Settings…", action: #selector(showSettings), key: ",", to: appMenu)
        appMenu.addItem(.separator())
        add("Quit Not Fancy Zones", action: #selector(quit), key: "q", to: appMenu)
        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Edit"); editItem.submenu = edit
        for (title, action, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(NSMenuItem(title: title, action: Selector(action), keyEquivalent: key))
        }
        let windowItem = NSMenuItem(); main.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window"); windowItem.submenu = windowMenu
        windowMenu.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        NSApp.mainMenu = main
    }

    @objc func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 790),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Not Fancy Zones Settings"
            window.contentView = NSHostingView(rootView: SettingsView(state: state, coordinator: coordinator,
                restartApp: { [weak self] in self?.restart() }))
            window.minSize = NSSize(width: 900, height: 720)
            window.isReleasedWhenClosed = false; window.delegate = self
            window.setFrameAutosaveName("SettingsWindow"); window.center()
            settingsWindow = window
        }
        coordinator.checkPermission()
        NSApp.activate(ignoringOtherApps: true); settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func accessibilitySettings() { showSettings(); coordinator.checkPermission(prompt: true); openAccessibilitySettings() }
    @objc private func preview() { coordinator.preview() }
    @objc private func restore() { coordinator.restoreAll() }
    @objc private func togglePause() {
        state.paused.toggle(); coordinator.cancelDrag()
        if !state.paused { coordinator.restoreAll() }
    }
    @objc private func quit() { NSApp.terminate(nil) }
    private func restart() {
        guard !state.restarting else { return }
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            state.permissionFeedback = "Run the built .app bundle to use Restart app."; return
        }
        state.restarting = true; state.flush()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        // The old instance exits as soon as Launch Services confirms the new one launched.
        configuration.arguments = ["--settings", "--allow-multiple"]
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { [weak self] _, error in
            DispatchQueue.main.async {
                if let error {
                    self?.state.restarting = false
                    self?.state.permissionFeedback = "Could not restart: \(error.localizedDescription)"
                } else { NSApp.terminate(nil) }
            }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func windowWillClose(_ notification: Notification) {
        // Release the SwiftUI view tree so hidden settings do no work on model changes.
        if let window = notification.object as? NSWindow, window === settingsWindow { settingsWindow = nil }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showSettings(); return true }
    func applicationDidBecomeActive(_ notification: Notification) { coordinator?.checkPermission() }
    func applicationWillTerminate(_ notification: Notification) { state?.flush() }
}
