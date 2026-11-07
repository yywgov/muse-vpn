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
# 1.12.0: any crash of 穿云 (main or core process) fails the run
rc3=0
if grep -A2 "FATAL EXCEPTION" out/e2e/logcat.txt | grep "Process: com.chuanyun.app" | tee out/e2e/fatal.txt | grep -q .; then
  grep -A30 "FATAL EXCEPTION" out/e2e/logcat.txt | head -80
  rc3=1
fi
# 1.13.0: every stop of the service must finish within 15 s (e2e #16: two in-app disconnects took
# 120 s each); also records whether the system ever froze 穿云's process (freezer.txt)
python3 tool/emulator/check_stops.py out/e2e | tee out/e2e/check_stops.txt
rc4=${PIPESTATUS[0]}
# the app's own logs (core box.log / stderr, disconnect log, crash log) for the artifact
mkdir -p out/e2e/applogs
for f in $(adb shell run-as com.chuanyun.app find . -name '*.log' -size -8192k 2>/dev/null | tr -d '\r'); do
  adb exec-out run-as com.chuanyun.app cat "$f" > "out/e2e/applogs/$(echo "$f" | sed 's#^\./##; s#/#_#g')" 2>/dev/null || true
done
for f in $(adb shell find /sdcard/Android/data/com.chuanyun.app -name '*.log' -size -8192k 2>/dev/null | tr -d '\r'); do
  adb pull "$f" "out/e2e/applogs/ext_$(basename "$f")" >/dev/null 2>&1 || true
done
ls -la out/e2e/applogs || true
echo "drive=$rc status_bar=$rc2 fatal=$rc3 stops=$rc4"
if [ "$rc" != 0 ] || [ "$rc2" != 0 ] || [ "$rc3" != 0 ] || [ "$rc4" != 0 ]; then exit 1; fi
