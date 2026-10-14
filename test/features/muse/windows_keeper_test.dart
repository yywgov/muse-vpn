// 穿云 Windows 1.2.1: connection keeper decisions and the system-proxy match.
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/muse/data/windows_proxy_guard.dart';
import 'package:hiddify/features/muse/desktop/connection_keeper.dart';
import 'package:hiddify/singbox/model/core_status.dart';

void main() {
  group('museKeeperDecide', () {
    KeeperAction d({
      bool want = true,
      bool justStopped = false,
      bool busy = false,
      bool ui = true,
      CoreStatus? core = const CoreStatus.started(),
    }) =>
        museKeeperDecide(wantConnected: want, userJustStopped: justStopped, uiBusy: busy, uiConnected: ui, core: core);

    test('running core, app shows connected: nothing', () => expect(d(), KeeperAction.none));
    test('running core, app shows 未连接 (lost status event): fix the UI', () {
      expect(d(ui: false), KeeperAction.fixUi);
      expect(d(ui: false, want: false), KeeperAction.fixUi);
      expect(d(ui: false, core: const CoreStatus.hotReloading()), KeeperAction.fixUi);
    });
    test('core stopped by itself while the user wants it: recover', () {
      expect(d(core: const CoreStatus.stopped()), KeeperAction.recover);
      expect(d(core: const CoreStatus.stopped(), ui: false), KeeperAction.recover);
    });
    test('core not answering while the user wants it: recover', () => expect(d(core: null), KeeperAction.recover));
    test('user stopped it: never recover', () {
      expect(d(want: false, core: const CoreStatus.stopped(), ui: false), KeeperAction.none);
      expect(d(justStopped: true, core: const CoreStatus.stopped(), ui: false), KeeperAction.none);
    });
    test('app still shows connected for a core the user stopped: show the truth', () {
      expect(d(want: false, core: const CoreStatus.stopped()), KeeperAction.fixUi);
    });
    test('connecting / starting: wait', () {
      expect(d(busy: true, core: const CoreStatus.stopped(), ui: false), KeeperAction.none);
      expect(d(core: const CoreStatus.starting(), ui: false), KeeperAction.none);
    });
  });

  test('wake detection', () {
    const tick = Duration(seconds: 10);
    expect(museLooksLikeWake(const Duration(seconds: 11), tick), isFalse);
    expect(museLooksLikeWake(const Duration(seconds: 25), tick), isFalse);
    expect(museLooksLikeWake(const Duration(seconds: 45), tick), isTrue);
    expect(museLooksLikeWake(const Duration(hours: 8), tick), isTrue);
  });

  test('recovery backoff 2/5/15/30/60 s', () {
    expect(museRecoveryBackoff.map((d) => d.inSeconds).toList(), [2, 5, 15, 30, 60]);
  });

  test('system proxy points at us', () {
    expect(WindowsProxyGuard.pointsAtUs('http://127.0.0.1:12334', 12334), isTrue);
    expect(WindowsProxyGuard.pointsAtUs('127.0.0.1:12334', 12334), isTrue);
    expect(WindowsProxyGuard.pointsAtUs('http=localhost:12334;https=localhost:12334', 12334), isTrue);
    expect(WindowsProxyGuard.pointsAtUs('http://[::1]:12334', 12334), isTrue);
    expect(WindowsProxyGuard.pointsAtUs('http://127.0.0.1:123345', 12334), isFalse);
    expect(WindowsProxyGuard.pointsAtUs('proxy.corp.example:8080', 12334), isFalse);
    expect(WindowsProxyGuard.pointsAtUs('http://127.0.0.1:7890', 12334), isFalse);
  });
}
