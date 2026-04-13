#!/bin/bash
# Creates a local self-signed code-signing certificate on first run.
# Subsequent runs detect the existing cert and exit immediately (no-op).
# Does NOT require an Apple Developer account.

CERT_NAME="${1:-PhemeMurmurDev}"
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"

# Already exists — silent no-op
if security find-certificate -c "$CERT_NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    exit 0
fi

echo "→ First-time setup: creating local code signing certificate '$CERT_NAME'..."

TMPDIR="$(mktemp -d)"
cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT

# OpenSSL config with code signing extensions
cat > "$TMPDIR/cert.conf" << EOF
[req]
prompt = no
distinguished_name = dn
x509_extensions = codesign

[dn]
CN = ${CERT_NAME}

[codesign]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF

# Generate 2048-bit RSA private key
if ! openssl genrsa -out "$TMPDIR/key.pem" 2048 2>/dev/null; then
    echo "✗ Failed to generate private key" >&2; exit 1
fi

# Self-signed certificate, valid 10 years
if ! openssl req -new -x509 \
    -key "$TMPDIR/key.pem" \
    -out "$TMPDIR/cert.pem" \
    -days 3650 \
    -config "$TMPDIR/cert.conf" 2>/dev/null; then
    echo "✗ Failed to create certificate" >&2; exit 1
fi

# Import key and cert as separate PEM files — avoids PKCS12 encryption
# compatibility issues between LibreSSL and macOS Keychain.
# macOS Keychain auto-links them via matching public key.
# -A: allow codesign to access without per-use prompts.
if ! security import "$TMPDIR/key.pem" -k "$KEYCHAIN" -A 2>/dev/null; then
    echo "✗ Failed to import private key" >&2; exit 1
fi

if ! security import "$TMPDIR/cert.pem" -k "$KEYCHAIN" -A 2>/dev/null; then
    echo "✗ Failed to import certificate" >&2; exit 1
fi

echo "→ Certificate '$CERT_NAME' is ready. Future builds will be silent."
