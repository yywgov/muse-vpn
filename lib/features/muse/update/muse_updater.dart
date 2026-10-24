// 穿云 1.1 - 关于 › 检查更新: reads the latest GitHub release, downloads its arm64 APK and opens
// the system installer (the release key is fixed, so it installs over the current version).
// Windows: downloads Chuanyun-Windows-x64-Setup.exe and runs it silently (/RELAUNCH reopens 穿云
// after the upgrade); a release with only the portable zip opens the release page instead.
// Part of 穿云 (GPLv3).

import 'dart:io';

import 'package:hiddify/features/muse/data/sync_service.dart';

import 'package:crypto/crypto.dart';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/features/muse/data/chuanyun_platform.dart';
import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/logic/net_tools.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/window/notifier/window_notifier.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hiddify/utils/uri_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:version/version.dart';

const museLatestReleaseApi = 'https://api.github.com/repos/yywgov/muse-vpn/releases/latest';

/// 1.4.1 Beta 通道: the newest releases including prereleases.
const museReleasesApi = 'https://api.github.com/repos/yywgov/muse-vpn/releases?per_page=10';

/// The only place an update file may come from (a mirror only relays this URL).
const museReleaseDownloadPrefix = 'https://github.com/yywgov/muse-vpn/releases/download/';

/// Release asset the app updates from (signed with the fixed 穿云 key).
const museApkAssetName = 'Chuanyun-Android-arm64.apk';

/// 穿云 Windows: the installer the Windows workflow publishes (preferred) ...
const museWindowsSetupAssetName = 'Chuanyun-Windows-x64-Setup.exe';

/// ... and the portable zip (only the release page is opened for it).
const museWindowsAssetName = 'Chuanyun-Windows-x64.zip';

/// Whether a Windows release found by [museParseRelease] is the installer (vs. the portable zip).
bool museIsWindowsInstaller(MuseRelease release) => release.apkUrl.toLowerCase().endsWith('.exe');

/// A release found on GitHub: its version, the asset to download (arm64 APK, or the Windows zip)
/// and the release page (Windows opens it in the browser instead of installing in-app).
///
/// 1.2.2: [sha256] is the asset's digest as GitHub reports it (the "digest" field, "sha256:" plus hex), lower
/// case hex, or null when the release does not carry one. A Windows installer is only run when
/// the downloaded file matches it.
typedef MuseRelease = ({String version, String apkUrl, int apkSize, String pageUrl, String? sha256});

/// The hex SHA-256 out of a GitHub asset's "digest" field ("sha256:abc…"), or null.
String? museAssetSha256(Map<String, dynamic> asset) {
  final digest = (asset['digest'] as String? ?? '').trim().toLowerCase();
  final m = RegExp(r'^sha256:([0-9a-f]{64})$').firstMatch(digest);
  return m?.group(1);
}

/// SHA-256 (lower case hex) of a file, read in chunks.
Future<String> museFileSha256(File file) async => (await sha256.bind(file.openRead()).first).toString();

/// 1.2.4: the new APK is signed with another key than the installed app (builds before 1.2.4 had
/// a different throw-away key each), so Android would refuse it: uninstall once, then install.
class MuseSignatureChanged implements Exception {
  const MuseSignatureChanged(this.path);
  final String path;
}

sealed class MuseUpdateState {
  const MuseUpdateState();
}

class MuseUpdateIdle extends MuseUpdateState {
  const MuseUpdateIdle();
}

class MuseUpdateChecking extends MuseUpdateState {
  const MuseUpdateChecking();
}

class MuseUpdateDownloading extends MuseUpdateState {
  const MuseUpdateDownloading(this.progress);

  /// 0..1, or null while the size is unknown.
  final double? progress;
}

