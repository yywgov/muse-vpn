// 穿云 1.2.8 - 内置更新说明: shown once on the first start of a new version (not on a fresh install).
// Part of 穿云 (GPLv3).

/// version → what changed, newest first. Keep each line short.
const museChangelog = <String, List<String>>{
  '1.5.4': [
    '节点筛选：可按协议、按自己加的标签筛选；节点可手动指定地区；不常用地区默认折叠（会记住你的展开/折叠）',
    '节点页顶部固定显示当前节点，并有「最近」快捷切回；详情里能看最近 10 次延迟走势',
    '节点详情：二维码分享，复制为 链接 / Clash / JSON 配置；中转节点显示入口和出口',
    '收藏可拖动排序；「重复判断」可在设置 › 节点 里选择三种规则',
    '清除不可用节点前先预览，清除后可一键撤销（只隐藏，不删订阅里的节点）',
  ],
  '1.5.3': [
    '修复：切换订阅后「节点」页还显示上一个订阅的节点（断开和连接中都已修复，连接中切换会自动重载新订阅）',
    '节点页更清爽：顶部显示当前订阅名，协议改成名字后的小标签，未知地区用灰色图标，自动最快、首页与列表的节点名一致',
    '出口 IP 不再每次打开都重新检测：按节点 / 订阅 / 网络缓存，10 分钟内直接显示；刷新时保留旧结果，诊断里可手动刷新',
  ],
  '1.5.2': [
    '修复：新版服务器拒绝 REALITY 节点连接（内核 muse.17 上报新版客户端版本号）',
  ],
  '1.5.1': [
    '首页去广告「关 / 温和 / 强力」和统计「日 / 周 / 月」切换：三段等宽、文字上下左右居中，选中块更饱满，大字号不溢出',
    '移除「关于」里的 Beta 通道开关（不发布测试版，应用内更新只取正式版）',
  ],
  '1.5.0': [
    'REALITY 更稳：内核 muse.16 按浏览器指纹配对密钥交换，握手失败自动换方式重试一次',
    '连接按钮可在「连接中」取消；显示 准备配置 → 启动核心 → 测试连通；启动前先检查配置，常见错误改成大白话',
    '节点：千节点列表滚动不卡，测速显示「已测 x / y」，详情显示传输/TLS/ALPN/指纹，当前节点可下载测速',
    '订阅：更新方式 自动/走代理/直连，失败显示状态码和建议，单个订阅可筛选节点，链接默认打码，明文 http 订阅会提醒',
    '分流：粘贴 Clash/Surge 规则自动转换，局域网规则固定第一，连接中改规则/设置自动生效',
    '高级（默认关）：IPv6 优先、Fake-IP、屏蔽 QUIC',
    '设置搜索；统计新增按周；恢复备份或更新前自动备份（可还原）',
    'Windows：托盘连上但上不了网时变橙色，通知显示「穿云」；诊断里可一键反馈问题',
    '界面：统一线性图标、对比度提升、骨架屏、尊重「减少动画」，窄屏大字号首页自动单列',
  ],
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
