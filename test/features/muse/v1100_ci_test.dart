// 穿云 1.10.0 - CI: code generation runs in its own job with the codegen toolchain
// (tool/ci/codegen.sh); the build jobs only compile with the release toolchain and never run
// build_runner themselves (that is what hung the 1.9.2 runs for 6 hours).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _job(String yml, String name) {
  final start = yml.indexOf('\n  $name:\n');
  expect(start, greaterThanOrEqualTo(0), reason: 'job $name');
  final rest = yml.substring(start + 1);
  final next = RegExp(r'\n  [a-z][a-z0-9-]*:\n').firstMatch(rest.substring(1));
  return next == null ? rest : rest.substring(0, next.start + 1);
}

void main() {
  const workflows = {
    'muse-android.yml': 'apk',
    'muse-windows.yml': 'windows',
    'muse-android-e2e.yml': 'e2e',
  };

  for (final MapEntry(key: file, value: buildJob) in workflows.entries) {
    group(file, () {
      final yml = File('.github/workflows/$file').readAsStringSync();

      test('codegen job uses the codegen toolchain and hands over generated sources', () {
        final codegen = _job(yml, 'codegen');
        expect(codegen, contains(r'flutter-version: ${{ env.CODEGEN_FLUTTER_VERSION }}'));
        expect(codegen, contains('tool/ci/codegen.sh'));
        expect(codegen, contains('name: muse-codegen'));
        expect(codegen, contains('timeout-minutes:'));
      });

      test('build job needs codegen, builds with the release toolchain and never runs the generators', () {
        final build = _job(yml, buildJob);
        expect(build, matches(RegExp(r'needs: (\[[^\]]*codegen[^\]]*\]|codegen)')));
        expect(build, contains(r'flutter-version: ${{ env.FLUTTER_VERSION }}'));
        expect(build, isNot(contains('CODEGEN_FLUTTER_VERSION')));
        expect(build, contains('name: muse-codegen'));
        for (final banned in ['android-prepare', 'windows-prepare', 'build_runner', 'make gen', 'dart run slang']) {
          expect(build, isNot(contains(banned)), reason: banned);
        }
        // the prebuilt core step cannot hang a job for hours again
        expect(build, contains(RegExp(r'Prepare \(prebuilt core\)\n\s+timeout-minutes: \d+')));
      });
    });
  }

  test('codegen script works on a copy and leaves the release toolchain floor in pubspec alone', () {
    final sh = File('tool/ci/codegen.sh').readAsStringSync();
    expect(sh, contains('mktemp -d'));
    expect(sh, contains('cd "\$tmp"'));
    // the pubspec rewrite happens after switching to the copy
    expect(sh.indexOf('sed -i'), greaterThan(sh.indexOf('cd "\$tmp"')));
    expect(sh, contains('build_runner build --delete-conflicting-outputs'));
    expect(sh, contains('dart run slang'));
    for (final ext in ['*.g.dart', '*.freezed.dart', '*.gen.dart', '*.mapper.dart']) {
      expect(sh, contains(ext));
    }
  });

  test('兼容内核 module downloads are retried before the build', () {
    for (final file in ['muse-android.yml', 'muse-windows.yml']) {
      final yml = File('.github/workflows/$file').readAsStringSync();
      final retry = yml.indexOf('for i in 1 2 3; do go mod download && break;');
      expect(retry, greaterThan(0), reason: file);
      expect(retry, lessThan(yml.indexOf('go build -buildmode=c-shared')), reason: file);
    }
  });

  test('the codegen toolchain is only used for generation', () {
    for (final file in workflows.keys) {
      final yml = File('.github/workflows/$file').readAsStringSync();
      expect(RegExp(r'CODEGEN_FLUTTER_VERSION').allMatches(yml).length, 2, reason: file); // env + codegen job
    }
  });
}
