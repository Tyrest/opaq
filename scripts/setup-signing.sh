#!/bin/bash
# Creates a local self-signed code-signing certificate named opaq-dev in the
# login keychain, if it is not already there.
#
# build_app.sh looks for this identity (override the name with
# OPAQ_SIGN_IDENTITY) and signs the app bundle with it. TCC recognizes a
# certificate-signed app across rebuilds. Ad-hoc signatures (--sign -) are
# tied to the cdhash, which changes whenever the binary changes, so macOS
# drops Full Disk Access after each rebuild.
#
# The private key is generated in a temp directory and deleted on exit.
# Do not commit the certificate, the key, or any .pem / .p12 file.

set -euo pipefail

IDENTITY="opaq-dev"
KEYCHAIN="$(security default-keychain -d user | sed -e 's/^[[:space:]]*"//' -e 's/"[[:space:]]*$//')"

identity_listed() {
    # -v lists only trusted identities. build_app.sh uses that form.
    security find-identity -v -p codesigning | grep -F -q -- "\"${IDENTITY}\""
}

identity_present() {
    security find-identity -p codesigning | grep -F -q -- "\"${IDENTITY}\""
}

print_trust_steps() {
    echo "${IDENTITY} is in the login keychain, but it is not a trusted code-signing identity yet."
    echo "build_app.sh only uses identities listed by: security find-identity -v -p codesigning"
    echo
    echo "Remaining manual step: open Keychain Access → login → ${IDENTITY} → Trust, and set Code Signing to Always Trust."
    echo "Then confirm:"
    echo "  security find-identity -v -p codesigning | grep ${IDENTITY}"
    echo
    echo "If codesign still cannot read the private key, run this once (it prompts for your login keychain password; do not save the password):"
    echo "  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k \"<login-keychain-password>\" \"${KEYCHAIN}\""
}

print_import_steps() {
    echo "Could not import ${IDENTITY} into the login keychain."
    if [[ -n "${1:-}" && -s "$1" ]]; then
        sed -n '1,20p' "$1"
    fi
    echo
    echo "Remaining manual step: run this script in Terminal and approve the login-keychain prompt:"
    echo "  scripts/setup-signing.sh"
    echo
    echo "If the certificate imports but codesign cannot use the private key, run this once"
    echo "(it prompts for your login keychain password; do not save the password):"
    echo "  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k \"<login-keychain-password>\" \"${KEYCHAIN}\""
}

if identity_listed; then
    echo "${IDENTITY} is already a valid code-signing identity. build_app.sh will use it."
    exit 0
fi

if identity_present || security find-certificate -c "${IDENTITY}" "${KEYCHAIN}" >/dev/null 2>&1; then
    print_trust_steps
    exit 1
fi

WORKDIR="$(mktemp -d)"
cleanup() {
    rm -rf "${WORKDIR}"
}
trap cleanup EXIT
umask 077

cat > "${WORKDIR}/codesign.cnf" <<EOF
[ req ]
prompt = no
distinguished_name = dn
x509_extensions = codesign_ext

[ dn ]
CN = ${IDENTITY}

[ codesign_ext ]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
EOF

if ! openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout "${WORKDIR}/key.pem" \
    -out "${WORKDIR}/cert.pem" \
    -config "${WORKDIR}/codesign.cnf" \
    >"${WORKDIR}/openssl-req.out" 2>"${WORKDIR}/openssl-req.err"
then
    echo "openssl could not create the code-signing certificate."
    sed -n '1,20p' "${WORKDIR}/openssl-req.err"
    exit 1
fi

# OpenSSL 3 defaults to PKCS#12 algorithms macOS `security import` rejects
# as a bad passphrase. -legacy with 3DES is the format the login keychain accepts.
P12_PASS="$(openssl rand -hex 16)"
if ! openssl pkcs12 -export -legacy \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg SHA1 \
    -inkey "${WORKDIR}/key.pem" \
    -in "${WORKDIR}/cert.pem" \
    -name "${IDENTITY}" \
    -out "${WORKDIR}/cert.p12" \
    -passout "pass:${P12_PASS}" \
    >"${WORKDIR}/openssl-p12.out" 2>"${WORKDIR}/openssl-p12.err"
then
    echo "openssl could not export the certificate."
    sed -n '1,20p' "${WORKDIR}/openssl-p12.err"
    exit 1
fi

echo "Importing ${IDENTITY} into the login keychain..."
set +e
security import "${WORKDIR}/cert.p12" \
    -k "${KEYCHAIN}" \
    -f pkcs12 \
    -P "${P12_PASS}" \
    -T /usr/bin/codesign \
    >"${WORKDIR}/import.out" 2>"${WORKDIR}/import.err"
IMPORT_STATUS=$?
set -e
unset P12_PASS

if [[ "${IMPORT_STATUS}" -ne 0 ]]; then
    print_import_steps "${WORKDIR}/import.err"
    exit 1
fi

if identity_listed; then
    echo "${IDENTITY} is ready. build_app.sh will sign with it so Full Disk Access survives rebuilds."
    exit 0
fi

if identity_present || security find-certificate -c "${IDENTITY}" "${KEYCHAIN}" >/dev/null 2>&1; then
    print_trust_steps
    exit 1
fi

print_import_steps "${WORKDIR}/import.err"
exit 1
