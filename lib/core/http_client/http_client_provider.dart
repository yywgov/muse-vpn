import 'package:hiddify/features/muse/data/port_override.dart';
import 'package:flutter/foundation.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/http_client/dio_http_client.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'http_client_provider.g.dart';

@Riverpod(keepAlive: true)
DioHttpClient httpClient(Ref ref) {
  final client = DioHttpClient(
    timeout: const Duration(seconds: 15),
    userAgent: ref.watch(appInfoProvider).requireValue.userAgent,
    debug: kDebugMode,
  );

  ref.listen(ConfigOptions.mixedPort, (_, next) => client.setProxyPort(ref.read(museMixedPortOverrideProvider) ?? next), fireImmediately: true);
  // 穿云 1.12.0: this connection uses another port (the saved one was taken)
  ref.listen<int?>(museMixedPortOverrideProvider, (_, next) => client.setProxyPort(next ?? ref.read(ConfigOptions.mixedPort)));
  return client;
}
