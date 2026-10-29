import 'package:hiddify/core/directories/directories_provider.dart';
import 'package:hiddify/features/connection/data/connection_repository.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/logic/compat_profile.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/settings/data/config_option_data_providers.dart';
import 'package:hiddify/hiddifycore/hiddify_core_service_provider.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'connection_data_providers.g.dart';

@Riverpod(keepAlive: true)
ConnectionRepository connectionRepository(Ref ref) {
  return ConnectionRepositoryImpl(
    ref: ref,
    directories: ref.watch(appDirectoriesProvider).requireValue,
    configOptionRepository: ref.watch(configOptionRepositoryProvider),
    singbox: ref.watch(hiddifyCoreServiceProvider),
    profilePathResolver: ref.watch(profilePathResolverProvider),
    // 穿云 1.7.0 M3-4: which core the next connection runs on
    coreKind: () => museEffectiveCoreKind(desktop: PlatformUtils.isDesktop, savedKey: ref.read(MusePrefs.coreKind)),
  );
}
