#!/usr/bin/env bash
# 穿云 1.10.0: code generation (build_runner + slang) with the codegen toolchain.
#
# The app is built with Flutter 3.47.8 (Dart 3.13, GHSA-frr6-h895-5pxp fix), but the generator stack
# pinned in pubspec.lock (riverpod_generator 2.6 / freezed 2.5 / drift_dev 2.26 → analyzer 7.x) cannot
# read the Flutter 3.47 framework sources: analyzer 7.x has no summary support for dot shorthands
# ("Missing implementation of visitDotShorthandPropertyAccess") and build_runner then waits forever
# (the 6-hour "Prepare" hang of the 1.9.2 CI runs). Every analyzer that understands dot shorthands
# (8.x+) needs the next major version of all those generators.
#
# So the generators run with the previous toolchain (CODEGEN_FLUTTER, Flutter 3.38.5) in a temporary
# copy of the working tree, and only the generated .dart sources are copied back. Generated code is
# plain Dart source; it is compiled into the app by the release toolchain like any other file, and no
# part of the codegen toolchain ships in the app.
#
# usage: tool/ci/codegen.sh <codegen flutter bin dir> [output tar]
#   without an output tar the generated files are copied into the working tree.
set -euo pipefail

flutter_bin=${1:?usage: codegen.sh <flutter bin dir of the codegen toolchain> [out.tar]}
out_tar=${2:-}
src=$(pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# tracked + untracked (not ignored) files, as they are in the working tree
git ls-files -z -co --exclude-standard | (cd "$src" && xargs -0 cp --parents -t "$tmp" 2>/dev/null || true)
cd "$tmp"

codegen_ver=$("$flutter_bin/flutter" --version --machine 2>/dev/null | sed -n 's/.*"frameworkVersion": *"\([^"]*\)".*/\1/p')
echo "codegen toolchain: Flutter ${codegen_ver:-?}"
# only the codegen copy accepts the older Flutter; the app's pubspec keeps the release toolchain floor
sed -i -E 's/^(  flutter: )\^[0-9.]+/\1^'"${codegen_ver:-3.38.5}"'/' pubspec.yaml

export PATH="$flutter_bin:$PATH"
flutter pub get
dart run build_runner build --delete-conflicting-outputs
dart run slang

mapfile -t files < <(find lib test -type f \( -name '*.g.dart' -o -name '*.freezed.dart' -o -name '*.gen.dart' -o -name '*.mapper.dart' \) | sort)
[ "${#files[@]}" -gt 0 ] || { echo "::error::code generation produced no files"; exit 1; }
echo "generated ${#files[@]} files"
if [ -n "$out_tar" ]; then
  case "$out_tar" in /*) ;; *) out_tar="$src/$out_tar" ;; esac
  tar cf "$out_tar" "${files[@]}"
else
  cp --parents -t "$src" "${files[@]}"
fi
