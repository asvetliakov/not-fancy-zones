#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if pgrep -x NotFancyZones >/dev/null; then
    echo "Quit Not Fancy Zones before E2E testing to avoid two instances handling the same drag."
    exit 1
fi
./scripts/build.sh
swift build -c release --product ZoneTestWindow
binary_dir="$(swift build -c release --show-bin-path)"
run_dir="$PWD/test-results/$(date +%Y%m%d-%H%M%S)"
fixture="$run_dir/Zone Test Window.app"
mkdir -p "$fixture/Contents/MacOS"
cp "$binary_dir/ZoneTestWindow" "$fixture/Contents/MacOS/ZoneTestWindow"
cat > "$fixture/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>app.notfancyzones.fixture</string>
<key>CFBundleExecutable</key><string>ZoneTestWindow</string>
<key>CFBundleName</key><string>Zone Test Window</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
codesign --force --sign - "$fixture"
echo "Tests briefly move two disposable windows and the pointer. Avoid using the mouse until they finish."
open -n "$PWD/dist/Not Fancy Zones.app" --env "NFZ_FIXTURE_NO_HIT_TEST=${NFZ_FIXTURE_NO_HIT_TEST:-0}" --args --integration-test "$run_dir/report.json" "$fixture/Contents/MacOS/ZoneTestWindow"
for ((attempt=0; attempt<60; attempt++)); do
    if [ -f "$run_dir/report.json" ]; then
        cat "$run_dir/report.json"
        /usr/bin/plutil -extract passed raw "$run_dir/report.json" | /usr/bin/grep -q true
        exit $?
    fi
    sleep 1
done
echo "Timed out. No report at $run_dir/report.json"
exit 1
