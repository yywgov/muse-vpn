#!/usr/bin/env bash
# 穿云 e2e on the Android emulator (called by .github/workflows/muse-android-e2e.yml).
set -x
mkdir -p out/e2e
adb wait-for-device
adb shell settings put global window_animation_scale 0
adb shell settings put global transition_animation_scale 0
adb shell settings put global animator_duration_scale 0
adb shell settings put system screen_off_timeout 1800000
adb shell svc power stayon true
# no "app isn't responding" dialogs of other apps (the emulator's launcher) over the screenshots
adb shell settings put global hide_error_dialogs 1
adb shell settings put global anr_show_background 0
adb shell cmd uimode night yes; sleep 2; adb shell cmd uimode night no
sleep 15
adb shell wm density | tee out/e2e/density.txt
density=$(adb shell wm density | grep -oE '[0-9]+' | tail -n1)
adb shell getprop ro.build.version.release | tee out/e2e/android.txt
adb logcat -c
timeout 1500 flutter drive --no-pub \
  --use-application-binary build/app/outputs/flutter-apk/app-debug.apk \
  --driver test_driver/muse_e2e_test.dart \
  --target test_driver/muse_e2e.dart \
  -d emulator-5554 2>&1 | tee out/e2e/drive.log
rc=${PIPESTATUS[0]}
adb logcat -d > out/e2e/logcat.txt 2>&1
python3 tool/emulator/check_status_bar.py out/e2e "${density:-420}" | tee out/e2e/status_bar_check.txt
rc2=${PIPESTATUS[0]}
echo "drive=$rc status_bar=$rc2"
if [ "$rc" != 0 ] || [ "$rc2" != 0 ]; then exit 1; fi
