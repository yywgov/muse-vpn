// 穿云 Windows 1.2.1: set by ChuanyunGuard.exe when it relaunches 穿云 after a crash exit.
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

import 'dart:io';

abstract final class MuseRecovery {
  static final bool relaunchedAfterCrash = Platform.environment['CHUANYUN_RECOVERED'] == '1';
}
