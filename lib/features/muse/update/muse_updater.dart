// 穿云 1.1 - 关于 › 检查更新: reads the latest GitHub release, downloads its arm64 APK and opens
// the system installer (the release key is fixed, so it installs over the current version).
// Windows: downloads Chuanyun-Windows-x64-Setup.exe and runs it silently (/RELAUNCH reopens 穿云
// after the upgrade); a release with only the portable zip opens the release page instead.
// Part of 穿云 (GPLv3).

import 'dart:ffi' show Abi;
import 'dart:io';


import 'package:hiddify/features/muse/data/port_override.dart';
import 'package:crypto/crypto.dart';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/features/muse/data/chuanyun_platform.dart';
import 'package:hiddify/features/muse/logic/net_tools.dart';
import 'package:hiddify/features/window/notifier/window_notifier.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hiddify/utils/uri_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:version/version.dart';

const museLatestReleaseApi = 'https://api.github.com/repos/yywgov/muse-vpn/releases/latest';

/// The only place an update file may come from (a mirror only relays this URL).
const museReleaseDownloadPrefix = 'https://github.com/yywgov/muse-vpn/releases/download/';

/// Release asset the app updates from (signed with the fixed 穿云 key).
const museApkAssetName = 'Chuanyun-Android-arm64.apk';

/// 1.9.1: the release asset that matches the architecture this app runs as (an APK of another
/// ABI cannot be installed over it). arm64 is the default and stays the one name older releases
/// carry; 32-bit ARM and x86_64 have their own packages.
String museApkAssetFor(Abi abi) {
  if (abi == Abi.androidArm) return 'Chuanyun-Android-armeabi-v7a.apk';
  if (abi == Abi.androidX64) return 'Chuanyun-Android-x86_64.apk';
  return museApkAssetName;
}

/// 1.5.0 #207: whether [path] already holds the whole byte range [range] (inclusive).
bool museRangePartDone(String path, (int, int) range) {
  try {
    final f = File(path);
    return f.existsSync() && f.lengthSync() == range.$2 - range.$1 + 1;
  } catch (_) {
    return false;
  }
}

/// 1.17.0 B12: how many bytes of [range] a half-finished part at [path] already holds (0 = none,
/// or a file longer than the range, which can't be continued).
int museRangePartHave(String path, (int, int) range) {
  try {
    final f = File(path);
    if (!f.existsSync()) return 0;
    final len = f.lengthSync();
    return len <= range.$2 - range.$1 + 1 ? len : 0;
  } catch (_) {
    return 0;
  }
}

/// The Range header that continues [range] after [have] bytes.
String museResumeRange((int, int) range, int have) => 'bytes=${range.$1 + have}-${range.$2}';

/// 1.17.0 B12: files in the update folder that belong to another version (removed before a new
/// download; the current version's file and parts are kept for 断点续传).
List<String> museStaleUpdateFiles(List<String> names, String version) =>
    [for (final n in names) if (!n.startsWith('Chuanyun-$version-')) n];

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

/// 1.17.0 B12: the checksum file the release CI publishes next to every package
/// ("Chuanyun-Android-arm64.apk.sha256", `sha256sum` format).
String museSha256AssetNameFor(String assetUrl) => '${Uri.decodeComponent(assetUrl.split('/').last)}.sha256';

/// The download URL of the `.sha256` file for [assetUrl] in a release (JSON of the releases API),
/// or null. Only files in this repository's release downloads count.
String? museSha256AssetUrl(Map<String, dynamic> json, String assetUrl) {
  final wanted = museSha256AssetNameFor(assetUrl).toLowerCase();
  for (final asset in (json['assets'] as List? ?? const []).whereType<Map<String, dynamic>>()) {
    final name = (asset['name'] as String? ?? '').toLowerCase();
    final url = asset['browser_download_url'] as String?;
    if (name == wanted && url != null && url.startsWith(museReleaseDownloadPrefix)) return url;
  }
  return null;
}

/// The hex SHA-256 for [assetName] out of a `sha256sum` file ("<hex>  <name>", "<hex> *<name>" or
/// just "<hex>"), lower case, or null when the file does not name it.
String? museParseSha256File(String text, String assetName) {
  final want = assetName.toLowerCase();
  String? lone;
  for (final raw in text.split(RegExp(r'\r?\n'))) {
    final m = RegExp(r'^\s*([0-9a-fA-F]{64})(?:\s+\*?(.+?))?\s*$').firstMatch(raw);
    if (m == null) continue;
    final hex = m.group(1)!.toLowerCase();
    final name = m.group(2)?.trim().split(RegExp(r'[\\/]')).last.toLowerCase();
    if (name == null) {
      lone ??= hex;
    } else if (name == want) {
      return hex;
    }
  }
  return lone;
}

