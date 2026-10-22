// 穿云 1.4.1 - Android: noticing that the system killed 穿云 in the background, and the per-brand
// steps that stop it (pure logic, unit-tested).
// Part of 穿云 (GPLv3).

/// Whether the VPN service was killed instead of stopped: it recorded a start ([connectedSince]
/// > 0, cleared on every normal stop), it isn't running now, the phone didn't reboot since
/// ([bootTime] before the start), the app wasn't just updated, and this start wasn't reported
/// already ([lastReported]).
bool museWasKilledInBackground({
  required int connectedSince,
  required bool running,
  required int bootTime,
  required bool appUpdated,
  required int lastReported,
}) {
  if (connectedSince <= 0 || running || appUpdated) return false;
  if (connectedSince == lastReported) return false;
  if (bootTime > 0 && bootTime >= connectedSince) return false; // rebooted since: not a kill
  return true;
}

/// A brand's settings steps.
class MuseOemGuide {
  const MuseOemGuide(this.brand, this.steps);

  final String brand;
  final List<String> steps;
}

/// The steps for a phone by its manufacturer / brand (Build.MANUFACTURER / BRAND).
MuseOemGuide museOemGuide(String manufacturer, {String brand = ''}) {
  final m = '$manufacturer $brand'.toLowerCase();
  if (m.contains('xiaomi') || m.contains('redmi') || m.contains('poco')) {
    return const MuseOemGuide('小米 / Redmi', [
      '设置 › 应用设置 › 应用管理 › 穿云 › 省电策略：选「无限制」',
      '同一页面打开「自启动」',
      '最近任务里按住穿云卡片，点锁形图标锁定',
    ]);
  }
  if (m.contains('huawei') || m.contains('honor')) {
    return const MuseOemGuide('华为 / 荣耀', [
      '设置 › 电池 › 启动应用管理（应用启动管理）› 穿云：关闭「自动管理」',
      '在弹出的窗口里打开「允许自启动」「允许关联启动」「允许后台活动」',
      '最近任务里下拉穿云卡片锁定',
    ]);
  }
  if (m.contains('oppo') || m.contains('oneplus') || m.contains('realme')) {
    return const MuseOemGuide('OPPO / 一加 / realme', [
      '设置 › 电池 › 更多设置 › 优化电池使用 › 穿云：选「不优化」',
      '设置 › 应用 › 自启动管理：打开穿云',
      '应用信息 › 耗电管理：打开「允许后台运行」',
    ]);
  }
  if (m.contains('vivo') || m.contains('iqoo')) {
    return const MuseOemGuide('vivo / iQOO', [
      '设置 › 电池 › 后台耗电管理 › 穿云：选「允许后台高耗电」',
      'i 管家 › 应用管理 › 权限管理 › 自启动：打开穿云',
      '最近任务里下拉穿云卡片锁定',
    ]);
  }
  if (m.contains('samsung')) {
    return const MuseOemGuide('三星', [
      '设置 › 电池 › 后台使用限制 › 永不休眠的应用：添加穿云',
      '应用 › 穿云 › 电池：选「不受限制」',
    ]);
  }
  if (m.contains('meizu')) {
    return const MuseOemGuide('魅族', ['手机管家 › 权限管理 › 后台管理 › 穿云：允许后台运行', '设置 › 应用管理 › 穿云 › 权限：打开自启动']);
  }
  return const MuseOemGuide('Android', [
    '设置 › 应用 › 穿云 › 电池：选「不受限制」或「不优化」',
    '如有「自启动」「后台运行」选项，请一并打开',
    '也可以在 设置 › 网络 › VPN 中为穿云打开「始终开启的 VPN」',
  ]);
}
