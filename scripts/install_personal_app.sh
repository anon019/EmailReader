#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
source_app="$project_dir/dist/Email Reader.app"
target_root="$HOME/Applications"
target_app="$target_root/Email Reader.app"
helper_root="$HOME/Library/Application Support/EmailReader"
helper_target="$helper_root/EmailReaderWorker"

if [[ ! -d "$source_app" ]]; then
  "$project_dir/scripts/build_app.sh" >/dev/null
fi

mkdir -p "$target_root"
if [[ -d "$target_app" ]]; then
  /usr/bin/osascript -e 'tell application "Email Reader" to quit' 2>/dev/null || true
  backup_dir="$(mktemp -d "$HOME/.Trash/EmailReader-install.XXXXXX")"
  mv "$target_app" "$backup_dir/Email Reader.app"
fi
ditto "$source_app" "$target_app"
mkdir -p "$helper_root"
if [[ ! -x "$helper_target" ]]; then
  install -m 700 "$source_app/Contents/Helpers/EmailReaderWorker" "$helper_target"
fi
codesign --verify --deep --strict "$target_app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$target_app"

echo "$target_app"
