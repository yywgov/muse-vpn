// 穿云 - 设置 › 开发者选项. Split out of more_settings.dart in 1.9.0 (same library, behaviour unchanged).
// Part of 穿云 (GPLv3).

part of 'more_settings.dart';

// ======================================================================= 开发者选项

/// 1.5.0: tuning nobody needs day to day (测速 并发数 / 超时 moved here from 设置 › 节点).
/// 1.6.0 C10 (#127): hidden until 关于 › 版本 is tapped 7 times; adds 调试日志, 清除缓存,
/// 消息样式测试, 崩溃记录测试, 重置引导 and a switch to hide it again.
/// 1.9.0 #9: the 测试页 (主题预览 with its 单选 / 开关示例, 消息样式测试, 崩溃记录测试) only in debug
/// builds; a release build never shows them.
class MuseDeveloperPage extends HookConsumerWidget {
  const MuseDeveloperPage({super.key, this.debugTools = kDebugMode});

  /// tests pass false to see the release page
  final bool debugTools;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workers = ref.watch(MusePrefs.testWorkers);
    final timeout = ref.watch(MusePrefs.testTimeoutSec);
    final debugLog = ref.watch(ConfigOptions.logLevel) == log.LogLevel.debug;
    return MuseScaffold(
      title: '开发者选项',
      body: MuseGroupedBody(
        children: [
          MuseSection(
            header: '延迟测试',
            children: [
              MuseTile(
                key: const ValueKey('node_test_workers'),
                leading: const Icon(Icons.speed_outlined),
                title: '并发数',
                trailing: Text('$workers'),
                chevron: true,
                onTap: () async {
                  final picked = await musePick<int>(context, '测速并发数', [for (final n in const [4, 8, 16, 32, 64]) (n, '$n')], workers);
                  if (picked != null) await ref.read(MusePrefs.testWorkers.notifier).update(picked);
                },
              ),
              MuseTile(
                key: const ValueKey('node_test_timeout'),
                leading: const Icon(Icons.timer_outlined),
                title: '超时',
                trailing: Text('$timeout 秒'),
                chevron: true,
                onTap: () async {
                  final picked = await musePick<int>(context, '测速超时', [for (final n in const [3, 5, 8, 10, 15]) (n, '$n 秒')], timeout);
                  if (picked != null) await ref.read(MusePrefs.testTimeoutSec.notifier).update(picked);
                },
              ),
              MuseTile(
                key: const ValueKey('dev_reset_test'),
                leading: const Icon(Icons.restart_alt_outlined),
                title: '恢复默认',
                onTap: () async {
                  await ref.read(MusePrefs.testWorkers.notifier).update(museTestWorkersDefault);
                  await ref.read(MusePrefs.testTimeoutSec.notifier).update(museTestTimeoutDefault);
                  _toast(ref, '已恢复默认');
                },
              ),
              // 1.20.3：「清除测速记录」与节点设置里的重复，只留节点设置那条
            ],
          ),
          MuseSection(
            header: '调试',
            children: [
              MuseSwitchTile(
                key: const ValueKey('dev_debug_log'),
                leading: const Icon(Icons.bug_report_outlined),
                title: '调试日志',
                info: '内核输出最详细的日志，便于排查；下次连接起生效。日志会变多，排查完请关闭',
                value: debugLog,
                onChanged: (v) => ref.read(ConfigOptions.logLevel.notifier).update(v ? log.LogLevel.debug : log.LogLevel.warn),
              ),
              MuseTile(
                key: const ValueKey('dev_clear_cache'),
                leading: const Icon(Icons.delete_sweep_outlined),
                title: '清除缓存',
                subtitle: '下载的更新安装包、导出的诊断文件，不影响设置和订阅',
                onTap: () async {
                  final freed = await museClearTempFiles();
                  _toast(ref, freed == 0 ? '没有可清除的缓存' : '已清除 ${museBytes(freed)}');
                },
              ),
            ],
          ),
          if (debugTools)
            MuseSection(
              header: '测试页 · 仅调试版',
              children: [
                MuseTile(
                  key: const ValueKey('dev_theme_preview'),
                  leading: const Icon(Icons.preview_outlined),
                  title: '主题预览',
                  subtitle: '首页、节点、列表、单选示例、开关示例',
                  chevron: true,
                  onTap: () => musePushPage(context, const MuseThemePreviewPage()),
                ),
                MuseTile(
                  key: const ValueKey('dev_toast_test'),
                  leading: const Icon(Icons.chat_bubble_outline_outlined),
                  title: '消息样式测试',
                  subtitle: '依次显示 成功 / 提示 / 错误 三种消息',
                  onTap: () {
                    try {
                      final n = ref.read(inAppNotificationControllerProvider);
                      n.showSuccessToast('成功消息示例');
                      n.showInfoToast('提示消息示例');
                      n.showErrorToast('错误消息示例');
                    } catch (_) {}
                  },
                ),
                MuseTile(
                  key: const ValueKey('dev_crash_test'),
                  leading: const Icon(Icons.report_outlined),
                  title: '崩溃记录测试',
                  subtitle: '写入一条测试崩溃，用来检查「诊断 › 导出崩溃记录」',
                  onTap: () async {
                    final ok = await museConfirm(context, title: '崩溃记录测试', message: '写入一条测试用的崩溃记录（不会真的退出）？', okText: '写入');
                    if (!ok) return;
                    MuseCrashRecorder.record(StateError('穿云崩溃记录测试'), StackTrace.current);
                    _toast(ref, '已写入测试崩溃记录');
                  },
                ),
              ],
            ),
          MuseSection(
            children: [
              MuseTile(
                key: const ValueKey('dev_reset_guides'),
                leading: const Icon(Icons.tips_and_updates_outlined),
                title: '重置引导',
                subtitle: '后台运行引导、更新内容提示重新显示一次',
                onTap: () async {
                  await ref.read(Preferences.keepAliveGuideShown.notifier).update(false);
                  await ref.read(MusePrefs.onboardingDone.notifier).update(false);
                  await ref.read(MusePrefs.changelogSeen.notifier).update('');
                  _toast(ref, '已重置');
                },
              ),
              MuseTile(
                key: const ValueKey('dev_turn_off'),
                leading: const Icon(Icons.visibility_off_outlined),
                title: '隐藏开发者选项',
                subtitle: '在「关于」连点图标 7 次可再次打开',
                onTap: () async {
                  await ref.read(MusePrefs.devMode.notifier).update(false);
                  if (context.mounted) Navigator.of(context).maybePop();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 1.6.0 C10 清除缓存: only what 穿云 itself put in the temporary directory (on Windows that is the
/// shared %TEMP%, so nothing else is touched): downloaded updates and exported diagnostics
/// (chuanyun-*). The bytes freed. Never throws.
bool museIsOwnTempEntry(String name, {required bool android}) =>
    name.startsWith('chuanyun-') || (android && name == 'updates');

Future<int> museClearTempFiles({Directory? dir, bool? android}) async {
  var freed = 0;
  final onAndroid = android ?? PlatformUtils.isAndroid;
  try {
    final d = dir ?? await getTemporaryDirectory();
    if (!d.existsSync()) return 0;
    for (final e in d.listSync(followLinks: false)) {
      if (!museIsOwnTempEntry(e.uri.pathSegments.where((x) => x.isNotEmpty).last, android: onAndroid)) continue;
      try {
        if (e is File) {
          final n = e.lengthSync();
          e.deleteSync();
          freed += n;
        } else if (e is Directory) {
          var n = 0;
          for (final f in e.listSync(recursive: true, followLinks: false).whereType<File>()) {
            try {
              n += f.lengthSync();
            } catch (_) {}
          }
          e.deleteSync(recursive: true);
          freed += n;
        }
      } catch (_) {
        // in use (Windows) or not ours to delete: skipped
      }
    }
  } catch (_) {}
  return freed;
}
