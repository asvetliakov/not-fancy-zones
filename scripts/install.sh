#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
destination="$HOME/Applications/Not Fancy Zones.app"
if pgrep -x NotFancyZones >/dev/null; then
    echo "Quit Not Fancy Zones before installing so its settings are flushed."
    exit 1
fi
./scripts/build.sh
mkdir -p "$HOME/Applications"
install_work_dir="$(mktemp -d "$HOME/Applications/.nfz-install.XXXXXX")"
installed=false
cleanup() {
    if [ "$installed" = false ] && [ -e "$install_work_dir/previous.app" ]; then
        echo "Previous app preserved at: $install_work_dir/previous.app" >&2
    else
        rm -rf "$install_work_dir"
    fi
}
trap cleanup EXIT
ditto "dist/Not Fancy Zones.app" "$install_work_dir/Not Fancy Zones.app"
codesign --verify --strict "$install_work_dir/Not Fancy Zones.app"
if pgrep -x NotFancyZones >/dev/null; then
    echo "Not Fancy Zones started during the build. Quit it and retry installation."
    exit 1
fi
# Replace the bundle instead of merging, so removed resources cannot linger.
if [ -e "$destination" ]; then mv "$destination" "$install_work_dir/previous.app"; fi
if ! mv "$install_work_dir/Not Fancy Zones.app" "$destination"; then
    if [ -e "$install_work_dir/previous.app" ]; then mv "$install_work_dir/previous.app" "$destination"; fi
    exit 1
fi
installed=true
echo "Installed: $destination"
open "$destination" --args --settings
