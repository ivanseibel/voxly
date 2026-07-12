#!/bin/zsh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
app="$root/build/Voxly.app"

swift build --package-path "$root"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$root/.build/debug/Voxly" "$app/Contents/MacOS/Voxly"
cp "$root/Info.plist" "$app/Contents/Info.plist"
identity="${VOXLY_SIGNING_IDENTITY:-$(security find-identity -v -p codesigning | awk -F '"' '/Voxly Local Development/ { print $1 }' | awk '{print $2; exit}')}"
if [[ -z "$identity" ]]; then
  echo "Missing Voxly Local Development signing identity" >&2
  exit 1
fi
codesign --force --sign "$identity" "$app"
echo "$app"
