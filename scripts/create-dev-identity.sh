#!/bin/zsh
set -euo pipefail

name="Voxly Local Development"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$tmp/key.pem" -out "$tmp/cert.pem" \
  -subj "/CN=$name/O=Voxly/" \
  -addext "keyUsage=digitalSignature" \
  -addext "extendedKeyUsage=codeSigning"
openssl pkcs12 -export -legacy -out "$tmp/identity.p12" -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -passout pass:voxly-local
security add-trusted-cert -d -r trustRoot -p codeSign -k "$HOME/Library/Keychains/login.keychain-db" "$tmp/cert.pem"
security import "$tmp/identity.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P voxly-local -T /usr/bin/codesign
echo "$name"
