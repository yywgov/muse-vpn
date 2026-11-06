// 穿云 1.11.1 - 修复 1.11.0 启动闪退.
//
// Root cause: VPNService / ProxyService build `BoxService(this, this)` (and the :compat services
// `CompatService(this, …)`) in a field initialiser, i.e. while the Service object itself is being
// constructed and has no base context yet. 1.11.0 added
//   init { status.observeForever { ChuanyunWidget.onStatus(service, it) } }
// observeForever calls back at once with the current status, and onStatus did
// `service.getSharedPreferences(...)` → ContextWrapper with a null base → NullPointerException
// during Service instantiation. MainActivity binds the service with BIND_AUTO_CREATE on every start,
// so the app died on every launch. These tests keep that class of bug out.
// Part of 穿云 (GPLv3).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/muse/data/changelog.dart';

const _kt = 'android/app/src/main/kotlin/com/hiddify/hiddify';

String _read(String p) => File(p).readAsStringSync();

/// Kotlin code without comments (no "//" inside strings in these files).
String _code(String p) => _read(p)
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .split('\n')
    .map((l) => l.contains('//') ? l.substring(0, l.indexOf('//')) : l)
    .join('\n');

/// The bodies of every top-level `init { … }` block in [code] (brace matched).
List<String> _initBlocks(String code) {
  final out = <String>[];
  for (final m in RegExp(r'\binit\s*\{').allMatches(code)) {
    var depth = 0;
    for (var i = m.end - 1; i < code.length; i++) {
      if (code[i] == '{') depth++;
      if (code[i] == '}') {
        depth--;
        if (depth == 0) {
          out.add(code.substring(m.end, i));
          break;
        }
      }
    }
  }
  return out;
}

/// The classes a Service builds in a field initialiser (`private val x = Foo(this…)`), i.e. before
/// that Service has a base context.
Set<String> _builtDuringServiceConstruction() {
  final names = <String>{};
  for (final f in Directory('$_kt/bg').listSync().whereType<File>().where((f) => f.path.endsWith('.kt'))) {
    final code = _code(f.path);
    if (!RegExp(r':\s*(VpnService|Service|TileService)\s*\(').hasMatch(code)) continue;
    for (final m in RegExp(r'^\s*(?:private\s+)?val\s+\w+\s*=\s*([A-Z]\w*)\(this\b', multiLine: true).allMatches(code)) {
      names.add(m.group(1)!);
    }
  }
  return names;
}

void main() {
  group('1.11.0 启动闪退 root cause', () {
    test('the services that build BoxService / CompatService during their own construction are found', () {
      final built = _builtDuringServiceConstruction();
      expect(built, containsAll(['BoxService', 'CompatService']));
    });

    test('nothing built during Service construction hands the Service (or any context) to code in init', () {
      for (final cls in _builtDuringServiceConstruction()) {
        final f = File('$_kt/bg/$cls.kt');
        if (!f.existsSync()) continue;
        for (final body in _initBlocks(_code(f.path))) {
          // the Service has no base context yet: no context calls, and it is never passed on
          expect(body, isNot(matches(RegExp(r'\bservice\b'))), reason: '$cls init uses `service`: $body');
          expect(body, isNot(matches(RegExp(r'\bcontext\b'))), reason: '$cls init uses `context`: $body');
          for (final call in ['getSharedPreferences', 'getSystemService', 'packageName', 'applicationContext', 'startService', 'sendBroadcast']) {
            expect(body, isNot(contains(call)), reason: '$cls init calls $call');
          }
        }
      }
    });

    test('BoxService / CompatService: the widget follows the status without the Service', () {
      for (final cls in ['BoxService', 'CompatService']) {
        final code = _code('$_kt/bg/$cls.kt');
        expect(code, contains('status.observeForever { ChuanyunWidget.onStatus(it) }'), reason: cls);
        expect(code, isNot(contains('ChuanyunWidget.onStatus(service')), reason: cls);
      }
    });

    test('ChuanyunWidget: status / node entry points take no Context, use the application context, never throw', () {
      final code = _code('$_kt/bg/ChuanyunWidget.kt');
      expect(code, contains('fun onStatus(status: Status)'));
      expect(code, contains('fun onNode(node: String, delay: Int)'));
      expect(code, isNot(matches(RegExp(r'fun onStatus\([^)]*Context'))));
      expect(code, isNot(matches(RegExp(r'fun onNode\([^)]*Context'))));
      expect(code, contains('Application.application.applicationContext'));
      // every entry point is wrapped in a Throwable catch (a widget problem must not kill the app)
      for (final fn in ['fun onStatus', 'fun onNode', 'override fun onUpdate', 'private fun redraw']) {
        final i = code.indexOf(fn);
        expect(i, greaterThanOrEqualTo(0), reason: fn);
        final next = code.indexOf(RegExp(r'\n\s*(?:private |override )?fun '), i + fn.length);
        final body = code.substring(i, next < 0 ? code.length : next);
        expect(body, contains('catch (_: Throwable)'), reason: fn);
      }
      expect(code, isNot(contains('catch (_: Exception)')));
    });

    test('the application context is set before any component is created', () {
      final app = _code('$_kt/Application.kt');
      final attach = app.indexOf('override fun attachBaseContext');
      expect(attach, greaterThanOrEqualTo(0));
      expect(app.indexOf('application = this', attach), greaterThan(attach));
    });

    test('ChuanyunHandler: widget_update passes only node and delay', () {
      final code = _code('$_kt/ChuanyunHandler.kt');
      expect(code, contains('"widget_update"'));
      expect(code, matches(RegExp(r'ChuanyunWidget\.onNode\(\s*call\.argument<String>\("node"\)')));
    });

    test('1.11.0 features stay (no rollback): widget registered, core muse.23', () {
      expect(_read('android/app/src/main/AndroidManifest.xml'), contains('android:name=".bg.ChuanyunWidget"'));
      expect(_read('dependencies.properties'), contains('muse.core.version=5.0.0-muse.23'));
    });
  });

  test('版本 1.11.1 与更新说明', () {
    // 1.12.0 came after
    expect(museChangelog.keys.toList().indexOf('1.11.1') + 1, museChangelog.keys.toList().indexOf('1.11.0'));
    expect(museChangelog['1.11.1']!.join('\n'), contains('修复 1.11.0 启动闪退'));
    final md = _read('CHANGELOG.md');
    expect(md.indexOf('### 1.11.1'), lessThan(md.indexOf('### 1.11.0')));
  });
}
