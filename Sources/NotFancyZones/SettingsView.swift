import AppKit
import SwiftUI
import ServiceManagement
import ZonesCore

struct SettingsView: View {
    @ObservedObject var state: AppState
    let coordinator: WindowCoordinator
    let restartApp: () -> Void
    @State private var displayID = ""
    @State private var columns = "50 50"
    @State private var rows = "100"
    @State private var outer = "8"
    @State private var gap = "8"
    @State private var draft = ZonesCore.GridLayout()
    @State private var selection = Set<String>()
    @State private var error: String?
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?
    @State private var showForgetConfirmation = false

    private var connected: DisplayInfo? { state.displays.first { $0.id == displayID } }
    private var displayName: String { state.preferences.displays.first { $0.id == displayID }?.name ?? "Choose a display" }
    private var currentLayout: ZonesCore.GridLayout { (try? parsedLayout()) ?? draft }
    private var hasChanges: Bool {
        guard let parsed = try? parsedLayout() else { return true }
        return parsed != state.layout(for: displayID)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 210)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    permissionBanner
                    if let storageError = state.storageError { Text(storageError).foregroundStyle(.red).font(.callout).textSelection(.enabled) }
                    layoutEditor
                    preview
                    HStack {
                        Button("Merge selected") { merge() }.disabled(selection.count < 2)
                            .accessibilityIdentifier("mergeZones")
                        Button("Unmerge selected") { unmerge() }.disabled(!currentLayout.groups.contains { $0.count > 1 && selection.contains($0.map(String.init).joined(separator: "-")) })
                            .accessibilityIdentifier("unmergeZones")
                        Spacer()
                        Text("\(currentLayout.groups.count) zones").font(.callout).foregroundStyle(.secondary)
                    }
                    if let error { Text(error).font(.callout).foregroundStyle(.red).accessibilityIdentifier("layoutError") }
                    HStack {
                        Text(hasChanges ? "Unapplied changes" : "Layout saved").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Preview on screens") { coordinator.preview() }.disabled(hasChanges)
                        Button("Apply layout") { apply() }.buttonStyle(.borderedProminent)
                            .keyboardShortcut(.return, modifiers: .command).accessibilityIdentifier("applyLayout")
                    }
                    Divider()
                    behavior
                }.padding(26)
            }
        }
        .frame(minWidth: 900, minHeight: 720)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { if displayID.isEmpty { load(state.displays.first?.id ?? state.preferences.displays.first?.id ?? "") } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginStatus = SMAppService.mainApp.status
        }
        .alert("Forget all remembered windows?", isPresented: $showForgetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Forget windows", role: .destructive) { coordinator.forgetAll() }
        } message: { Text("Your monitor layouts will stay saved. Snap a window again to remember a new position.") }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(nsImage: AppIcon.image).resizable().interpolation(.high)
                    .frame(width: 32, height: 32).accessibilityLabel("Not Fancy Zones app icon")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Not Fancy Zones").font(.headline)
                    Text("A place for every window").font(.caption2).foregroundStyle(.secondary)
                }
            }.padding(.bottom, 26).padding(.top, 10)
            Text("DISPLAYS").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 8)
            ForEach(state.preferences.displays) { display in
                let live = state.displays.first { $0.id == display.id }
                Button { load(display.id) } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: live == nil ? "display.trianglebadge.exclamationmark" : "display")
                            .font(.system(size: 19)).frame(width: 24).padding(.top, 2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(display.name).font(.system(size: 13, weight: .medium)).lineLimit(2)
                            Text(live.map { "\(Int($0.frame.width)) × \(Int($0.frame.height)) pt" } ?? "Disconnected · saved")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(displayID == display.id ? Color.accentColor.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("display-\(display.id)")
            }
            Spacer()
            Label(state.paused ? "Snapping paused" : "Shift + drag to snap", systemImage: state.paused ? "pause.circle" : "shift")
                .font(.callout).foregroundStyle(.secondary)
            Text("Runs quietly in your menu bar.").font(.caption2).foregroundStyle(.tertiary)
        }.padding(14).background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(displayName).font(.system(size: 25, weight: .semibold))
            if let connected {
                Text("\(Int(connected.pixels.width)) × \(Int(connected.pixels.height)) display · \(Int(connected.workArea.width)) × \(Int(connected.workArea.height)) pt available")
                    .font(.callout).foregroundStyle(.secondary)
            } else { Text("This layout will be used when the display reconnects.").font(.callout).foregroundStyle(.secondary) }
        }
    }

    private var permissionBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: state.accessibilityGranted ? "checkmark.shield.fill" : "hand.raised.fill")
                    .foregroundStyle(state.accessibilityGranted ? .green : .orange)
                Text(state.accessibilityGranted ? "Accessibility enabled" : "Allow Accessibility to move windows")
                    .font(.callout.weight(.semibold))
                Spacer()
                Button(state.checkingAccessibility ? "Checking…" : "Check again") { coordinator.recheckPermission() }
                    .disabled(state.checkingAccessibility || state.restarting).accessibilityIdentifier("checkAccessibility")
            }
            if let feedback = state.permissionFeedback {
                Text(feedback).font(.caption).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("accessibilityFeedback")
            }
            if !state.accessibilityGranted {
                Text("System Settings → Privacy & Security → Accessibility")
                    .font(.caption).foregroundStyle(.secondary)
                Text(Bundle.main.bundlePath).font(.caption2).foregroundStyle(.secondary)
                    .textSelection(.enabled).accessibilityIdentifier("runningAppPath")
                if Bundle.main.object(forInfoDictionaryKey: "NFZSigningKind") as? String == "adhoc" {
                    Text("This development build is ad-hoc signed. Updates can invalidate its permission until a consistent signing certificate is configured.")
                        .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Button("Open Settings") { coordinator.checkPermission(prompt: true); openAccessibilitySettings() }
                    Button("Show this app in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
                    Button(state.restarting ? "Restarting…" : "Restart app", action: restartApp)
                        .disabled(state.restarting).accessibilityIdentifier("restartApp")
                }
            }
            if let checkedAt = state.permissionCheckedAt {
                Text("Last checked at \(checkedAt)").font(.caption2).foregroundStyle(.secondary)
            }
        }.padding(12).background((state.accessibilityGranted ? Color.green : Color.orange).opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private var layoutEditor: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 18) {
                field("Columns (%)", text: $columns, identifier: "columns", hint: "e.g. 34 33 33")
                field("Rows (%)", text: $rows, identifier: "rows", hint: "e.g. 50 50 for two rows")
            }
            Text("The final percentage fills the remainder. Columns repeat in every row.")
                .font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 18) {
                field("Screen margin (pt)", text: $outer, identifier: "outerMargin", hint: "Space around the layout")
                field("Window gap (pt)", text: $gap, identifier: "windowGap", hint: "Space between windows")
            }
        }
    }

    private func field(_ label: String, text: Binding<String>, identifier: String, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.callout.weight(.medium))
            TextField(hint, text: text).textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced)).accessibilityLabel(label).accessibilityIdentifier(identifier)
                .onSubmit { apply() }
            Text(hint).font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Layout preview").font(.callout.weight(.semibold))
                Spacer()
                if !selection.isEmpty { Button("Clear selection") { selection.removeAll() }.font(.caption) }
            }
            GeometryReader { proxy in
                let area = CGRect(x: 0, y: 0, width: connected?.workArea.width ?? 1440, height: connected?.workArea.height ?? 900)
                let scale = min(proxy.size.width / area.width, proxy.size.height / area.height)
                let size = CGSize(width: area.width * scale, height: area.height * scale)
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.045))
                    ForEach(Array(currentLayout.zones(in: area).enumerated()), id: \.element.id) { index, zone in
                        let selected = selection.contains(zone.id)
                        Button {
                            if selected { selection.remove(zone.id) } else { selection.insert(zone.id) }
                        } label: {
                            VStack(spacing: 3) {
                                Text("\(index + 1)").font(.system(size: 20, weight: .semibold, design: .rounded))
                                if zone.frame.width * scale > 95 && zone.frame.height * scale > 55 {
                                    Text("\(Int(zone.frame.width)) × \(Int(zone.frame.height)) pt").font(.system(size: 10, design: .monospaced)).opacity(0.7)
                                }
                            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                                .foregroundStyle(selected ? Color.accentColor : Color.primary.opacity(0.7))
                                .background(selected ? Color.accentColor.opacity(0.22) : Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(selected ? Color.accentColor : Color.accentColor.opacity(0.3), lineWidth: selected ? 2 : 1))
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .frame(width: max(1, zone.frame.width * scale), height: max(1, zone.frame.height * scale))
                            .position(x: zone.frame.midX * scale, y: zone.frame.midY * scale)
                            .accessibilityLabel("Zone \(index + 1)\(selected ? ", selected" : "")")
                            .accessibilityIdentifier("zone-\(zone.id)")
                    }
                }.frame(width: size.width, height: size.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }.frame(height: 185)
            Text("Click adjacent zones to select them, then merge. Merges must form a rectangle.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var behavior: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Automatically restore remembered windows", isOn: Binding(
                get: { state.preferences.restoreWindows },
                set: { state.preferences.restoreWindows = $0; state.save(); coordinator.restorationChanged() }
            )).font(.callout)
            Toggle("Launch at login", isOn: Binding(
                get: { loginStatus == .enabled || loginStatus == .requiresApproval },
                set: setLaunchAtLogin
            )).font(.callout).accessibilityIdentifier("launchAtLogin")
            if loginStatus == .requiresApproval {
                Text("Allow Not Fancy Zones in System Settings → General → Login Items & Extensions to finish enabling it.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Open Login Items Settings") { SMAppService.openSystemSettingsLoginItems() }
            }
            if let loginError {
                Text(loginError).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                    .accessibilityIdentifier("loginItemError")
                Button("Restart app", action: restartApp).disabled(state.restarting)
            }
            HStack {
                Text("\(state.preferences.placements.count) remembered windows").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Restore now") { coordinator.restoreAll() }.disabled(!state.accessibilityGranted)
                Button("Forget windows…") { showForgetConfirmation = true }.disabled(state.preferences.placements.isEmpty)
            }
            Text(state.status).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("Uses the space macOS makes available, including when the Dock or menu bar auto-hides. Manually moving or resizing a window releases its assignment.")
                .font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        loginError = nil
        // Refreshing UI state must never register/unregister again. In particular,
        // reverting an unsuccessful enable must not try to unregister a missing item.
        defer { loginStatus = service.status }
        do {
            if enabled {
                if service.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems(); return
                }
                if service.status != .enabled { try service.register() }
                if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            } else if service.status == .enabled || service.status == .requiresApproval {
                try service.unregister()
            }
        } catch {
            let failure = error as NSError
            loginError = "Launch at login: \(failure.localizedDescription) (\(failure.domain), \(failure.code)). Quit and reopen the .app from Finder, then try again."
        }
    }

    private func load(_ id: String) {
        displayID = id; draft = state.layout(for: id)
        columns = Percentages.format(draft.columns); rows = Percentages.format(draft.rows)
        outer = Percentages.format([draft.outerMargin]); gap = Percentages.format([draft.gap])
        selection.removeAll(); error = nil
    }

    private func parsedLayout() throws -> ZonesCore.GridLayout {
        let cols = try Percentages.parse(columns), rs = try Percentages.parse(rows)
        guard let margin = Double(outer), let spacing = Double(gap) else { throw LayoutError.invalidMargin }
        return try ZonesCore.GridLayout(columns: cols, rows: rs,
            merges: cols.count == draft.columns.count && rs.count == draft.rows.count ? draft.merges : [],
            outerMargin: margin, gap: spacing).validated()
    }

    private func apply() {
        do {
            let layout = try parsedLayout()
            try state.setLayout(layout, for: displayID)
            load(displayID)
        } catch { self.error = error.localizedDescription }
    }

    private func merge() {
        do {
            var layout = try parsedLayout(); try layout.merge(zoneIDs: selection)
            draft = layout; selection.removeAll(); error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func unmerge() {
        do {
            var layout = try parsedLayout(); layout.unmerge(zoneIDs: selection)
            draft = layout; selection.removeAll(); error = nil
        } catch { self.error = error.localizedDescription }
    }
}

func openAccessibilitySettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
        NSWorkspace.shared.open(url)
    }
}
