// 穿云 1.8.0 - 活动: 连接 / 日志 / DNS in one page. Only the visible tab is built, so only its
// stream runs; switching tabs ends the one that was left right away (no grace period).
// 1.10.0: 统计 and 诊断 are tabs here too (they were rows of the 设置 home page); 诊断 runs its
// checks once when the tab opens, 统计 reads the saved traffic log (no stream).
// Routes: /settings/activity?tab=connections|logs|dns|stats|diagnose; the old /settings/connections
// and /settings/logs open the matching tab.
// Part of 穿云 (GPLv3).

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/features/muse/activity/dns_view.dart';
import 'package:hiddify/features/muse/connections/connections_page.dart';
import 'package:hiddify/features/muse/local_api/local_api_providers.dart';
import 'package:hiddify/features/muse/logic/settings_index.dart' show museActivityTabKeyForSetting;
import 'package:hiddify/features/muse/logs/logs_page.dart';
import 'package:hiddify/features/muse/settings/diagnose_sheet.dart' show MuseDiagnosePage;
import 'package:hiddify/features/muse/settings/more_settings.dart' show MuseStatsPage;
import 'package:hiddify/features/muse/widget/muse_segmented.dart';
import 'package:hiddify/features/muse/widget/muse_tokens.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

enum MuseActivityTab {
  connections('connections', '连接'),
  logs('logs', '日志'),
  dns('dns', 'DNS'),
  stats('stats', '统计'),
  diagnose('diagnose', '诊断');

  const MuseActivityTab(this.key, this.title);

  /// the `tab` query parameter
  final String key;
  final String title;

  static MuseActivityTab fromKey(String? key) => switch (key) {
    'logs' => MuseActivityTab.logs,
    'dns' => MuseActivityTab.dns,
    'stats' => MuseActivityTab.stats,
    'diagnose' => MuseActivityTab.diagnose,
    _ => MuseActivityTab.connections,
  };
}

/// The tab a 设置 search result opens.
MuseActivityTab museActivityTabForSetting(String title) => MuseActivityTab.fromKey(museActivityTabKeyForSetting(title));

/// Route name / path of 活动 (under 设置).
const museActivityRoute = 'activity';
const museActivityPath = '/settings/activity';

/// The location that opens [tab].
String museActivityLocation(MuseActivityTab tab) => '$museActivityPath?tab=${tab.key}';

/// The stream behind [tab]; ended when the tab is left (null = the tab has none).
ProviderOrFamily? museActivityStream(MuseActivityTab tab) => switch (tab) {
  MuseActivityTab.connections => museConnectionsProvider,
  MuseActivityTab.logs => museLogsProvider,
  MuseActivityTab.dns => museDnsQueriesProvider,
  MuseActivityTab.stats || MuseActivityTab.diagnose => null,
};

class MuseActivityPage extends HookConsumerWidget {
  const MuseActivityPage({super.key, this.initial = MuseActivityTab.connections});

  final MuseActivityTab initial;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = useState(initial);
    useEffect(() {
      tab.value = initial;
      return null;
    }, [initial]);

    void select(MuseActivityTab next) {
      final left = tab.value;
      if (next == left) return;
      tab.value = next;
      // the old tab's widgets are gone after this frame; then its stream ends at once (connections
      // and logs otherwise linger for their short grace period)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final stream = museActivityStream(left);
        if (stream != null && context.mounted && tab.value != left) ref.invalidate(stream);
      });
    }

    final header = Padding(
      padding: EdgeInsets.fromLTRB(MuseSpace.page(context), 0, MuseSpace.page(context), MuseSpace.s8),
      child: MuseSegmented<MuseActivityTab>(
        key: const ValueKey('activity_tabs'),
        values: MuseActivityTab.values,
        selected: tab.value,
        label: (t) => t.title,
        onChanged: select,
      ),
    );
    return switch (tab.value) {
      MuseActivityTab.connections => MuseConnectionsPage(key: const ValueKey('activity_connections'), header: header),
      MuseActivityTab.logs => MuseLogsPage(key: const ValueKey('activity_logs'), header: header),
      MuseActivityTab.dns => MuseDnsPage(key: const ValueKey('activity_dns'), header: header),
      MuseActivityTab.stats => MuseStatsPage(key: const ValueKey('activity_stats'), header: header),
      MuseActivityTab.diagnose => MuseDiagnosePage(key: const ValueKey('activity_diagnose'), header: header),
    };
  }
}
