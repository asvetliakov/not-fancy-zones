# Validation report

Validated locally on **2026-09-09**, macOS 26.6.2, Apple Silicon, Swift 6.3.3, using only Xcode Command Line Tools. App version: 0.1.0. The original functional/performance build was approximately **1 MiB** on disk; the bundle with the added multi-resolution application icon is approximately **2.7 MiB**.

## Final review before publication

Reviewed the full Swift sources, native event/AX lifecycle, persistence, and packaging scripts. Fixed these issues before committing:

- Cancelled drag hit tests and frame reads now stop before queued cross-process work; fallback enumeration also checks cancellation. Scan callbacks cannot restore windows after permission is revoked.
- Invalid layout fields show unapplied changes, and synchronous settings-save errors are reported instead of silently discarded.
- Installation stages and verifies a complete replacement bundle instead of merging into an older app. Both build and install preserve the previous bundle if replacement/rollback fails. The install guard was tested with an app running; an actual installation to `~/Applications` was not performed in this review.
- The original repository’s MIT license is preserved and included in release bundles. ZIP validation checks its exact contents alongside the signature and icon.

Validation on the final packaged executable: **20 core tests**, **23 normal native integration checks**, and **24 missing-hit-test integration checks** passed. The native tests include cancelled lookup/frame/placement work, both displays, simulated reconnect, overlays, fitting, content drag rejection, and app relaunch. Reports: `test-results/final-review/{normal,no-hit}/report.json`. These runs launched the bundled executable directly from the authorized development host; they do not establish permission persistence across ad-hoc rebuilds. All shell scripts passed syntax checks, the Python measurement script compiled, and the release ZIP signature/checksum/license verification passed. The staged source was checked for whitespace errors and credential patterns; build outputs, local preferences, test reports, and signing material are excluded from Git.

Fresh idle measurement of the optimized bundled app, settings closed, restoration enabled, **seven remembered windows across five currently running saved applications**: **0.03 CPU seconds over 30.020 seconds (0.100% of one core)**; RSS ended at **64.11 MiB**, and the two-second stack sample reported an **11.3 MB physical footprint** with threads waiting in the event loop/kernel. No new polling, repeating timers, display links, or idle overlays were introduced. Raw measurement and stack sample: `test-results/final-review/idle.json` and `idle-sample.txt`. GPU/WindowServer attribution and the physical/manual checks listed below remain untested.

## Telegram compatibility follow-up

Investigated Telegram 12.9 (`ru.keepcoder.Telegram`) on the attached displays. Direct read-only probes found a normal `AXStandardWindow` with readable geometry, while pointer hit testing returned `AXError.notImplemented` (-25208). The missing hit result prevented drag tracking before the Shift check.

Added a fallback only when AX hit testing cannot resolve a window: front-to-back on-screen metadata chooses the actual foreground window; a unique matching AX frame is required. Nonzero-layer panels and our own windows block selection of underlying apps. Candidate enumeration is capped at 32, with a 250 ms frame-scan deadline checked between bounded AX calls. No idle scan, screen capture, or new timer was added. The live Telegram lookup completed in approximately 17 ms.

Live synthesized Shift-drag then exposed a second issue: `AXEnhancedUserInterface` was enabled and separate animated size/position writes conflicted. Temporarily disabling it for the placement transaction and restoring it with `defer` fixed fitting. Telegram applies that flag change even when its setter returns `notImplemented`, so restoration runs after every attempted suspension and completes before the fit callback. A real Telegram Shift-drag showed overlays, filled a 1731.36 × 1393 point zone to the expected integer-rounded frame (1731 × 1393), and released all overlay panels afterward. The test used isolated preferences and restored the window frame; no chat interaction occurred.

The new core regression checks cover foreground occlusion, transparent windows, own-process exclusion, negative coordinates, and geometry matching. **20 core tests passed.** The native fixture does not expose the enhanced Accessibility flag, so that compatibility path was exercised on real Telegram instead. Native integration checks include an opt-in fixture application that reproduces `AXError.notImplemented` hit testing. Final runs passed **20/20 normal integration checks** and **21/21 missing-hit-test checks**, with reports at `test-results/telegram/normal/report.json` and `test-results/telegram/no-hit/report.json`. A separate real-Telegram check verified that enhanced Accessibility remained enabled after fitting and restoring its pre-test geometry. The release ZIP was rebuilt and validated. The integration executables were launched directly from the release build under the authorized development host, so these checks do not assert permission persistence for a newly ad-hoc-signed bundle.

