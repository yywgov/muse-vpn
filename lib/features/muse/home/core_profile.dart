// 穿云 1.5.3 - which subscription the running core was started / reloaded with. Switching the
// active subscription while connected reloads the core; until that finished, the old core's
// node groups are not shown on 节点 (nor saved as the new subscription's list).
// Part of 穿云 (GPLv3).

import 'package:hooks_riverpod/hooks_riverpod.dart';

/// null = unknown (not started by this app run, e.g. the Android VPN kept running).
final museCoreProfileIdProvider = StateProvider<String?>((ref) => null);
