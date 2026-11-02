#!/usr/bin/env bash
# 穿云 1.10.0: runs a build command; when it fails, the lines that say why (Gradle's 「What went
# wrong」, Kotlin / Dart errors, Flutter tool errors) become ::error:: annotations, which show on the
# public run page without signing in. The exit code is passed through unchanged.
set -o pipefail
log=$(mktemp)
"$@" 2>&1 | tee "$log"
status=${PIPESTATUS[0]}
if [ "$status" -ne 0 ]; then
  grep -E -A6 "What went wrong|^e: |error:|Error:|FAILURE:|Exception|BUILD FAILED|Could not " "$log" \
    | grep -vE '^\s*$|^--$' | cut -c1-300 | head -n 40 | while IFS= read -r line; do
      echo "::error title=build::${line}"
    done
fi
rm -f "$log"
exit "$status"
