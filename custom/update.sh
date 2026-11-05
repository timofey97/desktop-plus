#!/bin/bash
set -euo pipefail

repo=timofey97/desktop-plus
installed="/Applications/Desktop Plus.app"
state_dir="$HOME/.local/state/desktop-plus-custom"
agent_label=com.timofey97.desktop-plus-update
agent_script="$HOME/.local/bin/desktop-plus-update"
agent_plist="$HOME/Library/LaunchAgents/$agent_label.plist"
agent_log="$HOME/Library/Logs/desktop-plus-update.log"
mode="${1:-}"

is_running() {
  pgrep -qf "$installed/Contents/MacOS/"
}

notify() {
  osascript -e "display notification \"$1\" with title \"Desktop Plus\""
}

install_app() {
  local app="$1" label="$2"
  if is_running; then
    echo "Quitting Desktop Plus..."
    osascript -e 'quit app "Desktop Plus"'
    while is_running; do sleep 1; done
  fi
  rm -rf "$installed"
  ditto "$app" "$installed"
  xattr -dr com.apple.quarantine "$installed" 2>/dev/null || true
  mkdir -p "$state_dir"
  echo "$label" > "$state_dir/installed"
  echo "$(date '+%F %T') Installed $label"
}

case "$mode" in
--install-agent)
  mkdir -p "$(dirname "$agent_script")" "$(dirname "$agent_plist")"
  cp "$0" "$agent_script"
  chmod +x "$agent_script"
  cat > "$agent_plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$agent_label</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$agent_script</string>
    <string>--auto</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>StartInterval</key>
  <integer>3600</integer>
  <key>StandardOutPath</key>
  <string>$agent_log</string>
  <key>StandardErrorPath</key>
  <string>$agent_log</string>
</dict>
</plist>
PLIST
  launchctl bootout "gui/$(id -u)/$agent_label" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$agent_plist"
  echo "Auto-update agent installed. Log: $agent_log"
  exit 0
  ;;
--uninstall-agent)
  launchctl bootout "gui/$(id -u)/$agent_label" 2>/dev/null || true
  rm -f "$agent_plist" "$agent_script"
  echo "Auto-update agent removed."
  exit 0
  ;;
--local)
  cd "$(dirname "$0")/.."
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
  open "$installed"
  exit 0
  ;;
esac

if ! tag=$(gh release view --repo "$repo" --json tagName --jq .tagName); then
  echo "$(date '+%F %T') Could not get the latest release."
  [ "$mode" = "--auto" ] && exit 0
  exit 1
fi

if [ "$(cat "$state_dir/installed" 2>/dev/null)" = "$tag" ]; then
  echo "$(date '+%F %T') Already on the latest build ($tag)."
  exit 0
fi

if [ "$mode" = "--auto" ] && is_running; then
  if [ "$(cat "$state_dir/notified" 2>/dev/null)" != "$tag" ]; then
    notify "Готова новая сборка $tag. Выйди из приложения (⌘Q), и она установится сама в течение часа."
    mkdir -p "$state_dir"
    echo "$tag" > "$state_dir/notified"
  fi
  echo "$(date '+%F %T') $tag is available, Desktop Plus is running, waiting."
  exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
echo "Downloading $tag..."
gh release download "$tag" --repo "$repo" --pattern '*.zip' --dir "$tmp"
ditto -x -k "$tmp"/*.zip "$tmp/app"
install_app "$tmp/app/Desktop Plus.app" "$tag"

if [ "$mode" = "--auto" ]; then
  notify "Установлена новая сборка $tag."
else
  open "$installed"
fi
