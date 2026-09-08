#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

usage() {
    echo "Usage: ./scripts/release.sh [version]"
    echo "Builds an optimized app, ZIP, and SHA-256 file in dist/."
    echo "The optional version (e.g. 0.2.0) overrides only the packaged app's version."
    echo "Optional environment: APP_BUILD, SIGNING_IDENTITY. Nothing is uploaded."
}
if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    usage
    exit 0
fi
if [ "$#" -gt 1 ]; then
    usage >&2
    exit 64
fi
if [ "$#" -eq 1 ]; then
    if ! [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "Version must have the form 1.2.3." >&2
        exit 64
    fi
    export APP_VERSION="$1"
fi

source scripts/signing.sh
nfz_resolve_signing_identity
SIGNING_IDENTITY="$NFZ_SIGNING_IDENTITY" CONFIGURATION=release ./scripts/build.sh
bundle="$PWD/dist/Not Fancy Zones.app"
version="$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$bundle/Contents/Info.plist")"
if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "The bundle version must have the form 1.2.3 before packaging." >&2
    exit 64
fi
architectures="$(/usr/bin/lipo -archs "$bundle/Contents/MacOS/NotFancyZones")"
case "$architectures" in
    arm64) architecture="arm64" ;;
    x86_64) architecture="x86_64" ;;
    "x86_64 arm64"|"arm64 x86_64") architecture="universal" ;;
    *) echo "Unexpected executable architectures: $architectures" >&2; exit 1 ;;
esac
archive_name="Not-Fancy-Zones-${version}-macos-${architecture}.zip"
release_work_dir="$(mktemp -d "$PWD/dist/.release.XXXXXX")"
trap 'rm -rf "$release_work_dir"' EXIT

# Preserve the app directory, executable permissions, resource forks, and signature.
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$bundle" "$release_work_dir/$archive_name"

# Validate the actual downloadable archive, not just the pre-archive app.
/usr/bin/ditto -x -k "$release_work_dir/$archive_name" "$release_work_dir/unpacked"
unpacked_app="$release_work_dir/unpacked/Not Fancy Zones.app"
test -x "$unpacked_app/Contents/MacOS/NotFancyZones"
codesign --verify --strict "$unpacked_app"
cmp "$bundle/Contents/Resources/AppIcon.icns" "$unpacked_app/Contents/Resources/AppIcon.icns"
cmp LICENSE "$unpacked_app/Contents/Resources/LICENSE"
(
    cd "$release_work_dir"
    /usr/bin/shasum -a 256 "$archive_name" > "$archive_name.sha256"
)
mv "$release_work_dir/$archive_name" "$PWD/dist/$archive_name"
mv "$release_work_dir/$archive_name.sha256" "$PWD/dist/$archive_name.sha256"

echo "Release ZIP: $PWD/dist/$archive_name"
echo "SHA-256:     $PWD/dist/$archive_name.sha256"
echo "Architecture: $architectures; minimum macOS: $(/usr/bin/plutil -extract LSMinimumSystemVersion raw "$bundle/Contents/Info.plist")"
if [ "$NFZ_SIGNING_KIND" = "adhoc" ]; then
    echo "Signing: ad hoc. This archive has not been notarized by Apple."
else
    echo "Signed with: $NFZ_SIGNING_NAME. This script does not perform notarization."
fi
