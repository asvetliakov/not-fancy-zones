#!/bin/bash
# Shared by build/release/configure-signing. Read configuration as data, never shell code.
# Call from the repository root. No Keychain changes are made here.
nfz_resolve_signing_identity() {
    local requested available line fingerprint certificate_name
    if [ "${SIGNING_IDENTITY+x}" = x ]; then
        requested="$SIGNING_IDENTITY"
    elif [ -f .signing-identity ]; then
        requested="$(cat .signing-identity)"
    else
        requested="-"
    fi
    if [ -z "$requested" ] || [[ "$requested" == *$'\n'* ]] || [[ "$requested" == *$'\r'* ]]; then
        echo "Signing identity must be one nonempty certificate name or fingerprint." >&2
        return 64
    fi
    NFZ_SIGNING_IDENTITY="$requested"
    NFZ_SIGNING_NAME="$requested"
    NFZ_SIGNING_KIND="adhoc"
    if [ "$requested" = "-" ]; then return 0; fi
    available="$(/usr/bin/security find-identity -v -p codesigning)" || return 1
    while IFS= read -r line; do
        if [[ "$line" =~ [[:xdigit:]]{40} ]]; then
            fingerprint="${BASH_REMATCH[0]}"
            certificate_name="${line#*\"}"
            certificate_name="${certificate_name%\"*}"
            if [ "$requested" = "$certificate_name" ] || [ "$requested" = "$fingerprint" ]; then
                NFZ_SIGNING_IDENTITY="$fingerprint"
                NFZ_SIGNING_NAME="$certificate_name"
                case "$certificate_name" in
                    "Developer ID Application:"*) NFZ_SIGNING_KIND="developer-id" ;;
                    *) NFZ_SIGNING_KIND="certificate" ;;
                esac
                return 0
            fi
        fi
    done <<< "$available"
    echo "Configured signing identity is unavailable: $requested" >&2
    echo "Install its certificate/private key in Keychain, or run scripts/configure-signing.sh with a valid identity." >&2
    echo "The build will not fall back to ad-hoc signing because that would change Accessibility identity." >&2
    return 1
}
