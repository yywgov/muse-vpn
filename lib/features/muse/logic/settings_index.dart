// 穿云 1.5.0 #101 - 设置 search: every setting with the page it lives on (pure logic, unit-tested).
// Part of 穿云 (GPLv3).

/// The page a setting lives on.
enum MuseSettingPage {
  main('设置'),
  advanced('设置 › 高级'),
  appearance('设置 › 外观'),
  nodes('设置 › 节点'),
  routing('设置 › 分流'),
  network('设置 › 网络'),
  sync('设置 › 同步与备份'),
  stats('设置 › 统计'),
  developer('设置 › 开发者选项'),
  perApp('设置 › 分应用代理'),
  diagnose('设置 › 诊断'),
  about('设置 › 关于'),
  // 1.6.0 C10
  resources('设置 › 资源'),
  themePreview('设置 › 外观 › 主题预览');

  const MuseSettingPage(this.path);

  final String path;
}

class MuseSettingEntry {
  const MuseSettingEntry(this.title, this.page, {this.keywords = const [], this.androidOnly = false, this.windowsOnly = false});

  final String title;
  final MuseSettingPage page;
  final List<String> keywords;
  final bool androidOnly;
  final bool windowsOnly;
}

const museSettingEntries = <MuseSettingEntry>[
  MuseSettingEntry('外观', MuseSettingPage.appearance, keywords: ['主题', '深色', '浅色', '夜间']),
  MuseSettingEntry('深浅色', MuseSettingPage.appearance, keywords: ['深色模式', '浅色模式', '跟随系统', '主题']),
  MuseSettingEntry('纯黑', MuseSettingPage.appearance, keywords: ['黑色', 'OLED', '省电', '深色模式', 'AMOLED']),
  MuseSettingEntry('主题色', MuseSettingPage.appearance, keywords: ['颜色', '蓝', '绿', '紫', '青', '靛', '粉', '橙', '强调色']),
  MuseSettingEntry('配色风格', MuseSettingPage.appearance, keywords: ['标准', '鲜艳', '表现力', '柔和', '鲜明', '着色', '单色', '配色', '风格', '色调', 'Material You']),
  MuseSettingEntry('自定义主题色', MuseSettingPage.appearance, keywords: ['十六进制', 'hex', '#', '自定义颜色', '取色']),
  MuseSettingEntry('文字缩放', MuseSettingPage.appearance, keywords: ['字体大小', '字号', '文字', '放大', '缩小']),
  MuseSettingEntry('隐私模式', MuseSettingPage.appearance, keywords: ['模糊', '截图']),
  MuseSettingEntry('智能保持连接', MuseSettingPage.main, keywords: ['断线', '重连', '自动切换', '故障转移']),
  MuseSettingEntry('去广告', MuseSettingPage.main, keywords: ['广告', '拦截', '温和', '强力']),
  MuseSettingEntry('订阅自动更新', MuseSettingPage.main, keywords: ['更新间隔', '订阅']),
  MuseSettingEntry('分应用代理', MuseSettingPage.perApp, keywords: ['应用', 'App', '绕过'], androidOnly: true),
  MuseSettingEntry('节点名美化', MuseSettingPage.nodes, keywords: ['国旗', '名称']),
  MuseSettingEntry('隐藏重复节点', MuseSettingPage.nodes, keywords: ['重复']),
  MuseSettingEntry('重复判断', MuseSettingPage.nodes, keywords: ['去重', '地址', '端口', '完整参数']),
  MuseSettingEntry('只显示 / 排除', MuseSettingPage.nodes, keywords: ['过滤', '筛选', '正则']),
  MuseSettingEntry('订阅 UA', MuseSettingPage.nodes, keywords: ['User-Agent', '格式', '客户端']),
  MuseSettingEntry('订阅更新方式', MuseSettingPage.nodes, keywords: ['走代理', '直连', '订阅下载']),
  MuseSettingEntry('清除测速记录', MuseSettingPage.nodes, keywords: ['延迟', '缓存']),
  MuseSettingEntry('分流预设', MuseSettingPage.routing, keywords: ['规则', 'ChatGPT', 'Netflix', 'Telegram', '国内直连']),
  MuseSettingEntry('指定节点', MuseSettingPage.routing, keywords: ['网站走某个节点', '应用走某个节点']),
  MuseSettingEntry('远程规则集', MuseSettingPage.routing, keywords: ['规则订阅', 'rule-set']),
  MuseSettingEntry('规则测试', MuseSettingPage.routing, keywords: ['匹配', '走哪条']),
  MuseSettingEntry('自定义 hosts', MuseSettingPage.routing, keywords: ['hosts', '域名解析']),
  MuseSettingEntry('导入 / 导出 / 粘贴规则', MuseSettingPage.routing, keywords: ['Clash', 'Surge', '规则']),
  MuseSettingEntry('远程 DNS', MuseSettingPage.network, keywords: ['DNS', '解析']),
  MuseSettingEntry('每天定时连接 / 断开', MuseSettingPage.network, keywords: ['定时', '计划']),
  MuseSettingEntry('连接质量提醒', MuseSettingPage.network, keywords: ['延迟', '提醒', '通知']),
  MuseSettingEntry('局域网同步', MuseSettingPage.sync, keywords: ['配对码', '扫码', '多设备']),
  MuseSettingEntry('WebDAV 同步', MuseSettingPage.sync, keywords: ['坚果云', '云同步']),
  MuseSettingEntry('导出 / 恢复备份', MuseSettingPage.sync, keywords: ['备份', '恢复', '自动备份']),
  MuseSettingEntry('流量统计', MuseSettingPage.stats, keywords: ['图表', '月报', '用量']),
  MuseSettingEntry('负载均衡策略', MuseSettingPage.advanced, keywords: ['负载均衡']),
  MuseSettingEntry('TLS 分片', MuseSettingPage.advanced, keywords: ['分片', '混淆']),
  MuseSettingEntry('IPv6', MuseSettingPage.advanced, keywords: ['v6']),
  MuseSettingEntry('Fake-IP', MuseSettingPage.advanced, keywords: ['虚拟地址', 'TUN']),
  MuseSettingEntry('屏蔽 QUIC', MuseSettingPage.advanced, keywords: ['UDP', 'YouTube', 'HTTP/3']),
  MuseSettingEntry('连接', MuseSettingPage.advanced, keywords: ['连接列表', '实时连接', '连接信息', '请求', '屏蔽']),
  MuseSettingEntry('日志', MuseSettingPage.advanced, keywords: ['日志记录', '实时日志', '导出日志']),
  MuseSettingEntry('切换节点时关闭旧连接', MuseSettingPage.advanced, keywords: ['关闭连接', '断开旧连接']),
  MuseSettingEntry('测速并发数 / 超时', MuseSettingPage.developer, keywords: ['测速', '并发', '超时']),
  MuseSettingEntry('诊断', MuseSettingPage.diagnose, keywords: ['日志', '连不上', '排查', '反馈', '崩溃']),
  MuseSettingEntry('运行模式', MuseSettingPage.main, keywords: ['TUN', '系统代理', '虚拟网卡'], windowsOnly: true),
  MuseSettingEntry('开机自启', MuseSettingPage.main, keywords: ['启动', '开机'], windowsOnly: true),
  MuseSettingEntry('静默启动', MuseSettingPage.main, keywords: ['托盘', '后台启动', '不弹窗口', '隐藏窗口'], windowsOnly: true),
  MuseSettingEntry('关闭窗口时', MuseSettingPage.main, keywords: ['托盘', '最小化', '退出'], windowsOnly: true),
  // 1.6.0 C8
  MuseSettingEntry('开机自启时静默', MuseSettingPage.main, keywords: ['开机', '托盘', '不弹窗口'], windowsOnly: true),
  MuseSettingEntry('穿云标题栏', MuseSettingPage.main, keywords: ['标题栏', '系统标题栏', '窗口边框'], windowsOnly: true),
  MuseSettingEntry('窗口置顶', MuseSettingPage.main, keywords: ['置顶', '最前面', '总在最前'], windowsOnly: true),
  MuseSettingEntry('按需运行', MuseSettingPage.main, keywords: ['Wi-Fi', 'WiFi', '无线', '暂停', '家里', '公司']),
  MuseSettingEntry('快捷键', MuseSettingPage.main, keywords: ['全局快捷键', '热键', '键盘'], windowsOnly: true),
  // 1.6.0 C9 (Android 通用)
  MuseSettingEntry('自动运行', MuseSettingPage.main, keywords: ['打开即连接', '自动连接', '启动时连接'], androidOnly: true),
  MuseSettingEntry('通知栏断开按钮', MuseSettingPage.main, keywords: ['通知', '断开', '停止按钮'], androidOnly: true),
  MuseSettingEntry('允许后台运行', MuseSettingPage.main, keywords: ['保活', '电池', '后台'], androidOnly: true),
  MuseSettingEntry('自启动', MuseSettingPage.main, keywords: ['开机', '保活'], androidOnly: true),
  MuseSettingEntry('隐藏桌面图标 / 最近任务 / 通知', MuseSettingPage.main, keywords: ['隐私', '隐藏'], androidOnly: true),
  MuseSettingEntry('检查更新', MuseSettingPage.about, keywords: ['版本', '更新内容']),
  // 1.6.0 C10
  // 1.7.0 M3
  MuseSettingEntry('内核', MuseSettingPage.main, keywords: ['切换内核', '标准内核', '兼容内核', '双内核', '引擎', '代理组']),
  MuseSettingEntry('资源', MuseSettingPage.resources, keywords: ['规则集', '规则文件', 'geosite', 'geoip', '更新规则', '数据库']),
  MuseSettingEntry('主题预览', MuseSettingPage.themePreview, keywords: ['预览', '主题', '配色', '样式']),
  MuseSettingEntry('内核版本', MuseSettingPage.about, keywords: ['内核', '构建号', '版本号', '开源许可', '致谢']),
  MuseSettingEntry('恢复范围 / 恢复策略', MuseSettingPage.sync, keywords: ['仅订阅', '仅设置', '合并', '覆盖', '预览', '恢复']),
  MuseSettingEntry('调试日志', MuseSettingPage.developer, keywords: ['debug', '日志级别']),
  MuseSettingEntry('清除缓存', MuseSettingPage.developer, keywords: ['缓存', '临时文件']),
  MuseSettingEntry('消息样式测试', MuseSettingPage.developer, keywords: ['提示', 'toast']),
  MuseSettingEntry('崩溃记录测试', MuseSettingPage.developer, keywords: ['崩溃', 'crash']),
  MuseSettingEntry('重置引导', MuseSettingPage.developer, keywords: ['引导', '新手']),
];

/// Settings matching [query] (title, keywords or page; case-insensitive, every word must match),
/// title matches first. Empty query = nothing. 1.6.0 C10: 开发者选项 entries only with [developer].
List<MuseSettingEntry> museSearchSettings(String query, {required bool android, required bool windows, bool developer = false}) {
  final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return const [];
  bool visible(MuseSettingEntry e) =>
      (!e.androidOnly || android) && (!e.windowsOnly || windows) && (developer || e.page != MuseSettingPage.developer);
  String hay(MuseSettingEntry e) => [e.title, ...e.keywords, e.page.path].join(' ').toLowerCase();
  final hits = [for (final e in museSettingEntries) if (visible(e) && words.every(hay(e).contains)) e];
  bool inTitle(MuseSettingEntry e) => words.every(e.title.toLowerCase().contains);
  return [...hits.where(inTitle), ...hits.where((e) => !inTitle(e))];
}
