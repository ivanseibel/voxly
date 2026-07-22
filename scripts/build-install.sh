#!/bin/zsh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
packager="$root/scripts/package-app.sh"

if [[ ! -f "$packager" ]]; then
  echo "Missing packager script: $packager" >&2
  exit 1
fi

echo "Building and packaging Voxly..."
app_path="$(zsh "$packager" | tail -n 1)"

if [[ ! -d "$app_path" ]]; then
  echo "Packager did not produce an app bundle: $app_path" >&2
  exit 1
fi

install_dir="${VOXLY_INSTALL_DIR:-/Applications}"
if [[ "$install_dir" == "/Applications" && ! -w "$install_dir" ]]; then
  install_dir="$HOME/Applications"
  mkdir -p "$install_dir"
  echo "No write access to /Applications. Installing to $install_dir instead."
fi

target_app="$install_dir/Voxly.app"

echo "Installing to $target_app..."
rm -rf "$target_app"
ditto "$app_path" "$target_app"

# Keep local installs smooth when launched from Finder after copy.
xattr -dr com.apple.quarantine "$target_app" 2>/dev/null || true

echo "Installed: $target_app"

if [[ "${VOXLY_OPEN_AFTER_INSTALL:-1}" == "1" ]]; then
  echo "Opening Voxly..."
  open "$target_app"
fi
