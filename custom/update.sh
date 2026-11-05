#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

repo=timofey97/desktop-plus
installed="/Applications/Desktop Plus.app"
state="$HOME/.local/state/desktop-plus-custom-build"

install_app() {
  local app="$1" label="$2"
  if pgrep -qf "$installed/Contents/MacOS/"; then
    echo "Quitting Desktop Plus..."
    osascript -e 'quit app "Desktop Plus"'
    while pgrep -qf "$installed/Contents/MacOS/"; do sleep 1; done
  fi
  rm -rf "$installed"
  ditto "$app" "$installed"
  xattr -dr com.apple.quarantine "$installed" 2>/dev/null || true
  mkdir -p "$(dirname "$state")"
  echo "$label" > "$state"
  echo "Installed $label"
  open "$installed"
}

if [ "${1:-}" = "--local" ]; then
  source "$HOME/.nvm/nvm.sh"
  nvm install >/dev/null
  nvm use >/dev/null
  yarn install --frozen-lockfile
  yarn build:prod
  arch="$(uname -m)"
  [ "$arch" = "x86_64" ] && arch="x64"
  dirty=""
  git diff --quiet HEAD || dirty="+dirty"
  install_app "dist/Desktop Plus-darwin-$arch/Desktop Plus.app" "local-$(git rev-parse --short HEAD)$dirty"
  exit 0
fi

tag=$(gh release view --repo "$repo" --json tagName --jq .tagName)
if [ "$(cat "$state" 2>/dev/null)" = "$tag" ]; then
  echo "Already on the latest build ($tag)."
  exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
echo "Downloading $tag..."
gh release download "$tag" --repo "$repo" --pattern '*.zip' --dir "$tmp"
ditto -x -k "$tmp"/*.zip "$tmp/app"
install_app "$tmp/app/Desktop Plus.app" "$tag"
