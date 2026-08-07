#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
cd "$project_dir"

swift build -c release
swift run EmailReaderSmokeTests
plutil -lint "$project_dir"/App/*.plist
"$project_dir/scripts/build_app.sh" >/dev/null
codesign --verify --deep --strict "$project_dir/dist/Email Reader.app"

db_path="$HOME/Library/Application Support/EmailReader/email_reader.sqlite3"
if [[ -f "$db_path" ]]; then
  sqlite3 "$db_path" "SELECT 'threads=' || COUNT(*) FROM threads; SELECT 'runs=' || COUNT(*) FROM sync_runs;"
fi

echo "Email Reader verification passed"