## Menu/sidebar icon and permission feedback follow-up

The final artwork is the restored blue/cyan design. The graphite alternative is archived in `Resources/Artwork/AppIcon-Graphite.png`. The menu bar and sidebar now load the shared ICNS lazily once; no timer or animation was introduced.

- Rebuilt the release ZIP after restoring blue; archive extraction, signature, executable permissions, and icon comparison passed. All 19 core tests passed with the new Swift changes.
- Verified the denied **Check again** state displays an explicit explanation and check timestamp. Verified **Restart app** replaces the process with a single new instance and reopens Settings.
- The old Accessibility switch was on while the running rebuilt app reported denied. Removed the stale entry; automated re-add was not completed because native file chooser interactions repeatedly targeted unexpected locations. The current bundle needs to be added again before snapping or fresh E2E testing. No successful authorization recovery is claimed for this follow-up.
- Added persistent certificate selection, explicit failure for unavailable configured certificates, signing-kind metadata, and staging/verification before replacing the app bundle. Shell syntax and invalid-certificate failure checks passed; no certificate or private key was created or imported. Developer ID persistence remains untested because certificate setup was deferred by the user.
- Earlier 20-check E2E and idle measurements below describe the previous functional build, not this follow-up. The new permission check is one user-triggered query; no idle polling was added.

## Icon and release packaging follow-up

Added the generated source artwork, a native `.icns` build script, the bundle icon reference, and a release ZIP script. This follow-up changes artwork, packaging scripts, and bundle metadata; the application Swift code is unchanged. The functional and idle measurements below were taken before the artwork addition, rather than repeated for an asset-only update.

- Inspected the generated artwork and its extracted 128-pixel and 32-pixel representations.
- Round-tripped the `.icns` with `iconutil`; all ten 1×/2× representations have the expected dimensions (16–1024 pixels) and retain alpha.
- Release build, shell syntax, plist validation, and strict bundle signature checks passed.
- `./scripts/release.sh` produced `dist/Not-Fancy-Zones-0.1.0-macos-arm64.zip` and its SHA-256 file. The script extracted the archive and verified its signature, executable bit, and exact icon contents; the final checksum verified successfully.
- Tested `APP_BUILD=42 CONFIGURATION=debug ./scripts/release.sh 0.1.1`: it still built for production, packaged version 0.1.1/build 42, and left the source plist at 0.1.0/build 1. Test-only archives were moved under `test-results/release-validation/`, then the default release was regenerated.
- Invalid versions and excess arguments exited with status 64 without changing the existing bundle. Verified that the archive contains the app/icon and excludes Swift source and local settings.
- Fixed compatibility with macOS's Bash 3.2: signing arguments use a nonempty array so `set -u` does not reject an empty optional-arguments array.
- Developer ID signing is supported with hardened runtime and a timestamp, but was not exercised because no certificate was supplied. No notarization or GitHub upload was performed; the generated release ZIP is ad-hoc signed and not notarized.

## Automated checks

`./scripts/test.sh`: **19 tests passed**, including percentage correction and rejection, all 144 combinations of 1–12 columns/rows, gaps and margins, merges/unmerges, negative monitor origins, drag/resize classification, atomic persistence, corrupt settings, and conservative window identity matching.

`./scripts/build.sh`: optimized release build passed without warnings; bundle plist and strict code signature verification passed. Shell syntax checks and Python compilation checks passed.

`./scripts/e2e.sh`: **20 checks passed** on the earlier functional binary. Full local report: `test-results/20260909-021045/report.json` (generated artifacts are gitignored).

- Both disposable native fixture windows exposed independently, with automatic window tabbing disabled.
- Merged-zone fitting on the 5120 × 1440 Odyssey G95SD and on the MacBook's 1512 × 982 logical-point screen.
- Actual resulting AX window frames matched expected positions and sizes within two points, including the MacBook's negative global X origin.
- Application-enforced minimum window size respected.
- **Simulated** external-display removal fitted the window to the remaining screen, retained its home display UUID, and restored its full zone when the display returned to the simulated topology.
- Actual synthesized title-bar dragging with Shift pressed after drag initiation showed overlays on both monitors, highlighted the target, and filled it on drop.
- Overlay visibility and allocated panel count both returned to zero after drop.
- Content dragging did not show overlays or move the window.
- Relaunching the fixture application restored its remembered zone and size.
- Releasing Shift during a drag hid the overlays; an ordinary drop released the assignment and preserved the manually moved window size.

