#!/usr/bin/env bash
# 穿云 1.9.1: picks the release APK of one architecture out of build/app/outputs/flutter-apk, copies it
# to out/<name>, checks that both native cores are inside, records its size and writes a checksum.
# usage: tool/ci/collect_apk.sh <abi> <out-name>      e.g. armeabi-v7a Chuanyun-Android-armeabi-v7a.apk
set -euo pipefail
abi="$1"; name="$2"
mkdir -p out
apk=$(ls build/app/outputs/flutter-apk/*"$abi"*release*.apk build/app/outputs/flutter-apk/app-release.apk 2>/dev/null | head -n1 || true)
if [ -z "$apk" ]; then
  echo "::error::$abi APK not found"; ls -R build/app/outputs; exit 1
fi
cp "$apk" "out/$name"
# 1.7.0: 兼容内核 must be inside, next to the standard core (1.9.1: for this architecture)
unzip -l "out/$name" | tee "/tmp/apk-$abi.txt" | grep -E "lib/$abi/.*\.so$" || true
grep -q "lib/$abi/libmusecompat.so" "/tmp/apk-$abi.txt" || { echo "::error::libmusecompat.so ($abi) is not in $name"; exit 1; }
grep -q "lib/$abi/libhiddify-core.so" "/tmp/apk-$abi.txt" || { echo "::error::libhiddify-core.so ($abi) is not in $name"; exit 1; }
other=$(grep -E ' lib/[^/]+/libmusecompat\.so$' "/tmp/apk-$abi.txt" | grep -v "lib/$abi/" || true)
[ -z "$other" ] || { echo "::error::$name carries another architecture's 兼容内核: $other"; exit 1; }
# 1.5.0 #219: APK size recorded on every run; 1.4.1 was 45.4 MB. Warn past 60 MB, fail past 80 MB
size=$(stat -c %s "out/$name")
mb=$(awk "BEGIN{printf \"%.1f\", $size/1048576}")
echo "::notice title=APK size ($abi)::$mb MB"
echo "APK size ($abi): $mb MB" >> "$GITHUB_STEP_SUMMARY"
if [ "$size" -gt 83886080 ]; then echo "::error title=APK size::$name $mb MB is over the 80 MB limit"; exit 1; fi
if [ "$size" -gt 62914560 ]; then echo "::warning title=APK size::$name $mb MB is over 60 MB"; fi
# 1.5.0 #208: a checksum file next to the APK (verify with sha256sum -c)
(cd out && sha256sum "$name" > "$name.sha256")
ls -la out