/// Picks the arm64 APK (or with [windows] the Windows zip) out of a GitHub release
/// (JSON of the releases API), or null.
/// 1.4.1: [allowPrerelease] for the Beta 通道. Asset URLs outside this repository's release
/// downloads are ignored (release info that came through a mirror can't point elsewhere).
MuseRelease? museParseRelease(Map<String, dynamic> json, {bool windows = false, bool allowPrerelease = false}) {
  final tag = json['tag_name'] as String? ?? '';
  final version = tag.replaceFirst(RegExp('^v'), '').split('+').first;
  if (version.isEmpty || (json['prerelease'] == true && !allowPrerelease) || json['draft'] == true) return null;
  final assets = (json['assets'] as List? ?? const []).whereType<Map<String, dynamic>>().toList();
  final pageUrl = json['html_url'] as String? ?? 'https://github.com/yywgov/muse-vpn/releases/latest';
  if (windows) {
    for (final wanted in [museWindowsSetupAssetName, museWindowsAssetName]) {
      for (final asset in assets) {
        final name = (asset['name'] as String? ?? '').toLowerCase();
        final url = asset['browser_download_url'] as String?;
        if (url != null && url.startsWith(museReleaseDownloadPrefix) && name == wanted.toLowerCase()) {
          return (
            version: version,
            apkUrl: url,
            apkSize: (asset['size'] as num?)?.toInt() ?? 0,
            pageUrl: pageUrl,
            sha256: museAssetSha256(asset),
          );
        }
      }
    }
    return null;
  }
  // the re-signed asset the release workflow uploads is Chuanyun-Android-arm64.apk; prefer it
  assets.sort((a, b) {
    bool exact(Map<String, dynamic> e) => (e['name'] as String? ?? '').toLowerCase() == museApkAssetName.toLowerCase();
    return (exact(a) ? 0 : 1).compareTo(exact(b) ? 0 : 1);
  });
  for (final asset in assets) {
    final name = (asset['name'] as String? ?? '').toLowerCase();
    if (name.endsWith('.apk') && name.contains('arm64')) {
      final url = asset['browser_download_url'] as String?;
      if (url == null || !url.startsWith(museReleaseDownloadPrefix)) continue;
      return (
        version: version,
        apkUrl: url,
        apkSize: (asset['size'] as num?)?.toInt() ?? 0,
        pageUrl: pageUrl,
        sha256: museAssetSha256(asset),
      );
    }
  }
  return null;
}

/// 1.2.4: GitHub download accelerators tried (after the user's own node) when github.com is slow
/// or blocked. The file is checked against the release's SHA-256 (and on Android the system
/// installer checks the signing key), so a mirror cannot slip in a different file.
/// 1.4.1: more mirrors (checked working 2026-10-22); the fastest is picked by a short probe.
const museDownloadMirrors = [
  'https://ghfast.top/',
  'https://gh-proxy.com/',
  'https://edgeone.gh-proxy.com/',
  'https://hk.gh-proxy.com/',
  'https://gh.llkk.cc/',
  'https://gh-proxy.org/',
];

/// Mirrors that also relay api.github.com (to find out about an update when GitHub is blocked).
const museApiMirrors = ['https://gh-proxy.com/', 'https://edgeone.gh-proxy.com/', 'https://hk.gh-proxy.com/', 'https://gh-proxy.org/'];

/// 1.4.1: [sources] ordered by a probe's speed ([speeds]: url → bytes/s, null = failed or not
/// probed): working sources fastest first, then the rest in their original order (still tried,
/// GitHub itself last of those).
List<({String url, int? proxyPort})> museRankSources(List<({String url, int? proxyPort})> sources, Map<String, double?> speeds) {
  final ok = [for (final s in sources) if ((speeds[s.url] ?? 0) > 0) s]
    ..sort((a, b) => speeds[b.url]!.compareTo(speeds[a.url]!));
  return [...ok, for (final s in sources) if (!ok.contains(s)) s];
}

/// Whether a Windows release is safe to install silently: its info came from GitHub itself, not
/// relayed by a mirror (a mirror could hand out its own digest), and it carries a digest.
bool museCanInstallSilently(MuseRelease r, {required bool viaMirror}) => !viaMirror && r.sha256 != null;

/// Where an update is downloaded from, in order: through the running 穿云 connection (local
/// mixed port), then the mirrors, then github.com directly.
List<({String url, int? proxyPort})> museDownloadSources(String url, {int? proxyPort, bool mirrors = true}) => [
  if (proxyPort != null) (url: url, proxyPort: proxyPort),
  if (mirrors && url.startsWith('https://github.com/'))
    for (final m in museDownloadMirrors) (url: '$m$url', proxyPort: null),
  (url: url, proxyPort: null),
];

