import 'dart:io';

import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/model/directories.dart';
import 'package:hiddify/features/muse/logic/compat_profile.dart';
import 'package:hiddify/features/muse/logic/connect_flow.dart';
import 'package:hiddify/features/muse/logic/core_kind.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';
import 'package:hiddify/core/utils/exception_handler.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/profile/data/profile_path_resolver.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/hiddifycore/hiddify_core_service.dart';
import 'package:hiddify/singbox/model/core_status.dart';
import 'package:hiddify/singbox/model/singbox_config_option.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:meta/meta.dart';

abstract interface class ConnectionRepository {
  SingboxConfigOption? get configOptionsSnapshot;

  TaskEither<ConnectionFailure, Unit> setup();
  Stream<ConnectionStatus> watchConnectionStatus();

  /// Whether the core is applying a new config without a restart; the connection stays up
  /// (watchConnectionStatus keeps reporting it as connected).
  Stream<bool> watchHotReloading();
  TaskEither<ConnectionFailure, Unit> connect(ProfileEntity activeProfile, bool disableMemoryLimit);
  TaskEither<ConnectionFailure, Unit> disconnect();
  TaskEither<ConnectionFailure, Unit> reconnect(ProfileEntity activeProfile, bool disableMemoryLimit);
}

class ConnectionRepositoryImpl with ExceptionHandler, InfraLogger implements ConnectionRepository {
  ConnectionRepositoryImpl({
    required this.ref,
    required this.directories,
    required this.singbox,
    required this.configOptionRepository,
    required this.profilePathResolver,
    MuseCoreKind Function()? coreKind,
    this.compatStore = const MuseCompatProfileStore(),
  }) : coreKind = coreKind ?? _standard;

  static MuseCoreKind _standard() => MuseCoreKind.standard;

  /// 穿云 1.7.0 M3-4: the core the next connection runs on (compat_profile.dart)
  final MuseCoreKind Function() coreKind;
  final MuseCompatProfileStore compatStore;

  final Ref ref;

  final Directories directories;
  final HiddifyCoreService singbox;

  final ConfigOptionRepository configOptionRepository;
  final ProfilePathResolver profilePathResolver;

  SingboxConfigOption? _configOptionsSnapshot;
  @override
  SingboxConfigOption? get configOptionsSnapshot => _configOptionsSnapshot;

  bool _initialized = false;

  @override
  TaskEither<ConnectionFailure, Unit> setup() {
    if (_initialized) return TaskEither.of(unit);
    return exceptionHandler(() {
      loggy.debug("setting up singbox");

      return singbox
          .setup()
          .map((r) {
            _initialized = true;
            return r;
          })
          .mapLeft(UnexpectedConnectionFailure.new)
          .run();
    }, UnexpectedConnectionFailure.new);
  }

  @override
  Stream<ConnectionStatus> watchConnectionStatus() {
    return singbox.watchStatus().map(
      (event) => switch (event) {
        CoreStopped() => Disconnected(event.getCoreAlert()),
        CoreStarting() => const Connecting(),
        CoreStarted() => const Connected(),
        CoreStopping() => const Disconnecting(),
        CoreHotReloading() => const Connected(),
      },
    );
  }

  @override
  Stream<bool> watchHotReloading() => singbox.watchStatus().map((event) => event is CoreHotReloading).distinct();

  @override
  TaskEither<ConnectionFailure, Unit> connect(ProfileEntity activeProfile, bool disableMemoryLimit) => setup().flatMap(
    // 穿云 1.5.0: check the config first; a sure failure names the setting instead of starting the core
    (_) => precheck(activeProfile).flatMap((_) => applyConfigOption(activeProfile)).flatMap((_) => prepareProfile(activeProfile)).flatMap(
      (_) => singbox.start(profilePathResolver.file(activeProfile.id).path, activeProfile.name, disableMemoryLimit),
      // .mapLeft(UnexpectedConnectionFailure.new),
    ),
  );

  @override
  TaskEither<ConnectionFailure, Unit> disconnect() => singbox.stop().mapLeft(UnexpectedConnectionFailure.new);

  @override
  TaskEither<ConnectionFailure, Unit> reconnect(ProfileEntity activeProfile, bool disableMemoryLimit) =>
      applyConfigOption(activeProfile).flatMap((_) => prepareProfile(activeProfile)).flatMap(
        // hot reload when possible, restart otherwise
        (_) => singbox
            .reload(profilePathResolver.file(activeProfile.id).path, activeProfile.name, disableMemoryLimit)
            .mapLeft(UnexpectedConnectionFailure.new),
      );

  /// 穿云 1.7.0 M3-4: the saved subscription in the form the core about to run reads: 标准内核
  /// converts a body 兼容内核 kept as it came (keeping the original), 兼容内核 gets the original
  /// back. A failed conversion leaves the profile unchanged and names the reason.
  @visibleForTesting
  TaskEither<ConnectionFailure, Unit> prepareProfile(ProfileEntity prof) => TaskEither(() async {
    final file = File(profilePathResolver.file(prof.id).path);
    try {
      final error = await compatStore.prepare(
        file,
        coreKind(),
        (bodyPath) async => (await singbox.validateConfigByPath(file.path, bodyPath, false).run()).fold((l) => l, (_) => null),
      );
      if (error == null) return right(unit);
      loggy.warning("converting the subscription for the standard core failed: $error");
      return left(ConnectionFailure.invalidConfig(error));
    } catch (e) {
      loggy.warning("preparing the profile for the core failed: $e");
      return left(ConnectionFailure.unexpected(e));
    }
  });

  /// 穿云 1.5.0: [museConfigPrecheck] on the options the core is about to get.
  @visibleForTesting
  TaskEither<ConnectionFailure, Unit> precheck(ProfileEntity prof) => TaskEither(() async {
    final either = configOptionRepository.fullOptionsOverrided(prof.profileOverride());
    final options = either.toNullable();
    if (options == null) return right(unit); // reported by applyConfigOption
    int? bytes;
    try {
      final f = File(profilePathResolver.file(prof.id).path);
      bytes = await f.exists() ? await f.length() : null;
    } catch (_) {
      bytes = -1; // could not look: not a reason to refuse
    }
    final issues = museConfigPrecheck(
      profileBytes: bytes == -1 ? 1 : bytes,
      mixedPort: options.mixedPort,
      clashApi: options.enableClashApi,
      clashApiPort: options.clashApiPort,
      tun: options.enableTun,
      mtu: options.mtu,
      remoteDns: options.remoteDnsAddress,
      testUrl: options.connectionTestUrl,
    );
    if (issues.isEmpty) return right(unit);
    loggy.warning("config pre-check failed: ${issues.join('; ')}");
    return left(ConnectionFailure.invalidConfigOption(issues.join('\n')));
  });

  @visibleForTesting
  TaskEither<ConnectionFailure, Unit> applyConfigOption(ProfileEntity prof) =>
      TaskEither.fromEither(configOptionRepository.fullOptionsOverrided(prof.profileOverride()))
          .mapLeft((l) => ConnectionFailure.invalidConfigOption(null, l))
          .flatMap(
            (overridedOptions) => TaskEither.tryCatch(() async {
              // 穿云 1.1.1: never chain through WARP / Psiphon, whatever a profile or an old
              // preference says (the chain path, its licence dialogs and consent prefs are gone).
              final options = overridedOptions.copyWith(chainStatus: ChainStatus.off);
              _configOptionsSnapshot = options;
              await singbox.changeOptions(options).run();
              return unit;
            }, (err, st) => err is ConnectionFailure ? err : ConnectionFailure.unexpected(err, st)),
          );
}