/// 1.17.0 B12: the SHA-256 a download is checked against: GitHub's digest and the release's
/// `.sha256` file must agree when both are known (else [MuseUpdateFailure.mismatchInfo]);
/// either one alone is used as is.
String? museExpectedSha256({String? digest, String? file}) {
  if (digest != null && file != null && digest != file) throw const MuseUpdateFailure(MuseUpdateFailureKind.mismatchInfo);
  return digest ?? file;
}

/// 1.17.0 B12: why an update could not be installed, with the words 关于 shows.
enum MuseUpdateFailureKind { network, incomplete, checksum, mismatchInfo, noSpace }

class MuseUpdateFailure implements Exception {
  const MuseUpdateFailure(this.kind, [this.detail = '']);

  final MuseUpdateFailureKind kind;
  final String detail;

  /// A failed checksum means the downloaded bytes are bad: they are deleted and the download
  /// starts over. Anything else keeps the finished parts, so 「重试」 continues where it stopped.
  bool get startsOver => kind == MuseUpdateFailureKind.checksum || kind == MuseUpdateFailureKind.mismatchInfo;

  @override
  String toString() => 'MuseUpdateFailure($kind${detail.isEmpty ? '' : ': $detail'})';
}

/// The message for a failed update (Chinese, one or two sentences).
String museUpdateFailureText(Object error) {
  final kind = switch (error) {
    MuseUpdateFailure(:final kind) => kind,
    FileSystemException(:final osError) when (osError?.errorCode == 28 || osError?.errorCode == 112) =>
      MuseUpdateFailureKind.noSpace,
    _ => MuseUpdateFailureKind.network,
  };
  return switch (kind) {
    MuseUpdateFailureKind.network => '下载中断了（网络不稳定或下载地址都连不上）。已下载的部分会保留，点「重试」从断开的地方继续。',
    MuseUpdateFailureKind.incomplete => '安装包没有下载完整。已下载的部分会保留，点「重试」继续下载剩下的部分。',
    MuseUpdateFailureKind.checksum => '安装包校验失败：文件的 SHA-256 与发布页附带的校验值不一致，可能下载时损坏了。已删除这个文件，点「重新下载」再下一次。',
    MuseUpdateFailureKind.mismatchInfo => '发布页给出的两份校验值不一致，为安全起见没有安装。请稍后点「重新下载」，或到发布页手动下载。',
    MuseUpdateFailureKind.noSpace => '存储空间不足，安装包放不下。清理一些空间后点「重试」。',
  };
}

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

/// 1.17.0 B12: checking the downloaded file's SHA-256.
class MuseUpdateVerifying extends MuseUpdateState {
  const MuseUpdateVerifying();
}

class MuseUpdateDownloading extends MuseUpdateState {
  const MuseUpdateDownloading(this.progress);

  /// 0..1, or null while the size is unknown.
  final double? progress;
}

/// 1.10.0: a release's notes (its body, written by the release CI from the in-app changelog) as
/// lines for the 「发现新版本」 dialog: list items without their marker, headings and blank lines
/// dropped, at most [max] lines.
List<String> museReleaseNotes(Object? body, {int max = 12}) {
  if (body is! String) return const [];
  final out = <String>[];
  for (final raw in body.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#') || line.startsWith('<!--')) continue;
    final item = line.replaceFirst(RegExp(r'^([-*·•]|\d+[.)])\s+'), '').trim();
    if (item.isEmpty) continue;
    out.add(item);
    if (out.length >= max) break;
  }
  return out;
}

