#!/usr/bin/env bash
# Example: Orchard repackaged as com.bytv.launcher
set -euo pipefail
TV="${1:?usage: $0 <tv-ip> [apk-path]}"
APK="${2:-orchard_bytv.apk}"
ADB="${ADB:-adb}"

"$ADB" connect "$TV:5555"
"$ADB" -s "$TV:5555" install -r "$APK"
"$ADB" -s "$TV:5555" shell \
  'cmd package set-home-activity --user 0 com.bytv.launcher/app.orchard.tv.MainActivity'
"$ADB" -s "$TV:5555" shell \
  'cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME'
"$ADB" -s "$TV:5555" shell 'pm disable-user --user 0 com.mitv.tvhome'
"$ADB" -s "$TV:5555" shell \
  'cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME'
echo "Done. Press HOME on the remote to verify."
