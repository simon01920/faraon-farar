#!/usr/bin/env bash
# Android emulator smoke test, run by the `android-smoke` job of release.yml
# inside reactivecircus/android-emulator-runner (adb is on PATH, the emulator
# is booted). Informational only - that job never blocks a release.
#
#   1. install the x86_64 test APK and launch it (first launch -> tutorial)
#   2. after the boot the app must still be running
#   3. Back once: the tutorial closes to the main menu, the app must NOT quit
#   4. no "SCRIPT ERROR" from Godot in logcat
#
# Usage: android_emulator_smoke.sh <apk> <out-dir>
set -euo pipefail

apk="$1"
out="$2"
pkg="sk.pirios.faraon"
mkdir -p "$out"

alive() { adb shell pidof "$pkg" 2>/dev/null | tr -d '\r' || true; }
shot() { adb exec-out screencap -p > "$out/$1.png" 2>/dev/null || true; }
dump_log() { adb logcat -d > "$out/logcat.txt" 2>/dev/null || true; }
fail() {
  echo "::error::android smoke: $1"
  dump_log
  echo "--- godot / crash lines from logcat"
  grep -E " godot |AndroidRuntime|FATAL|SCRIPT ERROR" "$out/logcat.txt" | tail -n 200 || true
  exit 1
}

adb install -r "$apk"
adb logcat -c || true
adb shell monkey -p "$pkg" -c android.intent.category.LAUNCHER 1
# Software-rendered emulator: give the first scene (and the shader warm-up)
# plenty of time.
sleep 60
shot 1-first-launch
[ -n "$(alive)" ] || fail "the app is not running 60 s after launch"

adb shell input keyevent KEYCODE_BACK
sleep 10
shot 2-after-back
[ -n "$(alive)" ] || fail "the first Back press closed the app (expected: tutorial -> main menu)"

dump_log
echo "--- godot lines from logcat"
grep -E " godot " "$out/logcat.txt" | tail -n 120 || true
if grep -q "SCRIPT ERROR" "$out/logcat.txt"; then
  fail "SCRIPT ERROR in logcat"
fi

# Back on the main menu is meant to close the app; report, don't judge
# (how fast Android tears the process down varies).
adb shell input keyevent KEYCODE_BACK
sleep 8
shot 3-after-second-back
if [ -n "$(alive)" ]; then
  echo "note: process still alive after Back on the main menu"
else
  echo "Back on the main menu closed the app"
fi
dump_log
echo "android smoke OK"