/// Picks the arm64 APK (or with [windows] the Windows zip) out of a GitHub release
/// (JSON of the releases API), or null.
/// Prereleases and drafts are never used (1.5.1: stable releases only). Asset URLs outside this
/// repository's release downloads are ignored (release info that came through a mirror can't
/// point elsewhere).
MuseRelease? museParseRelease(Map<String, dynamic> json, {bool windows = false, String apkAsset = museApkAssetName}) {
  final tag = json['tag_name'] as String? ?? '';
  final version = tag.replaceFirst(RegExp('^v'), '').split('+').first;
  if (version.isEmpty || json['prerelease'] == true || json['draft'] == true) return null;
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
  // 1.9.1: the package for this app's architecture. Non-arm64 builds only take their own file (an
  // arm64 APK would be refused by the installer); arm64 keeps the earlier name-contains-arm64 rule.
  assets.sort((a, b) {
    bool exact(Map<String, dynamic> e) => (e['name'] as String? ?? '').toLowerCase() == apkAsset.toLowerCase();
    return (exact(a) ? 0 : 1).compareTo(exact(b) ? 0 : 1);
  });
  final wanted = apkAsset.toLowerCase();
  for (final asset in assets) {
    final name = (asset['name'] as String? ?? '').toLowerCase();
    final isArm64 = wanted == museApkAssetName.toLowerCase();
    if (name.endsWith('.apk') && (isArm64 ? name.contains('arm64') : name == wanted)) {
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
      final port = museEffectiveMixedPort(ref.read);
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
    // 1.17.0 B12: nothing worked. The parts stay (finished and half-finished ones) so 「重试」
    // continues from where it stopped; the SHA-256 check at the end catches a bad part.
    if (lastError is FileSystemException && lastError.message == 'incomplete download') {
      throw const MuseUpdateFailure(MuseUpdateFailureKind.incomplete);
    }
    if (lastError is FileSystemException && lastError.osError != null) throw lastError;
    throw MuseUpdateFailure(MuseUpdateFailureKind.network, '${lastError ?? 'download failed'}');
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
    final parts = <String>[for (var i = 0; i < ranges.length; i++) '$path.part$i'];
    // 1.5.0 #207: parts finished by an earlier source are kept (the whole file's SHA-256 is still
    // checked at the end), so a switch to the next mirror only fetches what is missing
    final done = [for (var i = 0; i < ranges.length; i++) museRangePartDone(parts[i], ranges[i])];
    // 1.17.0 B12 断点续传: a half-finished part continues from its own length
    final have = [for (var i = 0; i < ranges.length; i++) museRangePartHave(parts[i], ranges[i])];
    final got = [for (var i = 0; i < ranges.length; i++) done[i] ? ranges[i].$2 - ranges[i].$1 + 1 : have[i]];
    var ok = false;
    try {
      await Future.wait([
        for (var i = 0; i < ranges.length; i++)
          if (!done[i])
          dio
              .download(
                url,
                parts[i],
                cancelToken: _cancel,
                fileAccessMode: have[i] > 0 ? FileAccessMode.append : FileAccessMode.write,
                options: Options(headers: {'Range': museResumeRange(ranges[i], have[i])}),
                onReceiveProgress: (received, _) {
                  got[i] = have[i] + received;
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
      ok = true;
    } finally {
      // finished and half-finished parts stay for the next source / 「重试」 (see
      // museRangePartHave); a part longer than its range is unusable and dropped
      for (var i = 0; i < parts.length; i++) {
        if (ok || (!museRangePartDone(parts[i], ranges[i]) && museRangePartHave(parts[i], ranges[i]) == 0)) {
          try {
            File(parts[i]).deleteSync();
          } catch (_) {}
        }
      }
    }
  }

  /// Whether the last [check] got the release info through a mirror (see museCanInstallSilently).
  bool lastCheckViaMirror = false;

  /// 1.10.0: the notes of the release the last [check] found (empty when it had none).
  List<String> lastNotes = const [];

  /// The latest release when it is newer than this build, null when up to date. Throws on failure.
  /// The latest stable release (1.5.1: no Beta 通道) and, when GitHub can't be reached, the API mirrors.
  Future<MuseRelease?> check() async {
    if (state is! MuseUpdateIdle) return null;
    state = const MuseUpdateChecking();
    try {
      const api = museLatestReleaseApi;
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
      Map<String, dynamic>? json;
      lastNotes = const [];
      if (data is List) {
        // a mirror that answers with a release list: its newest stable entry
        json = musePickRelease([for (final e in data) if (e is Map<String, dynamic>) e]);
      } else if (data is Map<String, dynamic>) {
        json = data;
      }
      if (json != null) {
        release = museParseRelease(json, windows: windows, apkAsset: museApkAssetFor(Abi.current()));
        lastNotes = museReleaseNotes(json['body']);
      }
      final current = ref.read(appInfoProvider).requireValue.version;
      if (release == null || !museIsNewer(release.version, current)) return null;
      // 1.17.0 B12: the release's own .sha256 file, checked against GitHub's digest
      final shaUrl = museSha256AssetUrl(json!, release.apkUrl);
      if (shaUrl != null) {
        final text = await _fetchSmall(shaUrl, mirrors: !windows);
        final fromFile = text == null ? null : museParseSha256File(text, museSha256AssetNameFor(release.apkUrl));
        final expected = museExpectedSha256(digest: release.sha256, file: fromFile);
        release = (
          version: release.version,
          apkUrl: release.apkUrl,
          apkSize: release.apkSize,
          pageUrl: release.pageUrl,
          sha256: expected,
        );
      }
      return release;
    } finally {
      state = const MuseUpdateIdle();
    }
  }

  /// 1.17.0 B12: a small text file (the .sha256) from the running connection or GitHub (and, with
  /// [mirrors], the download mirrors); null when none answers.
  Future<String?> _fetchSmall(String url, {required bool mirrors}) async {
    for (final src in museDownloadSources(url, proxyPort: await _proxyPort(), mirrors: mirrors)) {
      final dio = _dio(proxyPort: src.proxyPort);
      try {
        final r = await dio
            .get<String>(src.url, options: Options(responseType: ResponseType.plain))
            .timeout(const Duration(seconds: 10));
        final text = r.data ?? '';
        if (r.statusCode == 200 && text.length < 4096 && RegExp('[0-9a-fA-F]{64}').hasMatch(text)) return text;
      } catch (_) {
      } finally {
        dio.close(force: true);
      }
    }
    return null;
  }

  /// 1.17.0 B12: the folder updates are downloaded to; files of other versions are removed, the
  /// current version's file and parts stay (断点续传 after 「重试」).
  Future<Directory> _updateDir(String version, {bool fresh = false}) async {
    final tmp = (await getTemporaryDirectory()).path;
    final dir = Directory(PlatformUtils.isWindows ? '$tmp\\chuanyun-update' : '$tmp/updates');
    if (dir.existsSync()) {
      final names = [for (final e in dir.listSync()) e.uri.pathSegments.lastWhere((x) => x.isNotEmpty)];
      for (final n in fresh ? names : museStaleUpdateFiles(names, version)) {
        try {
          final e = File('${dir.path}${Platform.pathSeparator}$n');
          if (e.existsSync()) e.deleteSync();
        } catch (_) {}
      }
    }
    dir.createSync(recursive: true);
    return dir;
  }

  /// 1.17.0 B12: 「重新下载」 — drops everything downloaded for [release] so far.
  Future<void> discardDownload(MuseRelease release) async => _updateDir(release.version, fresh: true);

  /// Checks the finished file; a mismatch deletes it (and its parts) and throws.
  Future<void> _verify(File file, String path, MuseRelease release) async {
    if (!file.existsSync() || (release.apkSize > 0 && file.lengthSync() != release.apkSize)) {
      throw const MuseUpdateFailure(MuseUpdateFailureKind.incomplete);
    }
    final expected = release.sha256;
    if (expected == null) return;
    state = const MuseUpdateVerifying();
    final actual = await museFileSha256(file);
    if (actual != expected) {
      try {
        file.deleteSync();
      } catch (_) {}
      for (var i = 0; i < 8; i++) {
        try {
          final f = File('$path.part$i');
          if (f.existsSync()) f.deleteSync();
        } catch (_) {}
      }
      throw MuseUpdateFailure(MuseUpdateFailureKind.checksum, 'expected $expected, got $actual');
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
      final dir = await _updateDir(release.version);
      final path = '${dir.path}/Chuanyun-${release.version}-arm64.apk';
      final existing = File(path);
      // already downloaded (e.g. the first try stopped at 「安装未知应用」): install it right away
      if (release.apkSize > 0 &&
          existing.existsSync() &&
          existing.lengthSync() == release.apkSize &&
          (release.sha256 == null || await museFileSha256(existing) == release.sha256)) {
        if (await ChuanyunPlatform.apkSignatureMatches(path) == false) throw MuseSignatureChanged(path);
        return await ChuanyunPlatform.installApk(path);
      }
      // a whole file of the wrong size / content from an earlier try is not reused
      if (existing.existsSync()) existing.deleteSync();
      await _download(release.apkUrl, path, release.apkSize, verified: release.sha256 != null);
      // 1.2.2: the installer also checks the signing key; the SHA-256 catches a corrupt download
      // (1.17.0 B12: checked against the release's .sha256 file too; a mismatch deletes the file)
      await _verify(File(path), path, release);
      if (await ChuanyunPlatform.apkSignatureMatches(path) == false) throw MuseSignatureChanged(path);
        return await ChuanyunPlatform.installApk(path);
    } catch (e, st) {
      loggy.warning('update download failed', e, st);
      rethrow;
    } finally {
      _cancel = null;
      state = const MuseUpdateIdle();
    }
  }

  /// 穿云 Windows: downloads the Setup.exe, starts it silently (UAC prompt; /RELAUNCH opens the
  /// new version when done) and quits so the files can be replaced and 系统代理 is restored.
  Future<bool> _downloadAndRunSetup(MuseRelease release) async {
    state = const MuseUpdateDownloading(null);
    _cancel = CancelToken();
    try {
      final dir = await _updateDir(release.version);
      final path = '${dir.path}\\Chuanyun-${release.version}-Setup.exe';
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
      await _download(release.apkUrl, path, release.apkSize, verified: release.sha256 != null);
      // never run without a matching SHA-256 (museCanInstallSilently already requires one)
      if (release.sha256 == null) throw const MuseUpdateFailure(MuseUpdateFailureKind.mismatchInfo);
      await _verify(file, path, release);
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
