# Working on Not Fancy Zones

This is a native macOS 14+ menu bar utility, written in Swift/AppKit with a SwiftUI settings window. The user prioritizes **low idle CPU, GPU, and WindowServer activity** over animations or elaborate UI. No third-party packages, Electron, browser runtime, network service, or full Xcode installation is required.

## Build and validate

- `./scripts/test.sh` — geometry, input validation, persistence, and window matching tests.
- `./scripts/build.sh` — optimized, locally signed app at `dist/Not Fancy Zones.app`.
- `./scripts/release.sh [version]` — force a release build and create the versioned, architecture-labeled ZIP plus SHA-256 file in `dist/`. It extracts the archive and verifies the app before delivery. Packaging never uploads or notarizes. `APP_BUILD` and `SIGNING_IDENTITY` are optional; version/build overrides change only the built plist, before signing. Bundle the repository LICENSE and validate it in the extracted archive.
- `./scripts/build-icon.sh` — regenerate the multi-resolution `.icns` from `Resources/Artwork/AppIcon-Source.png` using native macOS tools; automatically called by the build. Preserve the source artwork and generation prompt in `Resources/Artwork/README.md`.
- `./scripts/configure-signing.sh "Developer ID Application: Your Name (TEAMID)"` — select an existing certificate in gitignored `.signing-identity`. No Keychain changes. Configured identities must never silently fall back to ad-hoc signing. Preserve the bundle ID and signing identity across updates.
- `./scripts/install.sh` — build and install to `~/Applications`; quit an existing instance first.
- `./scripts/e2e.sh` — real Accessibility and Shift-drag checks using disposable fixture windows. Requires user-enabled Accessibility for the built app; briefly takes over the mouse. Uses isolated settings under `test-results/`. Set `NFZ_FIXTURE_NO_HIT_TEST=1` for the Telegram-style hit-test regression.
- `./scripts/measure-idle.py PID --seconds 30` — cumulative CPU-time delta and RSS. Close settings and leave the desktop idle during measurement.

Read `README.md` for permissions, testing limitations, and macOS-specific behavior. Record real validation results in `VALIDATION.md`; distinguish automated, simulated, measured, and untested behavior. Never claim a hardware disconnect test based only on a simulated topology test.

## Architecture

- `Sources/ZonesCore/`: platform-independent layout geometry, percentage rules, persistent models, atomic JSON I/O, deterministic window matching.
- `AppState.swift`: UI state, persistent display UUIDs, `NSScreen.visibleFrame` work areas, debounced settings writes.
- `AccessibilityService.swift`: cross-process AX calls and AX observers. The click-only window-list fallback must respect frontmost occlusion and require a unique geometry match; never guess the focused window. Restore `AXEnhancedUserInterface` immediately after a placement transaction if it was temporarily suspended. All potentially blocking AX calls belong on its serial queue, not in mouse callbacks or on the main thread. AX messaging timeouts are bounded.
- `WindowCoordinator.swift`: mouse-drag state machine, one-shot restore work, live AX window identity, monitor reconnect handling.
- `OverlayController.swift`: click-through nonactivating panels, created only during a drag or explicit preview. Draw only when selection changes; close panels afterward.
- `AppIcon.swift`: lazily cached shared ICNS artwork for the status item and sidebar; no drawing timer.
- `SettingsView.swift`: per-display editor with live preview and explicit Apply, rectangular merge/unmerge, permission and login settings.
- `IntegrationRunner.swift` and `Sources/ZoneTestWindow/`: opt-in fixture testing, never regular startup behavior.

## Invariants

1. **No repeating idle timer, polling loop, display link, or idle overlay.** Event subscriptions are allowed. Debounce/coalesce event bursts and use only bounded one-shot retries. Avoid observing general window-move/resize events to repeatedly enforce sizes.
2. **Never resize in a loop.** Native applications may enforce minimum/maximum sizes. Fit once, optionally correct once after settling, and accept constraints.
3. **Do not snap content drags or resizes.** Confirm that a standard window translated while retaining its size. Shift can be pressed after the drag starts and released to cancel the overlay.
4. **Use consistent coordinates.** Core geometry and AX use top-left global points. Convert AppKit coordinates with `NSScreen.screens[0].frame.height`; `NSScreen.main` changes with focus and is not the primary screen.
5. **Percentages fill each axis.** Preserve leading values and correct the last value to the remainder. Reject nonfinite/negative/zero values, totals with no remainder, and more than 12 tracks. Changing the track counts resets incompatible merges.
6. **Merged cells must form a rectangle.** No overlapping, duplicated, or out-of-bounds cell memberships. Apply one inter-window gap, not twice the requested gap.
7. **Preserve home display identity on disconnect.** A temporary fallback placement must never overwrite its remembered monitor UUID. Manually dragging or resizing outside snapping releases that assignment.
8. **Avoid ambiguous restoration.** Match live AX elements first. Across restarts use a unique identifier, document, or title, with a conservative single-window fallback. Never map multiple live windows onto one saved record.
9. **Persist locally and atomically.** Settings live in `~/Library/Application Support/NotFancyZones/settings.json`. Preserve corrupt files before writing defaults. No telemetry. Titles/document URLs in settings are local user data; do not include them in diagnostics or commits.
10. **Review asynchronous races.** A stale hit-test, frame read, restore, or delayed resize must not affect a newer drag or a forgotten window. Invalidate work across topology changes, pause, and settings changes.

Keep changes native and focused. Add meaningful tests for geometry/state regressions. Run the appropriate tests and release build before delivery. Full Xcode, a developer account, or signing certificates are optional; ad-hoc signing can require Accessibility reauthorization after rebuilding.
