// 穿云 1.2.8 - 内置更新说明: shown once on the first start of a new version (not on a fresh install).
// Part of 穿云 (GPLv3).

/// version → what changed, newest first. Keep each line short.
const museChangelog = <String, List<String>>{
  '1.4.1': [
    '修复新服务器上的 REALITY 节点连不上（内核 muse.15 恢复抗量子密钥交换）',
    '局域网扫码同步：两台设备扫码即可同步，坚果云 WebDAV 移到「更多」',
    '分流预设增至 25 个：新增 Google、YouTube、Netflix、Spotify、TikTok、X、Meta、Discord、GitHub 开发者、海外支付、加密货币、Amazon、国内 App 直连、BT 直连、游戏下载直连，支持分组与搜索',
    '应用内更新：多镜像自动选最快，可选 Beta 通道',
    '连接诊断向导与一键修复；睡眠唤醒后自动重新检测',
    'Windows：修复退出后残留系统代理；安卓：后台被杀检测与保活指南',
    '节点多选、指定节点、远程规则集、订阅 UA、更新差异、流量提醒、定时连接、连接质量提醒、命令行与 chuanyun:// 链接、崩溃日志导出',
    '修复：流量重复统计、定时连接次日不触发、同步覆盖或已删订阅复活、弹窗泄漏、大字号首页卡片溢出、更新安全校验',
  ],
  '1.4.0': [
    '节点测速更快：有界并发、按节点数的超时，打开即显示上次延迟，测速中可停止',
    '节点：重命名、备注、隐藏，名称美化，正则筛选/排除，隐藏重复节点；按地区分组可折叠并显示最低延迟；详情显示地址、落地 IP、健康度',
    '分流预设：AI、流媒体、Telegram、游戏、苹果、微软、Steam、学术、国内银行、隐私拦截；规则测试；自定义 hosts；规则导入导出',
    '坚果云 WebDAV 同步（订阅、节点改名/备注/隐藏、收藏、分流、设置，加密上传）与本地备份/恢复',
    '流量统计（日/月）与月度报告；远程 DNS 预设（DoH / DoT / DoQ）',
    '外观：主题色（蓝/绿/紫）、字体大小、隐私模式（首页数字打码）；订阅二维码分享',
    'Windows：主页卡片按列数自适应，网速与本次流量合并为「流量」卡；移除 Ctrl+Alt+P 快捷键',
  ],
  '1.3.0': [
    '全新界面：首页改为仪表盘（连接卡片 + 网速、流量、剩余流量、到期、出口 IP、去广告），长按卡片可排序或隐藏',
    '浅色背景改为淡蓝渐变加云朵，深色模式改为夜空蓝',
    '节点列表移到单独的「节点」页；未连接时也能选节点，连上后自动使用',
    '「智能保持连接」一个开关管掉线重连、换最佳节点、内核重启',
    '出口检测、外网检测、一键诊断合并为「诊断」，点首页出口 IP 即可打开',
    '添加订阅统一为一个「添加」入口，剪贴板里的订阅链接会出现在第一行',
    '去广告可选 关 / 温和 / 强力；Windows 宽窗口下首页右侧直接显示节点',
  ],
  '1.2.9': [
    '修复 Cloudflare Workers/Pages 自建节点（edgetunnel 等）开启 ECH 后全部超时',
    '兼容更多节点写法：未知指纹 fp、空 SNI、路径里的 ?ed=、VLESS 加密字段等',
    '无法使用的节点显示「节点配置不兼容：原因」，长按可查看并复制完整错误',
  ],
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
///
/// 1.5.0: a small update (same major.minor, e.g. 1.5.0 → 1.5.1) no longer pops the dialog; it
/// only puts a dot on 设置 › 关于 › 更新内容 ([museChangelogUnread]).
List<String>? museChangelogToShow({required String version, required String shown, required bool introDone}) {
  if (!introDone || shown == version) return null;
  if (museIsSmallUpdate(version: version, from: shown)) return null;
  return museChangelog[version];
}

/// 1.5.0: [version] only bumps the patch number of [from] (1.5.0 → 1.5.2). Unknown / empty
/// [from] is not small.
bool museIsSmallUpdate({required String version, required String from}) {
  List<int>? parse(String v) {
    final parts = v.trim().split('+').first.split('.');
    if (parts.length < 2) return null;
    final out = [for (final p in parts) int.tryParse(p)];
    if (out.any((e) => e == null)) return null;
    return out.cast<int>();
  }

  final a = parse(version);
  final b = parse(from);
  if (a == null || b == null) return false;
  return a[0] == b[0] && a[1] == b[1] && version.trim() != from.trim();
}

/// 1.5.0: whether 「更新内容」 shows a dot: this version has notes the user hasn't opened.
bool museChangelogUnread({required String version, required String seen}) =>
    museChangelog.containsKey(version) && seen != version;
