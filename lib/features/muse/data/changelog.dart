// 穿云 1.2.8 - 内置更新说明: shown once on the first start of a new version (not on a fresh install).
// Part of 穿云 (GPLv3).

/// version → what changed, newest first. Keep each line short.
const museChangelog = <String, List<String>>{
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
List<String>? museChangelogToShow({required String version, required String shown, required bool introDone}) {
  if (!introDone || shown == version) return null;
  return museChangelog[version];
}
