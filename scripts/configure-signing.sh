#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "$#" -ne 1 ] || [ "${1:-}" = "--help" ]; then
    echo 'Usage: ./scripts/configure-signing.sh "Developer ID Application: Your Name (TEAMID)"'
    echo 'Selects an already-installed certificate for all future local builds and releases.'
    echo 'List available certificates with: security find-identity -v -p codesigning'
    if [ "${1:-}" = "--help" ]; then exit 0; fi
    exit 64
fi
if [ "$1" = "-" ]; then
    echo "Choose a certificate to preserve identity across updates; ad-hoc signing cannot do that." >&2
    exit 64
fi
export SIGNING_IDENTITY="$1"
source scripts/signing.sh
nfz_resolve_signing_identity
umask 077
printf '%s\n' "$NFZ_SIGNING_NAME" > .signing-identity
echo "Saved signing identity: $NFZ_SIGNING_NAME"
echo "Configuration: $PWD/.signing-identity (gitignored). Keychain was not modified."
