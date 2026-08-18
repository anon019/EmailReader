#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
cd "$project_dir"

swift build -c release
binary_dir="$(swift build -c release --show-bin-path)"
app_dir="$project_dir/dist/Email Reader.app"
icon_master="$project_dir/Assets/AppIcon-master.png"
iconset_dir="$project_dir/.build/AppIcon.iconset"
icon_work_dir="$project_dir/.build/AppIcon-work"

if [[ ! -f "$icon_master" ]]; then
  swift "$project_dir/scripts/generate_icon.swift" "$icon_master"
fi

rm -rf "$iconset_dir" "$icon_work_dir" "$app_dir"
mkdir -p "$icon_work_dir" "$app_dir/Contents/MacOS" "$app_dir/Contents/Helpers" "$app_dir/Contents/Resources"

for spec in "16:16x16" "32:16x16@2x" "32:32x32" "64:32x32@2x" "128:128x128" "256:128x128@2x" "256:256x256" "512:256x256@2x" "512:512x512" "1024:512x512@2x"; do
  pixels="${spec%%:*}"
  name="${spec#*:}"
  sips -z "$pixels" "$pixels" "$icon_master" --out "$icon_work_dir/icon_${name}.png" >/dev/null
done
mv "$icon_work_dir" "$iconset_dir"
iconutil -c icns "$iconset_dir" -o "$app_dir/Contents/Resources/AppIcon.icns"

cp "$project_dir/App/Info.plist" "$app_dir/Contents/Info.plist"
cp "$binary_dir/EmailReader" "$app_dir/Contents/MacOS/EmailReader"
cp "$binary_dir/EmailReaderWorker" "$app_dir/Contents/Helpers/EmailReaderWorker"

signing_identity="${EMAILREADER_SIGNING_IDENTITY:--}"
if [[ "$signing_identity" == "-" ]]; then
  # Personal source builds remain ad-hoc. The stable helper installed by
  # install_personal_app.sh is preserved so routine refreshes do not repeatedly
  # change the Keychain caller identity.
  local_requirement='=designated => identifier "com.sota.EmailReader.local"'
  codesign --force --deep --sign - \
    --identifier "com.sota.EmailReader.local" \
    --requirements "$local_requirement" \
    "$app_dir"
else
  # Publicly distributed binaries must use a real Developer ID identity. This
  # binds the designated requirement to Apple's certificate chain and enables
  # Hardened Runtime instead of the forgeable identifier-only personal build.
  codesign --force --sign "$signing_identity" --options runtime --timestamp \
    "$app_dir/Contents/Helpers/EmailReaderWorker"
  codesign --force --sign "$signing_identity" --options runtime --timestamp \
    "$app_dir/Contents/MacOS/EmailReader"
  codesign --force --sign "$signing_identity" --options runtime --timestamp \
    "$app_dir"
fi
codesign --verify --deep --strict "$app_dir"

echo "$app_dir"