/// Splits [size] bytes into [parts] inclusive byte ranges for a parallel download.
List<(int, int)> museByteRanges(int size, int parts) {
  if (size <= 0) return const [];
  final n = parts.clamp(1, size);
  final chunk = (size / n).ceil();
  return [
    for (var start = 0; start < size; start += chunk) (start, (start + chunk > size ? size : start + chunk) - 1),
  ];
}

/// Whether [remote] is newer than [current] ("1.1.0" vs "1.0.0"); unparsable versions are not.
bool museIsNewer(String remote, String current) {
  try {
    return Version.parse(remote) > Version.parse(current);
  } catch (_) {
    return false;
  }
}

final museUpdaterProvider = NotifierProvider<MuseUpdater, MuseUpdateState>(MuseUpdater.new);

class MuseUpdater extends Notifier<MuseUpdateState> with AppLogger {
  CancelToken? _cancel;

  @override
  MuseUpdateState build() => const MuseUpdateIdle();

  Dio _dio({int? proxyPort}) {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 20),
        headers: {'Accept': 'application/vnd.github+json', 'User-Agent': 'Chuanyun'},
      ),
    );
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.findProxy = (_) => proxyPort == null ? 'DIRECT' : 'PROXY 127.0.0.1:$proxyPort';
        return client;
      },
    );
    return dio;
  }

  /// The local mixed port when 穿云 is connected and listening, else null.
  Future<int?> _proxyPort() async {
    try {
      final port = ref.read(ConfigOptions.mixedPort);
      final s = await Socket.connect(InternetAddress.loopbackIPv4, port, timeout: const Duration(milliseconds: 500));
      s.destroy();
      return port;
    } catch (_) {
      return null;
    }
  }

  /// 1.2.4: downloads [url] to [path] from the fastest source that works (see
  /// [museDownloadSources]), in 4 parallel ranges when the size is known.
  Future<void> _download(String url, String path, int size, {required bool verified}) async {
    // mirrors only for a file whose SHA-256 is checked afterwards
    var sources = museDownloadSources(url, proxyPort: await _proxyPort(), mirrors: verified);
    // 1.4.1: a 64 KB probe of every source at once, fastest first
    if (sources.length > 2) sources = museRankSources(sources, await _probeSpeeds(sources));
    Object? lastError;
    for (final src in sources) {
      if (_cancel?.isCancelled ?? false) break;
      try {
        await _downloadFrom(src.url, path, size, src.proxyPort);
        final f = File(path);
        if (f.existsSync() && (size <= 0 || f.lengthSync() == size)) return;
        lastError = const FileSystemException('incomplete download');
      } catch (e) {
        lastError = e;
        loggy.warning('update download from ${src.url} failed: $e');
        if (e is DioException && e.type == DioExceptionType.cancel) rethrow;
      }
    }
    throw lastError ?? const FileSystemException('download failed');
  }

  /// Bytes/s of a 64 KB range from each source (null = failed), 5 s at most in total.
  Future<Map<String, double?>> _probeSpeeds(List<({String url, int? proxyPort})> sources) async {
    final out = <String, double?>{};
    await Future.wait([
      for (final src in sources)
        () async {
          final dio = _dio(proxyPort: src.proxyPort);
          final sw = Stopwatch()..start();
          try {
            final r = await dio
                .get<List<int>>(
                  src.url,
                  cancelToken: _cancel,
                  options: Options(responseType: ResponseType.bytes, headers: {'Range': 'bytes=0-65535'}),
                )
                .timeout(const Duration(seconds: 5));
            final n = r.data?.length ?? 0;
            final html = (r.headers.value('content-type') ?? '').contains('text/html');
            out[src.url] = (r.statusCode == 206 || r.statusCode == 200) && n > 1024 && !html ? n / (sw.elapsedMilliseconds + 1) * 1000 : null;
          } catch (_) {
            out[src.url] = null;
          } finally {
            dio.close(force: true);
          }
        }(),
    ]);
    return out;
  }

  Future<void> _downloadFrom(String url, String path, int size, int? proxyPort) async {
    final dio = _dio(proxyPort: proxyPort);
    try {
      await _downloadWith(dio, url, path, size);
    } finally {
      dio.close(force: true); // 1.4.1: one client per source, closed afterwards
    }
  }

  Future<void> _downloadWith(Dio dio, String url, String path, int size) async {
    void progress(int received) {
      if (size > 0) state = MuseUpdateDownloading((received / size).clamp(0, 1));
    }

    final ranges = museByteRanges(size, 4);
    if (ranges.length < 2) {
      await dio.download(
        url,
        path,
        cancelToken: _cancel,
        onReceiveProgress: (received, total) {
          final s = total > 0 ? total : size;
          state = MuseUpdateDownloading(s > 0 ? (received / s).clamp(0, 1) : null);
        },
      );
      return;
    }
    final got = List<int>.filled(ranges.length, 0);
    final parts = <String>[for (var i = 0; i < ranges.length; i++) '$path.part$i'];
    try {
      await Future.wait([
        for (var i = 0; i < ranges.length; i++)
          dio
              .download(
                url,
                parts[i],
                cancelToken: _cancel,
                options: Options(headers: {'Range': 'bytes=${ranges[i].$1}-${ranges[i].$2}'}),
                onReceiveProgress: (received, _) {
                  got[i] = received;
                  progress(got.fold(0, (a, b) => a + b));
                },
              )
              .then((r) {
                // a server that ignores Range sends the whole file with 200: not usable in parts
                if (r.statusCode != 206) throw const FileSystemException('range not supported');
                final len = File(parts[i]).lengthSync();
                if (len != ranges[i].$2 - ranges[i].$1 + 1) throw const FileSystemException('short range');
              }),
      ]);
      final out = File(path).openWrite();
      for (final p in parts) {
        await out.addStream(File(p).openRead());
      }
      await out.close();
    } finally {
      for (final p in parts) {
        try {
          File(p).deleteSync();
        } catch (_) {}
      }
    }
  }

  /// Whether the last [check] got the release info through a mirror (see museCanInstallSilently).
  bool lastCheckViaMirror = false;

  /// The latest release when it is newer than this build, null when up to date. Throws on failure.
  /// 1.4.1: Beta 通道 (prereleases too) and, when GitHub can't be reached, the API mirrors.
  Future<MuseRelease?> check() async {
    if (state is! MuseUpdateIdle) return null;
    state = const MuseUpdateChecking();
    try {
      final beta = ref.read(MusePrefs.betaChannel);
      final api = beta ? museReleasesApi : museLatestReleaseApi;
      final port = await _proxyPort();
      Object? data;
      lastCheckViaMirror = false;
      final tries = <({String url, int? port, bool mirror})>[
        if (port != null) (url: api, port: port, mirror: false),
        (url: api, port: null, mirror: false),
        for (final m in museApiMirrors) (url: '$m$api', port: null, mirror: true),
      ];
      Object? lastError;
      for (final t in tries) {
        final dio = _dio(proxyPort: t.port);
        try {
          final r = await dio.get<Object>(t.url);
          if (r.data is Map || r.data is List) {
            data = r.data;
            lastCheckViaMirror = t.mirror;
            break;
          }
        } catch (e) {
          lastError = e;
        } finally {
          dio.close(force: true);
        }
      }
      if (data == null) throw lastError ?? const FileSystemException('release check failed');
      final windows = PlatformUtils.isWindows;
      MuseRelease? release;
      if (data is List) {
        final picked = musePickRelease([for (final e in data) if (e is Map<String, dynamic>) e], beta: beta);
        release = picked == null ? null : museParseRelease(picked, windows: windows, allowPrerelease: beta);
      } else if (data is Map<String, dynamic>) {
        release = museParseRelease(data, windows: windows, allowPrerelease: beta);
      }
      final current = ref.read(appInfoProvider).requireValue.version;
      if (release == null || !museIsNewer(release.version, current)) return null;
      return release;
    } finally {
      state = const MuseUpdateIdle();
    }
  }

  /// Downloads the APK and hands it to the installer. Returns false when it couldn't be opened
  /// (e.g. 「安装未知应用」 still needs allowing: the system page is opened for that).
  Future<bool> downloadAndInstall(MuseRelease release) async {
    if (state is! MuseUpdateIdle) return false;
    // 穿云 Windows: only the portable zip in this release -> open the release page.
    // 1.2.2: so does an installer without a SHA-256 digest: an unverified file is never run
    // silently with administrator rights.
    // 1.4.1: also when the release info was relayed by a mirror
    if (PlatformUtils.isWindows &&
        (!museIsWindowsInstaller(release) || !museCanInstallSilently(release, viaMirror: lastCheckViaMirror))) {
      return UriUtils.tryLaunch(Uri.parse(release.pageUrl));
    }
    if (PlatformUtils.isWindows) return _downloadAndRunSetup(release);
    state = const MuseUpdateDownloading(null);
    _cancel = CancelToken();
    try {
      final dir = Directory('${(await getTemporaryDirectory()).path}/updates');
      final path = '${dir.path}/Chuanyun-${release.version}-arm64.apk';
      final existing = File(path);
      // already downloaded (e.g. the first try stopped at 「安装未知应用」): install it right away
      if (release.apkSize > 0 &&
          existing.existsSync() &&
          existing.lengthSync() == release.apkSize &&
          (release.sha256 == null || await museFileSha256(existing) == release.sha256)) {
        if (await ChuanyunPlatform.apkSignatureMatches(path) == false) throw MuseSignatureChanged(path);
        await _backupBeforeUpdate();
        return await ChuanyunPlatform.installApk(path);
      }
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      dir.createSync(recursive: true);
      await _download(release.apkUrl, path, release.apkSize, verified: release.sha256 != null);
      final file = File(path);
      if (!file.existsSync() || (release.apkSize > 0 && file.lengthSync() != release.apkSize)) {
        throw const FileSystemException('incomplete download');
      }
      // 1.2.2: the installer also checks the signing key; a digest catches a corrupt download
      if (release.sha256 != null && await museFileSha256(file) != release.sha256) {
        file.deleteSync();
        throw const FileSystemException('SHA-256 mismatch');
      }
      if (await ChuanyunPlatform.apkSignatureMatches(path) == false) throw MuseSignatureChanged(path);
      await _backupBeforeUpdate();
        return await ChuanyunPlatform.installApk(path);
    } catch (e, st) {
      loggy.warning('update download failed', e, st);
      rethrow;
    } finally {
      _cancel = null;
      state = const MuseUpdateIdle();
    }
  }

  /// 1.5.0 #206: settings and subscriptions saved before the new version installs.
  Future<void> _backupBeforeUpdate() async {
    try {
      await ref.read(museSyncServiceProvider).autoBackup('update').timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  /// 穿云 Windows: downloads the Setup.exe, starts it silently (UAC prompt; /RELAUNCH opens the
  /// new version when done) and quits so the files can be replaced and 系统代理 is restored.
  Future<bool> _downloadAndRunSetup(MuseRelease release) async {
    state = const MuseUpdateDownloading(null);
    _cancel = CancelToken();
    try {
      final dir = Directory('${(await getTemporaryDirectory()).path}\\chuanyun-update');
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      dir.createSync(recursive: true);
      final path = '${dir.path}\\Chuanyun-${release.version}-Setup.exe';
      await _download(release.apkUrl, path, release.apkSize, verified: release.sha256 != null);
      final file = File(path);
      if (!file.existsSync() || (release.apkSize > 0 && file.lengthSync() != release.apkSize)) {
        throw const FileSystemException('incomplete download');
      }
      final actual = await museFileSha256(file);
      if (actual != release.sha256) {
        file.deleteSync();
        throw FileSystemException('SHA-256 mismatch (expected ${release.sha256}, got $actual)');
      }
      await _backupBeforeUpdate();
      await Process.start(path, const [
        '/SILENT',
        '/SUPPRESSMSGBOXES',
        '/NORESTART',
        '/RELAUNCH',
      ], mode: ProcessStartMode.detached);
      await Future<void>.delayed(const Duration(seconds: 1));
      await ref.read(windowNotifierProvider.notifier).exit();
      return true;
    } catch (e, st) {
      loggy.warning('update download failed', e, st);
      rethrow;
    } finally {
      _cancel = null;
      state = const MuseUpdateIdle();
    }
  }

  void cancel() => _cancel?.cancel();
}
