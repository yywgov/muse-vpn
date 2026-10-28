import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:ffi/ffi.dart';
import 'package:grpc/grpc.dart';
import 'package:hiddify/core/model/directories.dart';
import 'package:hiddify/features/muse/logic/core_kind.dart';
import 'package:hiddify/gen/hiddify_core_generated_bindings.dart';
import 'package:hiddify/hiddifycore/core_interface/core_interface.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore_service.pbgrpc.dart';
import 'package:hiddify/hiddifycore/generated/v2/hello/hello.pb.dart';
import 'package:hiddify/hiddifycore/generated/v2/hello/hello_service.pbgrpc.dart';
import 'package:hiddify/utils/custom_loggers.dart';

import 'package:path/path.dart' as p;

final _logger = infraLogger('HiddifyCoreFFI');
typedef StopFunc = Pointer<Utf8> Function();
typedef StopFuncDart = Pointer<Utf8> Function();

class CoreInterfaceDesktop extends CoreInterface with InfraLogger {
  static final HiddifyCoreNativeLibrary _box = _gen();

  static HiddifyCoreNativeLibrary _gen() {
    String fullPath = "";
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      fullPath = "hiddify-core";
    }
    if (Platform.isWindows) {
      // 穿云 1.7.0: the core chosen in 设置 › 内核 (read once at start-up); 标准内核 when the other
      // library is missing, so a damaged install still connects
      // (looked up next to Chuanyun.exe: the working directory differs when started at log-in)
      final libDir = fullPath.isEmpty ? File(Platform.resolvedExecutable).parent.path : fullPath;
      final compat = museCompatLibraryPath(libDir, MuseCoreSelection.startup, exists: (f) => File(f).existsSync());
      if (compat != null) {
        _logger.info('core: 兼容内核 ($compat)');
        return HiddifyCoreNativeLibrary(DynamicLibrary.open(compat));
      }
      if (MuseCoreSelection.startup == MuseCoreKind.compat) {
        _logger.warning('core: $museCompatLibrary not found, using 标准内核');
        MuseCoreSelection.init(MuseCoreKind.standard.key);
      }
      fullPath = p.join(fullPath, "hiddify-core.dll");
    } else if (Platform.isMacOS) {
      fullPath = p.join(fullPath, "hiddify-core.dylib");
    } else {
      fullPath = p.join(fullPath, "hiddify-core.so");
    }

    _logger.debug('hiddify-core native libs path: "$fullPath"');
    final lib = DynamicLibrary.open(fullPath);
    // final stopFunc = lib.lookup<NativeFunction<StopFunc>>('stop').asFunction<StopFunc>();
    // final errPtr2 = stopFunc();
    // final err = errPtr2.cast<Utf8>().toDartString();

    return HiddifyCoreNativeLibrary(lib);
  }

  Future<bool> isMusl() async {
    try {
      final result = await Process.run('ldd', ['--version']);
      return result.stdout.toString().toLowerCase().contains('musl');
    } catch (_) {
      return false;
    }
  }

  final port = 17078;

  /// the one channel to the in-process core, kept for the life of the app
  ClientChannel? _channel;
  static String generateRandomPassword(int length) {
    const characters = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    // 穿云 1.2.2: cryptographic RNG (the secret guards the local gRPC control API)
    final random = Random.secure();
    return List.generate(length, (_) => characters[random.nextInt(characters.length)]).join();
  }

  static final String secret = generateRandomPassword(100);

  @override
  Future<String> setup(Directories directories, bool debug, int mode) async {
    // Generate a random password for the grpc service
    // final errPtr2 = _box.stop();
    // final err = errPtr2.cast<Utf8>().toDartString();
    // throw Exception('stop: $err');
    const channelOption = ChannelCredentials.insecure();
    // 穿云 1.2.1: the hello channel is shut down after use, and a client that already talks to
    // the running core is kept: setup() used to open a new ClientChannel on every call (every
    // window restore) and never closed the old ones.
    final helloChannel = ClientChannel(
      '127.0.0.1',
      port: port,
      options: const ChannelOptions(credentials: channelOption),
    );
    final helloClient = HelloClient(helloChannel, options: CallOptions(metadata: {"x-muse-token": secret}));

    try {
      try {
        await helloClient.sayHello(HelloRequest(name: "test"), options: CallOptions(timeout: const Duration(seconds: 3)));
        loggy.info("core is already started!");
      } catch (e) {
        //core is not started yet

        final errPtr = _box.setup(
          directories.baseDir.path.toNativeUtf8().cast(),
          directories.workingDir.path.toNativeUtf8().cast(),
          directories.tempDir.path.toNativeUtf8().cast(),
          SetupMode.GRPC_NORMAL_INSECURE.value,
          "127.0.0.1:$port".toNativeUtf8().cast(),
          secret.toNativeUtf8().cast(),
          0,
          debug ? 1 : 0,
        );
        final err = errPtr.cast<Utf8>().toDartString();

        if (err.isNotEmpty) {
          return err;
        }
        final res = await helloClient.sayHello(HelloRequest(name: "test"));
        loggy.info(res.toString());
      }
    } finally {
      unawaited(helloChannel.shutdown().catchError((_) {}));
    }
    if (_channel != null) return "";
    _channel = ClientChannel(
      // 127.0.0.1, not localhost: the server listens on IPv4 loopback only
      '127.0.0.1',
      port: port,
      options: const ChannelOptions(
        credentials: ChannelCredentials.insecure(),
        // credentials: ChannelCredentials.secure(
        //   password: secret,
        //   onBadCertificate: (certificate, host) => true,
        // ),
      ),
    );
    bgClient = fgClient = CoreClient(
      _channel!,
      options: CallOptions(metadata: {"x-muse-token": secret}),
    );

    return "";
  }

  @override
  Future<bool> restart(String path, String name) async {
    return false;
  }

  @override
  Future<bool> stop() async {
    return false;
  }
}
