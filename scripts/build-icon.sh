#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source_image="Resources/Artwork/AppIcon-Source.png"
destination="Resources/AppIcon.icns"

if [ -f "$destination" ] && [ "$destination" -nt "$source_image" ] && [ "$destination" -nt scripts/build-icon.sh ]; then
    exit 0
fi

icon_work_dir="$(mktemp -d "${TMPDIR:-/tmp}/not-fancy-zones-icon.XXXXXX")"
trap 'rm -rf "$icon_work_dir"' EXIT
iconset="$icon_work_dir/AppIcon.iconset"
mkdir -p "$iconset"

# Native macOS tools preserve the generated transparency; no extra dependencies.
for size in 16 32 128 256 512; do
    /usr/bin/sips --resampleHeightWidth "$size" "$size" "$source_image" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    retina_size=$((size * 2))
    /usr/bin/sips --resampleHeightWidth "$retina_size" "$retina_size" "$source_image" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
/usr/bin/iconutil --convert icns "$iconset" --output "$icon_work_dir/AppIcon.icns"
mv "$icon_work_dir/AppIcon.icns" "$destination"
echo "Generated: $destination"
