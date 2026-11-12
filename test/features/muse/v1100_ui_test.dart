// 穿云 1.10.0 界面精简七项: 关于只剩图标/名称/版本行, 节点页精简, 删帮助与隐私, 删后台保活
// (仅首次连接一次电池白名单提示, 测试在 v190_settings_test), 规则入口只留「订阅 › 规则」,
// 删「不可用」(超时节点排到末尾, 测试在 v122/v124/v160_nodes_b_ui), 设置首页 8 项.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/muse/logic/resources.dart';
import 'package:hiddify/features/muse/logic/settings_index.dart';
import 'package:hiddify/features/settings/overview/settings_page.dart';

String _src(String p) => File(p).readAsStringSync();

MuseSettingPage? _first(String q, {bool android = true, bool windows = false}) {
  final hits = museSearchSettings(q, android: android, windows: windows);
  return hits.isEmpty ? null : hits.first.page;
}

void main() {
  // 1.11.0: 备份与同步 removed (导出 / 导入配置 on 关于) — seven rows
  group('#7 设置首页 8 项', () {
    test('Android: 外观, 自动连接, 分应用代理, 网络, 活动, 内核与资源, 关于', () {
      // 1.20.2：「网络」下面加「分流规则」（订阅页并入节点页）
      // 1.20.3：+ 隐私（外观页的隐私三项搬来）
      // 1.20.3：一级结构改为 外观、启动与断线、分流规则、网络、隐私与通知、活动、诊断、内核与资源、备份与恢复、关于；分应用代理进了分流规则页
      // 1.22.0 F2：一级 6 组（分流规则、活动搬到底栏「流量」）
      expect(museSettingsHomeRows(android: true, developer: false), ['连接与网络', '订阅与节点', '外观', '自动化', '诊断', '关于']);
    });
    test('Windows has no 分应用代理; 开发者选项 only once turned on', () {
      expect(museSettingsHomeRows(android: false, developer: false), hasLength(6)); // 1.22.0：6 组
      expect(museSettingsHomeRows(android: false, developer: false), isNot(contains('分应用代理')));
      // 1.22.0：开发者选项在「关于」组里
      expect(museSettingsHomeRows(android: true, developer: true), isNot(contains('开发者选项')));
      expect(_src('lib/features/settings/overview/settings_page.dart'), contains("if (devMode)\n                MuseTile(\n                  key: const ValueKey('settings_developer')"));
    });
    test('the removed rows are not on the page any more', () {
      final page = _src('lib/features/settings/overview/settings_page.dart');
      for (final k in ['settings_help', 'settings_nodes', 'settings_routing', 'settings_stats', 'settings_keep_alive', 'settings_privacy', 'settings_advanced']) {
        expect(page, isNot(contains("ValueKey('$k')")), reason: k);
      }
      expect(page, isNot(contains("ValueKey('settings_sync')")));
      // 1.22.0：活动成了底栏「流量」
      expect(page, isNot(contains("ValueKey('settings_activity')")));
      for (final k in ['settings_auto_connect', 'settings_network', 'settings_resources', 'settings_about']) {
        expect(page, contains("ValueKey('$k')"), reason: k);
      }
    });
    test('search: old names find their new place', () {
      const moved = <String, MuseSettingPage>{
        '智能保持连接': MuseSettingPage.autoConnect,
        '去广告': MuseSettingPage.routing,
        // 1.20.3：订阅弹层 ⋯ › 订阅设置
        '订阅自动更新': MuseSettingPage.subSettings,
        '节点名美化': MuseSettingPage.nodes,
        '负载均衡策略': MuseSettingPage.advanced,
        // 1.11.0: TLS 分片 stays on 网络 (not folded into 高级)
        'TLS 分片': MuseSettingPage.network,
        '统计': MuseSettingPage.stats,
        '诊断': MuseSettingPage.diagnose,
        // 1.20.3：搬到 隐私与通知
        '通知栏断开按钮': MuseSettingPage.privacy,
        // 1.20.3: 导入后清空剪贴板 moved to 设置 › 隐私; 致谢 is gone (no keyword any more)
        '导入后清空剪贴板': MuseSettingPage.privacy,
        '开源许可': MuseSettingPage.openSource,
      };
      moved.forEach((q, page) => expect(_first(q), page, reason: q));
      expect(_first('运行模式', android: false, windows: true), MuseSettingPage.network);
      expect(_first('窗口置顶', android: false, windows: true), MuseSettingPage.windowAdvanced);
      expect(MuseSettingPage.stats.path, '流量 › 连接 › 统计');
      expect(MuseSettingPage.advanced.path, '设置 › 连接与网络 › 网络 › 高级');
      expect(MuseSettingPage.nodes.path, '设置 › 订阅与节点 › 节点设置');
    });
    test('统计 / 诊断 open as tabs of 活动', () {
      expect(museActivityTabKeyForSetting('统计'), 'stats');
      // 1.20.3：诊断不再是活动的 tab（设置一级），这里落回默认 tab
      expect(museActivityTabKeyForSetting('诊断'), 'connections');
      expect(museActivityTabKeyForSetting('连接'), 'connections');
    });
    test('no entry points at the removed 设置 home groups', () {
      for (final e in museSettingEntries) {
        expect(e.page.path, isNot(anyOf(contains('帮助与隐私'), contains('后台保活'), equals('设置'))), reason: e.title);
      }
      final titles = museSettingEntries.map((e) => '${e.title}|${e.androidOnly}|${e.windowsOnly}').toList();
      expect(titles.toSet().length, titles.length);
    });
  });

  test('storage keys of every moved setting are unchanged', () {
    final general = _src('lib/core/preferences/general_preferences.dart');
    final muse = _src('lib/features/muse/data/muse_prefs.dart');
    const keys = <(String, String, bool)>[
      ('museKeepAlive', 'muse_keep_alive', true),
      ('museAdBlockLevel', 'muse_ad_block_level', true),
      ('museAutoUpdateHours', 'muse_auto_update_hours', true),
      ('keepAliveGuideShown', 'keep_alive_guide_shown', true),
      ('hideNotification', 'hide_notification', true),
      ('notifyStopButton', 'muse_notify_stop_button', false),
      ('clearClipboardAfterImport', 'muse_clear_clipboard', false),
      ('privacyMask', 'muse_privacy_mask', false),
      ('nodeMeta', 'muse_node_meta', false),
    ];
    for (final (name, key, inGeneral) in keys) {
      final re = RegExp('static final $name = PreferencesNotifier\\.create<[^>]+>\\("$key"');
      expect(re.hasMatch(inGeneral ? general : muse), isTrue, reason: '$name → $key');
    }
  });

  group('#5 规则入口只留「订阅 › 规则」', () {
    test('分流 / 订阅覆写 search lands on the 规则 page under 订阅', () {
      expect(_first('分流'), MuseSettingPage.routing);
      // 1.20.2：订阅页并入节点页——分流规则在设置「网络」下面，订阅覆写跟着订阅的 ⋮
      // 1.22.0：分流规则在 流量 › 规则；订阅修改（原覆写）在 设置 › 订阅与节点（订阅弹层 ⋯ 里也有）
      expect(MuseSettingPage.routing.path, '流量 › 规则');
      expect(MuseSettingPage.overrides.path, '设置 › 订阅与节点 › 订阅修改');
    });
    test('覆写 JSON is in 规则 › ⋯, not in 设置', () {
      expect(_src('lib/features/muse/config/rules_page.dart'), contains("ValueKey('rules_more_override_json')"));
      for (final p in [
        'lib/features/settings/overview/settings_page.dart',
        'lib/features/muse/settings/network_page.dart',
        'lib/features/muse/settings/more_settings.dart',
      ]) {
        final s = _src(p);
        expect(s, isNot(contains('MuseRoutingPage(')), reason: p);
        expect(s, isNot(contains('override_json')), reason: p);
      }
    });
  });

  group('#1 关于', () {
    // 1.20.3: the version line drops 「 · 内核 muse.xx」 (断言随改)
    test('one version line: 1.10.0（193）', () {
      expect(museCoreShort('5.0.0-muse.20'), 'muse.20');
      expect(museCoreShort('muse.20'), 'muse.20');
      expect(museAboutVersionLine(version: '1.10.0', build: '193'), '1.10.0（193）');
      expect(museAboutVersionLine(version: '1.10.0', build: ''), '1.10.0');
    });
    test('no list cards: icon, name, 点击检测更新 + version line below, one 开源许可 link (1.20.3: was 开源许可与致谢)', () {
      final s = _src('lib/features/about/widget/about_page.dart');
      expect(s, contains("ValueKey('about_check_update')"));
      expect(s, contains("ValueKey('about_version_text')"));
      expect(s, contains("ValueKey('about_open_source')"));
      expect(s, contains('onTap: idle ? checkUpdate : null'));
      for (final gone in ['MuseSection(', 'MuseTile(', "'更新内容'", "'致谢'", "'内核版本'"]) {
        expect(s, isNot(contains(gone)), reason: gone);
      }
    });
  });

  group('#2 节点页精简', () {
    test('toolbar is 搜索 + 测速 + ⋯; no 当前节点 card, no separate filter / style / sort buttons', () {
      final s = _src('lib/features/muse/nodes/node_list.dart');
      for (final k in ['node_search_button', 'node_test_button', 'node_more_button']) {
        expect(s, contains("ValueKey('$k')"), reason: k);
      }
      for (final k in ['node_filter_button', 'node_style_button', 'node_sort_button', 'node_current_card', 'clear_unavailable']) {
        expect(s, isNot(contains("ValueKey('$k')")), reason: k);
      }
    });
  });

  test('#3 帮助与隐私 is gone (page, route and search entry)', () {
    expect(File('lib/features/muse/settings/help_page.dart').existsSync(), isFalse);
    expect(File('lib/features/muse/settings/privacy_page.dart').existsSync(), isFalse);
    expect(_src('lib/features/settings/overview/settings_page.dart'), isNot(contains('MuseHelpPage')));
    expect(museSettingEntries.where((e) => e.title == '帮助与隐私'), isEmpty);
  });

  test('#6 「不可用」 is gone', () {
    expect(File('lib/features/muse/logic/bad_nodes.dart').existsSync(), isFalse);
    expect(File('lib/features/muse/home/bad_nodes.dart').existsSync(), isFalse);
    expect(_src('lib/features/muse/nodes/node_list.dart'), isNot(contains('不可用 ·')));
  });

  test('Android 打包: 每个 APK 只带自己架构的原生库 (AGP 8.11 下 abiFilters 不再排除预置 jniLibs)', () {
    final g = _src('android/app/build.gradle');
    expect(g, contains('def museAbi = System.getenv("MUSE_ABI") ?: System.getenv("MUSE_E2E_ABI") ?: "arm64-v8a"'));
    expect(g, contains('if (abi != museAbi) excludes.add("lib/\$abi/**".toString())'));
    for (final abi in ['arm64-v8a', 'armeabi-v7a', 'x86_64']) {
      expect(g, contains('"$abi"'), reason: abi);
    }
    // 签名配置不变
    expect(g, contains('chuanyun-release.p12'));
  });
}
