#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${CONFIGURATION:-release}"
source scripts/signing.sh
nfz_resolve_signing_identity
if [ -n "${APP_VERSION:-}" ] && ! [[ "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "APP_VERSION must have the form 1.2.3." >&2
    exit 64
fi
if [ -n "${APP_BUILD:-}" ] && ! [[ "$APP_BUILD" =~ ^[0-9]+$ ]]; then
    echo "APP_BUILD must be a numeric build number." >&2
    exit 64
fi
./scripts/build-icon.sh
swift build -c "$configuration" --product NotFancyZones
binary_dir="$(swift build -c "$configuration" --show-bin-path)"
destination="$PWD/dist/Not Fancy Zones.app"
mkdir -p dist
app_work_dir="$(mktemp -d "$PWD/dist/.app-build.XXXXXX")"
build_installed=false
cleanup() {
    if [ "$build_installed" = false ] && [ -e "$app_work_dir/previous.app" ]; then
        echo "Previous app preserved at: $app_work_dir/previous.app" >&2
    else
        rm -rf "$app_work_dir"
    fi
}
trap cleanup EXIT
bundle="$app_work_dir/Not Fancy Zones.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$binary_dir/NotFancyZones" "$bundle/Contents/MacOS/NotFancyZones"
cp Resources/Info.plist "$bundle/Contents/Info.plist"
cp Resources/AppIcon.icns "$bundle/Contents/Resources/AppIcon.icns"
cp LICENSE "$bundle/Contents/Resources/LICENSE"
if [ -n "${APP_VERSION:-}" ]; then
    /usr/bin/plutil -replace CFBundleShortVersionString -string "$APP_VERSION" "$bundle/Contents/Info.plist"
fi
if [ -n "${APP_BUILD:-}" ]; then
    /usr/bin/plutil -replace CFBundleVersion -string "$APP_BUILD" "$bundle/Contents/Info.plist"
fi
# Keep the bundle ID and certificate-based designated requirement stable across versions.
/usr/bin/plutil -replace NFZSigningKind -string "$NFZ_SIGNING_KIND" "$bundle/Contents/Info.plist"
signing_options=(--force --sign "$NFZ_SIGNING_IDENTITY" --identifier app.notfancyzones)
if [ "$NFZ_SIGNING_KIND" = "developer-id" ]; then
    signing_options+=(--options runtime --timestamp)
elif [ "$NFZ_SIGNING_KIND" = "certificate" ]; then
    signing_options+=(--options runtime --timestamp=none)
fi
codesign "${signing_options[@]}" "$bundle"
codesign --verify --strict "$bundle"
# Do not overwrite the executable of a running instance in place. Keep the previous
# bundle until the fully signed replacement is ready, and restore it if moving fails.
if [ -e "$destination" ]; then mv "$destination" "$app_work_dir/previous.app"; fi
if ! mv "$bundle" "$destination"; then
    if [ -e "$app_work_dir/previous.app" ]; then mv "$app_work_dir/previous.app" "$destination"; fi
    exit 1
fi
build_installed=true
echo "Built: $destination"
echo "Signing: $NFZ_SIGNING_KIND ($NFZ_SIGNING_NAME)"
if pgrep -x NotFancyZones >/dev/null; then echo "A copy is running. Restart it to use this build."; fi
