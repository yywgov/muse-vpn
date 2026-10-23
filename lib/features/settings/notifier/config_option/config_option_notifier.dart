import 'dart:convert';

import 'package:hiddify/features/connection/data/connection_data_providers.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/muse/data/core_extras_provider.dart';
import 'package:hiddify/features/muse/logic/net_tools.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/singbox/model/singbox_config_option.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'config_option_notifier.g.dart';

/// 穿云 1.5.0: how long settings must stay unchanged before a running connection takes them.
const museConfigApplyDelay = Duration(milliseconds: 400);

@Riverpod(keepAlive: true)
class ConfigOptionNotifier extends _$ConfigOptionNotifier with AppLogger {
  @override
  Future<bool> build() async {
    final serviceRunning = ref.watch(serviceRunningProvider);
    // what the running core was last given (updated by every connect / reload)
    SingboxConfigOption? applied() => ref.read(connectionRepositoryProvider).configOptionsSnapshot;
    // 1.5.0 #56: rules / settings changed while connected are applied once the changes stop (hot
    // reload, or a restart for 系统代理 ⇄ TUN). The old guard dropped a change made within 100 ms
    // of the previous one, so the last edit of a quick series could be lost until a reconnect.
    final debounce = MuseDebouncer(museConfigApplyDelay);
    ref.onDispose(debounce.cancel);

    Future<void> apply({bool force = false}) async {
      final next = ref.read(ConfigOptions.singboxConfigOptions);
      final current = applied();
      if (!ref.read(serviceRunningProvider) || (next == current && !force)) return;
      if (current?.enableTun != next.enableTun) {
        loggy.debug("tun option changed, reconnecting");
        await ref.read(connectionNotifierProvider.notifier).restartForModeChange();
      } else {
        final activeProfile = await ref.read(activeProfileProvider.future);
        await ref.read(connectionNotifierProvider.notifier).reconnect(activeProfile);
      }
      state = const AsyncData(false);
    }

    ref.listen(ConfigOptions.singboxConfigOptions, (previous, next) {
      if (!serviceRunning || previous == null) return;
      if (next != previous && next != applied()) {
        debounce(() => apply().catchError((Object e) => loggy.warning("applying settings failed", e)));
      }
    }, fireImmediately: true);
    // the options sent beside them (hosts, 指定节点, 测速) are applied the same way
    ref.listen(museCoreExtrasProvider, (previous, next) {
      if (!serviceRunning || previous == null || jsonEncode(previous) == jsonEncode(next)) return;
      debounce(() => apply(force: true).catchError((Object e) => loggy.warning("applying settings failed", e)));
    });
    return false;
  }
}
