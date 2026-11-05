#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

rebuild=0
if [ "${1:-}" = "--rebuild" ]; then
  rebuild=1
  shift
fi

if [ -n "$(git status --porcelain)" ]; then
  echo "Working tree has uncommitted changes, commit or stash them first."
  exit 1
fi

git switch -q custom
git fetch -q upstream --tags

target="${1:-$(git tag -l 'v*' --sort=-v:refname | grep -E '^v[0-9]+(\.[0-9]+)+$' | head -1)}"

if git merge-base --is-ancestor "$target" HEAD; then
  echo "Already contains $target."
  if [ "$rebuild" = 0 ]; then
    echo "Nothing to do. Use --rebuild to build and install anyway."
    exit 0
  fi
else
  echo "Merging $target..."
  if ! git merge --no-edit "$target"; then
    echo
    echo "Merge conflict. Resolve it, commit, then run: custom/update.sh --rebuild"
    exit 1
  fi
fi

source "$HOME/.nvm/nvm.sh"
nvm install >/dev/null
nvm use >/dev/null

yarn install --frozen-lockfile
yarn build:prod

arch="$(uname -m)"
[ "$arch" = "x86_64" ] && arch="x64"
built="dist/Desktop Plus-darwin-$arch/Desktop Plus.app"
installed="/Applications/Desktop Plus.app"

if pgrep -qf "$installed/Contents/MacOS/"; then
  echo "Quitting Desktop Plus..."
  osascript -e 'quit app "Desktop Plus"'
  while pgrep -qf "$installed/Contents/MacOS/"; do sleep 1; done
fi

rm -rf "$installed"
ditto "$built" "$installed"
echo "Installed $(defaults read "$installed/Contents/Info" CFBundleShortVersionString) from $(git rev-parse --short HEAD)"

git push -q origin custom
open "$installed"
