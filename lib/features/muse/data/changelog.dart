// 穿云 1.2.8 - 内置更新说明: shown once on the first start of a new version (not on a fresh install).
// Part of 穿云 (GPLv3).

/// version → what changed, newest first. Keep each line short.
const museChangelog = <String, List<String>>{
  '1.2.8': [
    'Windows 托盘图标连上即变蓝，右键菜单显示当前网速',
    '去广告分「温和 / 强力」两档，默认温和，避免误拦导致 App 打不开',
    '长按节点：收藏置顶、只测这个节点',
    '自动隐藏「剩余流量 / 到期 / 官网」等非节点条目（设置里可关）',
    '记住每个订阅上次选择的节点',
    '流量用到 80% 和到期前 3 天发通知（Windows 也有）',
    '订阅自动更新间隔可选，更新失败会提示',
    '连上后自动检测外网，不通时首页提示换节点',
    '新增一键诊断；导出日志自动脱敏',
  ],
};

/// The notes to show for [version], or null: nothing new, already shown, or a fresh install
/// ([introDone] false — a new user has nothing to compare with; it is marked shown silently).
List<String>? museChangelogToShow({required String version, required String shown, required bool introDone}) {
  if (!introDone || shown == version) return null;
  return museChangelog[version];
}
