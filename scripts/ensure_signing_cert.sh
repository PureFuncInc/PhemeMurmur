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
openssl genrsa -out "$TMPDIR/key.pem" 2048 2>/dev/null

# Self-signed certificate, valid 10 years
openssl req -new -x509 \
    -key "$TMPDIR/key.pem" \
    -out "$TMPDIR/cert.pem" \
    -days 3650 \
    -config "$TMPDIR/cert.conf" 2>/dev/null

# Bundle as PKCS12 with empty password
openssl pkcs12 -export \
    -inkey "$TMPDIR/key.pem" \
    -in "$TMPDIR/cert.pem" \
    -out "$TMPDIR/cert.p12" \
    -passout pass: 2>/dev/null

# Import into login keychain.
# -A: allow codesign to access the key without per-use prompts.
# macOS may show one keychain dialog on the very first import — expected behaviour.
security import "$TMPDIR/cert.p12" \
    -k "$KEYCHAIN" \
    -P "" \
    -A

echo "→ Certificate '$CERT_NAME' is ready. Future builds will be silent."