An earlier fixture run exposed a test gap: macOS had combined the two fixture windows into tabs. That fixture issue was corrected, and the final run explicitly asserts that two independent standard windows exist. Missing constrained windows now fail the test rather than silently skipping it.

## Native UI checks

The running settings editor was inspected through macOS Accessibility and a screenshot. Verified both connected display selectors, live preview, `57 10` → `57 43` columns, `50 30` → `50 50` rows, four-cell rectangular merge, unmerge back to six cells, and rejection of `70 40 30` without overwriting the saved layout. Confirmed saved configuration survives app restarts. Standard application/Edit/Window menus were added after discovering that the original menu-bar-only implementation did not handle Command-Q.

The external display is left configured with `34 33 33` columns, `50 50` rows, cells 0/1/3/4 merged into the large left zone, and eight-point margins/gaps. The MacBook keeps its separate two-column layout. All disposable test window assignments were removed after measurement, and the original configuration was restored.

## Performance measurements

Measured the optimized app with Accessibility granted, both monitors connected, and **one remembered live fixture window**, so restoration observers were active. No overlays were visible. CPU figures are cumulative process CPU-time deltas divided by wall time; `ps` has centisecond CPU-time resolution.

| State | Wall time | CPU time used | Average CPU, one core | RSS at end | Physical footprint from `sample` |
| --- | ---: | ---: | ---: | ---: | ---: |
| Menu bar, before opening Settings | 30.016 s | 0.01 s | 0.033% | 60.88 MiB | 13.2 M |
| Settings opened, then closed | 30.016 s | 0.00 s | 0.000% at measurement resolution | 113.17 MiB | 32.8 M |

RSS includes resident shared frameworks and is not the same metric as the physical footprint. Opening SwiftUI settings loads frameworks/caches that macOS retains even after the view tree is released.

Two `top` samples showed **0.0% CPU, zero idle wakeups, and three threads**. A three-second stack sample before Settings and a one-second sample after closing Settings showed every sampled thread waiting in the kernel/event loop, with no drawing, polling, or resizing loop on the stacks. Measurements and stack samples are under `test-results/idle-observers/`.

Source review found and addressed:

- Blocking AX work: runs off the UI thread on a serial queue with bounded messaging timeouts.
- Stale queued restores: cancellation tokens are invalidated by new drags, pause, topology/layout changes, and forgetting assignments; setters recheck tokens before mutation.
- Event burst backlogs: per-process scans are debounced and coalesced, with at most one scan per process in flight.
- Unnecessary observation: only apps with remembered placements are scanned/observed; unrelated application title updates do not trigger AX enumeration.
- Redundant drag computation: zone geometry is cached, and frame checks stop after movement is confirmed.
- Idle rendering: no repeating timers/display links/ordinary mouse-move subscription; overlays close after use and redraw only on highlight changes.
- Hidden editor work: closing Settings releases the SwiftUI view tree.
- Resize feedback: at most one settling correction per fit, with native size constraints accepted.

These short measurements support very low idle overhead on this machine; they are not a universal performance guarantee. GPU and WindowServer utilization were **not directly attributed with a GPU profiler**. Overlay panel disposal, the lack of an idle drawing loop, and sleeping thread samples were verified.

## Remaining manual checks and platform limitations

- Physical cable disconnect/reconnect, laptop lid/clamshell transitions, sleep/wake, arbitrary Spaces/full-screen workflows, and changing display scaling/arrangement were not physically exercised. The monitor transition test used simulated topology over the real attached screens.
- Dock auto-hide was enabled during testing, and the work-area geometry respected it. Menu-bar auto-hide was off; toggling it was not tested. The implementation uses macOS's `NSScreen.visibleFrame`, including any reserved notch/safe area.
- Login item registration is implemented but has not been verified through an actual logout/login.
- Compatibility with every third-party app cannot be guaranteed: Accessibility support, minimum sizes, protected/nonstandard windows, and ambiguous window identities vary.
- Ad-hoc signing changes the code identity on rebuild. This was observed to invalidate Accessibility authorization. Toggling the stale entry was insufficient; removing and re-adding the exact current bundle restored access. The final binary was then kept unchanged for testing. An optional stable signing identity is supported by the build script.
