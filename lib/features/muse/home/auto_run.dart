// 穿云 1.6.0 C9 - 自动运行 (Android): opening 穿云 connects. Only once per launch of the app
// (cold start): turning the switch on later, coming back from the background, or disconnecting by
// hand never connects again by itself. Goes through the same connect as a chuanyun://connect link
// (museApplyLaunchControl → toggleConnection), so the connection state machine is untouched and
// the usual VPN permission dialog appears when needed.
// Part of 穿云 (GPLv3).

import 'dart:async';

import 'package:hiddify/features/muse/data/muse_prefs.dart';
import 'package:hiddify/features/muse/desktop/launch_control.dart';
import 'package:hiddify/features/muse/home/home_data.dart';
import 'package:hiddify/features/muse/logic/net_tools.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Whether this launch should connect by itself.
bool museShouldAutoRun({
  required bool isAndroid,
  required bool on,
  required bool alreadyRan,
  required bool hasActiveProfile,
  bool launchedForControl = false,
}) => isAndroid && on && !alreadyRan && hasActiveProfile && !launchedForControl;

bool _ranThisLaunch = false;

/// tests: start a new "launch"
void museAutoRunResetForTest() => _ranThisLaunch = false;

/// tests run it off Android
final museAutoRunForceProvider = Provider<bool>((_) => false);

/// the connect itself (same as a chuanyun://connect link); overridable in tests
final museAutoRunActionProvider = Provider<Future<void> Function()>(
  (ref) =>
      () => museApplyLaunchControl(ref, const MuseCliArgs(connect: true)),
);

/// the delay before connecting (the first frame comes first, start-up is not slowed)
const museAutoRunDelay = Duration(milliseconds: 800);

final museAutoRunProvider = Provider<void>((ref) {
  final android = PlatformUtils.isAndroid || ref.read(museAutoRunForceProvider);
  if (!android || _ranThisLaunch) return;
  // decided once, at the first build of the app: later changes of the switch wait for the next launch
  _ranThisLaunch = true;
  if (!ref.read(MusePrefs.autoRun)) return;
  // a chuanyun:// link that opened the app speaks for itself
  final control = museLaunchArgs.connect || museLaunchArgs.disconnect;
  final timer = Timer(museAutoRunDelay, () async {
    // the active subscription is read from the database at start-up
    for (var i = 0; i < 10 && ref.read(museActiveProfileIdProvider) == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    final go = museShouldAutoRun(
      isAndroid: true,
      on: ref.read(MusePrefs.autoRun),
      alreadyRan: false,
      hasActiveProfile: ref.read(museActiveProfileIdProvider) != null,
      launchedForControl: control,
    );
    if (!go) return;
    await ref.read(museAutoRunActionProvider)();
  });
  ref.onDispose(timer.cancel);
});
