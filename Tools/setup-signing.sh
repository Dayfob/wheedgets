#!/bin/zsh
# Creates a stable, self-signed code-signing identity, "Wheedgets Local Signing",
# in its own keychain. build.sh picks it up automatically.
#
# Why: macOS ties the Accessibility grant to the app's code signature. Ad-hoc
# signatures change on every build, so the grant would silently stop working
# after each rebuild. A fixed identity keeps it.
#
# Free, offline, and idempotent. It does not replace Apple notarization: builds
# downloaded by other people still need a Developer ID for Gatekeeper.
#
# Undo: security delete-keychain ~/Library/Keychains/wheedgets-signing.keychain-db
set -euo pipefail

IDENTITY="Wheedgets Local Signing"
KEYCHAIN="$HOME/Library/Keychains/wheedgets-signing.keychain-db"
PASSWORD="wheedgets-signing"

identity_can_sign() {
    # The keychain locks after every reboot; a locked keychain cannot sign.
    security unlock-keychain -p "$PASSWORD" "$KEYCHAIN" 2>/dev/null || true
    local probe
    probe="$(mktemp)"
    cp /usr/bin/true "$probe"
    local result=1
    codesign --force --sign "$IDENTITY" "$probe" >/dev/null 2>&1 && result=0
    rm -f "$probe"
    return $result
}

if identity_can_sign; then
    echo "✓ Signing identity already installed."
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
    -subj "/CN=$IDENTITY" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -addext "basicConstraints=critical,CA:false" 2>/dev/null

# Explicit legacy algorithms: /usr/bin/openssl is LibreSSL, and security(1)
# does not reliably import OpenSSL 3's newer PKCS#12 defaults.
openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -out "$WORK/identity.p12" -passout pass:"$PASSWORD" -name "$IDENTITY" \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1

security delete-keychain "$KEYCHAIN" 2>/dev/null || true
security create-keychain -p "$PASSWORD" "$KEYCHAIN"
security set-keychain-settings "$KEYCHAIN"   # no auto-lock timeout
security unlock-keychain -p "$PASSWORD" "$KEYCHAIN"
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASSWORD" "$KEYCHAIN" >/dev/null

# Add to the user search list, keeping the existing keychains.
EXISTING=(${(f)"$(security list-keychains -d user | sed -e 's/^ *"//' -e 's/"$//')"})
security list-keychains -d user -s "$KEYCHAIN" "${EXISTING[@]}"

identity_can_sign || {
    echo "✗ Identity imported, but codesign cannot use it." >&2
    exit 1
}
echo "✓ Created '$IDENTITY'. ./build.sh will use it from now on."
