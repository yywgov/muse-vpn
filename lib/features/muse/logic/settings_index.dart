// 穿云 1.5.0 #101 - 设置 search: every setting with the page it lives on (pure logic, unit-tested).
// Part of 穿云 (GPLv3).

import 'package:flutter/foundation.dart' show kDebugMode;

/// The page a setting lives on. 1.20.3：设置一级 外观、启动与断线、分流规则、网络、隐私与通知、活动、诊断、内核与资源、
/// 备份与恢复、关于（+ 开发者选项）；旧名都留着能搜到。1.10.0: the 设置 home page has 8 rows (外观, 自动连接, 分应用代理,
/// 网络, 活动, 备份与同步, 内核与资源, 关于); rows that moved elsewhere keep their old names here so
/// search still finds them, with the path of their new place. 1.11.0: removed settings (配色风格, 文字缩放,
/// 隐藏桌面图标, 局域网同步, WebDAV 同步, 每周本地快照, 连接质量提醒, 导出 CSV) are gone from search too.
enum MuseSettingPage {
  advanced('设置 › 网络 › 高级'),
  appearance('设置 › 外观'),
  // 1.20.3：隐私 → 隐私与通知（+ Android 通知栏断开按钮、隐藏通知、在最近任务中隐藏）
  privacy('设置 › 隐私与通知'),
  // 1.20.3：节点设置只留显示相关
  nodes('节点 › ⋯ › 节点设置'),
  // 1.20.2：订阅页并入节点页；1.20.3：分流规则排在网络前面
  routing('设置 › 分流规则'),
  // 1.20.3：自定义规则列表（原 Hiddify「路由」页）挂回 /settings，页标题「我的规则」
  myRules('设置 › 分流规则 › 我的规则'),
  network('设置 › 网络'),
  // 1.20.3：导出 / 导入配置从关于页搬到设置一级「备份与恢复」
  sync('设置 › 备份与恢复'),
  stats('设置 › 活动 › 统计'),
  developer('设置 › 开发者选项'),
  // 1.20.3：分应用代理进了分流规则页（路由 /settings/per-app 不变）
  perApp('设置 › 分流规则 › 分应用代理'),
  // 1.20.3：诊断升为设置一级（原 活动 › 诊断）
  diagnose('设置 › 诊断'),
  about('设置 › 关于'),
  // 1.6.0 C10
  resources('设置 › 内核与资源'),
  themePreview('设置 › 开发者选项 › 主题预览'),
  // 1.8.0
  activity('设置 › 活动'),
  // 1.9.0；1.20.3：自动连接 → 启动与断线
  autoConnect('设置 › 启动与断线'),
  // 1.20.3：按需运行 + 按 Wi‑Fi 切换模式 合成一页
  wifiRules('设置 › 启动与断线 › Wi‑Fi 规则'),
  // 1.9.0 #17；1.20.3：订阅弹层 ⋯ › 全部覆写（单个订阅在 订阅名 ▾ › ⋮ › 订阅覆写）
  overrides('节点 › 订阅名 ▾ › ⋯ › 全部覆写'),
  // 1.20.2：订阅弹层（节点页标题「订阅名 ▾」）
  subscriptions('节点 › 订阅名 ▾ › ⋯'),
  // 1.20.3：订阅自动更新、更新后测速、更新方式、订阅 UA
  subSettings('节点 › 订阅名 ▾ › ⋯ › 订阅设置'),
  // 1.20.3：开源许可与致谢 → 开源许可（致谢分组已删）
  openSource('设置 › 关于 › 开源许可'),
  // 1.11.0；1.20.3：节点设置不再有「高级」，重复判断在「隐藏重复节点」下面（保留给旧条目）
  nodesAdvanced('节点 › ⋯ › 节点设置'),
  windowAdvanced('设置 › 外观 › 窗口 › 高级');

  const MuseSettingPage(this.path);

  final String path;
}

class MuseSettingEntry {
  const MuseSettingEntry(this.title, this.page, {this.keywords = const [], this.androidOnly = false, this.windowsOnly = false, this.debugOnly = false});

  final String title;
  final MuseSettingPage page;
  final List<String> keywords;
  final bool androidOnly;
  final bool windowsOnly;

  /// 1.9.0 #9: a 测试页 under 开发者选项, found only in debug builds
  final bool debugOnly;
}

const museSettingEntries = <MuseSettingEntry>[
  // 1.20.3：深浅色 / 纯黑 / 主题 / 外观 四条并成一条靠关键词命中（旧名都在关键词里）
  MuseSettingEntry('外观', MuseSettingPage.appearance, keywords: ['主题', '深色', '浅色', '夜间', '深浅色', '纯黑', '配色']),
  MuseSettingEntry('深浅色', MuseSettingPage.appearance, keywords: ['深色模式', '浅色模式', '跟随系统', '配色']),
  MuseSettingEntry('纯黑', MuseSettingPage.appearance, keywords: ['黑色', 'OLED', '省电', '深色模式', 'AMOLED', '配色']),
  // 1.18.0 P6
  // 1.19.0 P5
  MuseSettingEntry('主题', MuseSettingPage.appearance, keywords: ['浅色', '纯黑', '终端绿', '暖纸', '配色', '皮肤', '黑底绿字', '米色', '纸']),
  // 1.20.3：深浅色、纯黑、主题合成「配色」一组；旧名字的条目放在前面，搜旧名先出旧名
  MuseSettingEntry('配色', MuseSettingPage.appearance, keywords: ['深浅色', '深色模式', '浅色模式', '跟随系统', '纯黑', '黑色', 'OLED', '省电', 'AMOLED', '主题', '终端绿', '暖纸', '皮肤', '黑底绿字', '米色', '纸']),
  // 1.20.3：首页样式（新首页 / 经典首页）并入首页风格，「经典」是第四张
  MuseSettingEntry('首页风格', MuseSettingPage.appearance, keywords: ['留白', '细线', '数字', '经典', '风格', '首页外观', '密度', '大字时长', '首页样式', '经典首页', '旧首页']),
  MuseSettingEntry('首页样式', MuseSettingPage.appearance, keywords: ['新首页', '经典首页', '旧首页', '路由图', '弧线图', '地图', '首页', '首页风格']),
  MuseSettingEntry('动效', MuseSettingPage.appearance, keywords: ['动画', '移除动画', '减少动画', '省电模式', '精简']),
  MuseSettingEntry('主题色', MuseSettingPage.appearance, keywords: ['颜色', '强调色', '中国传统色', '传统色', '景泰蓝', '宝蓝', '竹青', '松花', '胭脂', '枣红', '藤黄', '青碧', '丁香', '赭石', '蓝', '绿', '紫', '青', '红', '黄', '灰', '棕']),
  MuseSettingEntry('自定义主题色', MuseSettingPage.appearance, keywords: ['十六进制', 'hex', '#', '自定义颜色', '取色']),
  // 1.20.3：编辑首页卡片（首页标题栏 ✎ 或长按卡片；外观里的入口交给外观原型）
  MuseSettingEntry('编辑首页卡片', MuseSettingPage.appearance, keywords: ['编辑首页', '首页卡片', '卡片', '服务状态', '代理组', '内存']),
  // 1.20.3：隐私 → 隐私与通知
  MuseSettingEntry('隐私与通知', MuseSettingPage.privacy, keywords: ['隐私', '隐私模式', '截屏', '剪贴板', '安全', '通知', '最近任务']),
  MuseSettingEntry('隐私', MuseSettingPage.privacy, keywords: ['隐私模式', '截屏', '剪贴板', '安全']),
  MuseSettingEntry('隐私模式', MuseSettingPage.privacy, keywords: ['模糊', '截图', '打码']),
  MuseSettingEntry('敏感页禁止截屏', MuseSettingPage.privacy, keywords: ['截屏', '截图', '录屏', '防截屏', '安全', '隐私'], androidOnly: true),
  MuseSettingEntry('智能保持连接', MuseSettingPage.autoConnect, keywords: ['断线', '重连', '重启内核', '断线处理', '保持连接']),
  // 1.11.0；1.20.3：搬到 启动与断线 › 断线处理
  MuseSettingEntry('节点失效自动切换', MuseSettingPage.autoConnect, keywords: ['自动切换', '故障转移', '失效', '同地区', '换节点', '断线处理', '保持连接']),
  MuseSettingEntry('隐藏通知', MuseSettingPage.privacy, keywords: ['通知', '隐私'], androidOnly: true),
  MuseSettingEntry('去广告', MuseSettingPage.routing, keywords: ['广告', '拦截', '温和', '强力', '规则来源']),
  // 1.20.3：订阅弹层 ⋯ › 订阅设置
  MuseSettingEntry('订阅设置', MuseSettingPage.subSettings, keywords: ['订阅自动更新', '更新间隔', '订阅更新方式', '订阅 UA', '更新后测速']),
  MuseSettingEntry('订阅自动更新', MuseSettingPage.subSettings, keywords: ['更新间隔', '订阅']),
  MuseSettingEntry('更新后测速新增节点', MuseSettingPage.subSettings, keywords: ['测速', '新节点', '订阅更新']),
  // 1.20.2：订阅页没有了，搜索「订阅」打开订阅弹层
  MuseSettingEntry('订阅列表', MuseSettingPage.subscriptions, keywords: ['订阅', '切换订阅', '添加订阅', '全部更新']),
  // 单个订阅的设置在 订阅名 ▾ › ⋮
  MuseSettingEntry('请求头', MuseSettingPage.subscriptions, keywords: ['订阅请求头', 'Header', '单个订阅']),
  MuseSettingEntry('节点筛选（单个订阅）', MuseSettingPage.subscriptions, keywords: ['此订阅', '只显示', '排除', '正则', '节点筛选']),
  MuseSettingEntry('分应用代理', MuseSettingPage.perApp, keywords: ['应用', 'App', '绕过', '不走代理'], androidOnly: true),
  // 1.10.0: 设置 › 节点 is 节点 › ⋯ › 节点设置 now；1.20.3：「节点」「节点设置」一条
  MuseSettingEntry('节点设置', MuseSettingPage.nodes, keywords: ['节点', '测速记录', '显示']),
  MuseSettingEntry('节点', MuseSettingPage.nodes, keywords: ['节点设置', '测速记录']),
  MuseSettingEntry('节点名美化', MuseSettingPage.nodes, keywords: ['国旗', '名称']),
  MuseSettingEntry('隐藏重复节点', MuseSettingPage.nodes, keywords: ['重复']),
  MuseSettingEntry('重复判断', MuseSettingPage.nodesAdvanced, keywords: ['去重', '地址', '端口', '完整参数']),
  MuseSettingEntry('只显示 / 排除', MuseSettingPage.nodes, keywords: ['过滤', '筛选', '正则', '全部订阅']),
  MuseSettingEntry('显示全部已隐藏节点', MuseSettingPage.nodes, keywords: ['已隐藏', '手动隐藏', '恢复节点']),
  MuseSettingEntry('订阅 UA', MuseSettingPage.subSettings, keywords: ['User-Agent', '格式', '客户端']),
  MuseSettingEntry('订阅更新方式', MuseSettingPage.subSettings, keywords: ['走代理', '直连', '订阅下载']),
  MuseSettingEntry('清除测速记录', MuseSettingPage.nodes, keywords: ['延迟', '缓存']),
  MuseSettingEntry('订阅覆写', MuseSettingPage.overrides, keywords: ['覆写', '覆写脚本', '追加节点', '代理组', '自定义规则', 'override', '全部覆写']),
  MuseSettingEntry('分流规则', MuseSettingPage.routing, keywords: ['规则', '路由规则', '分流', '生效顺序']),
  // 1.20.3：规则 / 全局（原来只有首页胶囊、托盘能改）
  MuseSettingEntry('规则 / 全局模式', MuseSettingPage.routing, keywords: ['模式', '规则模式', '全局模式', '全局', '代理模式']),
  // 1.20.3：自定义规则列表 → 我的规则（原 Hiddify「路由」页）
  MuseSettingEntry('我的规则', MuseSettingPage.myRules, keywords: ['自定义规则', '自定义规则列表', '路由', '规则列表', '恢复默认规则']),
  MuseSettingEntry('自定义规则列表', MuseSettingPage.myRules, keywords: ['路由', '我的规则']),
  MuseSettingEntry('分流预设', MuseSettingPage.routing, keywords: ['规则', 'ChatGPT', 'Netflix', 'Telegram', '国内直连', '预设']),
  MuseSettingEntry('指定节点', MuseSettingPage.routing, keywords: ['网站走某个节点', '应用走某个节点', '我的规则']),
  MuseSettingEntry('来自连接的规则', MuseSettingPage.routing, keywords: ['直连', '走代理', '连接', '我的规则']),
  MuseSettingEntry('已屏蔽的网站', MuseSettingPage.routing, keywords: ['屏蔽', '拦截', '取消屏蔽', '连接', '我的规则']),
  MuseSettingEntry('远程规则集', MuseSettingPage.routing, keywords: ['规则订阅', 'rule-set', '规则来源']),
  MuseSettingEntry('规则测试', MuseSettingPage.routing, keywords: ['匹配', '走哪条', '命中']),
  // 1.20.3：挪到 网络 › DNS
  MuseSettingEntry('自定义 hosts', MuseSettingPage.network, keywords: ['hosts', '域名解析', 'DNS']),
  MuseSettingEntry('导入 / 导出 / 粘贴规则', MuseSettingPage.routing, keywords: ['Clash', 'Surge', '规则', '⋯']),
  MuseSettingEntry('远程 DNS', MuseSettingPage.network, keywords: ['DNS', '解析']),
  // 1.20.3：关键词去掉「网络」（搜「网络」不再先出它）
  MuseSettingEntry('每天定时连接 / 断开', MuseSettingPage.autoConnect, keywords: ['定时', '计划']),
  MuseSettingEntry('导出 / 导入配置', MuseSettingPage.sync, keywords: ['导出配置', '导入配置', '备份', '恢复', '导出 / 恢复备份', '脱敏', '导出脱敏备份', '加密', '同步与备份']),
  // 1.20.3：设置一级「备份与恢复」；备份与同步、同步与备份是旧名
  MuseSettingEntry('备份与恢复', MuseSettingPage.sync, keywords: ['备份与同步', '同步与备份', '同步', '备份', '导出配置', '导入配置']),
  MuseSettingEntry('备份与同步', MuseSettingPage.sync, keywords: ['同步与备份', '同步', '备份']),
  // 1.20.3：统计 / 流量统计 合一条
  MuseSettingEntry('流量统计', MuseSettingPage.stats, keywords: ['统计', '流量', '用量', '图表', '月报']),
  MuseSettingEntry('统计', MuseSettingPage.stats, keywords: ['流量', '用量']),
  // 1.10.0: 「高级」 is a group of 设置 › 网络
  MuseSettingEntry('高级', MuseSettingPage.advanced, keywords: ['负载均衡', 'IPv6', 'Fake-IP', '关闭旧连接']),
  MuseSettingEntry('负载均衡策略', MuseSettingPage.advanced, keywords: ['负载均衡']),
  MuseSettingEntry('TLS 分片', MuseSettingPage.network, keywords: ['分片', '混淆']),
  MuseSettingEntry('IPv6', MuseSettingPage.advanced, keywords: ['v6']),
  MuseSettingEntry('Fake-IP', MuseSettingPage.advanced, keywords: ['虚拟地址', 'TUN']),
  MuseSettingEntry('不走代理的地址', MuseSettingPage.advanced, keywords: ['系统代理', '绕过', '例外', 'bypass'], windowsOnly: true),
  MuseSettingEntry('允许商店应用走代理', MuseSettingPage.network, keywords: ['UWP', '商店', '回环', 'loopback'], windowsOnly: true),
  MuseSettingEntry('屏蔽 QUIC', MuseSettingPage.network, keywords: ['UDP', 'YouTube', 'HTTP/3']),
  // 1.8.0: 连接 / 日志 / DNS are the tabs of 活动
  MuseSettingEntry('活动', MuseSettingPage.activity, keywords: ['连接', '日志', 'DNS', '统计']),
  MuseSettingEntry('连接', MuseSettingPage.activity, keywords: ['连接列表', '实时连接', '连接信息', '请求', '屏蔽']),
  MuseSettingEntry('日志', MuseSettingPage.activity, keywords: ['日志记录', '实时日志', '导出日志']),
  MuseSettingEntry('DNS 查询', MuseSettingPage.activity, keywords: ['DNS', '域名解析', '解析记录', '缓存命中', 'Fake-IP']),
  MuseSettingEntry('切换节点时关闭旧连接', MuseSettingPage.advanced, keywords: ['关闭连接', '断开旧连接']),
  MuseSettingEntry('测速并发数 / 超时', MuseSettingPage.developer, keywords: ['测速', '并发', '超时']),
  // 1.9.0
  MuseSettingEntry('导入后清空剪贴板', MuseSettingPage.privacy, keywords: ['剪贴板', '订阅链接', '密钥', '隐私']),
  MuseSettingEntry('导出为 sing-box 格式', MuseSettingPage.routing, keywords: ['规则', '导出']),
  MuseSettingEntry('恢复推荐 DNS', MuseSettingPage.network, keywords: ['默认', 'DNS', '还原']),
  // 1.20.3：诊断是设置一级；一键诊断、网络诊断、出口检测、解锁检测、DNS 泄漏都在这一页
  MuseSettingEntry('诊断', MuseSettingPage.diagnose, keywords: ['日志', '连不上', '排查', '反馈', '崩溃', '一键诊断', '网络诊断']),
  MuseSettingEntry('一键诊断', MuseSettingPage.diagnose, keywords: ['连不上', '端口占用', '其他 VPN']),
  MuseSettingEntry('出口与解锁', MuseSettingPage.diagnose, keywords: ['出口', '出口 IP', '解锁检测', '服务状态', 'Netflix', 'ChatGPT']),
  MuseSettingEntry('DNS 泄漏检测', MuseSettingPage.diagnose, keywords: ['DNS 泄漏', '泄露', '隐私']),
  // 1.20.3：首页卡片「网络接管」改名「运行模式」，旧名还能搜到
  MuseSettingEntry('运行模式', MuseSettingPage.network, keywords: ['TUN', '系统代理', '虚拟网卡', '网络接管'], windowsOnly: true),
  MuseSettingEntry('开机自启', MuseSettingPage.autoConnect, keywords: ['启动', '开机'], windowsOnly: true),
  MuseSettingEntry('静默启动', MuseSettingPage.autoConnect, keywords: ['托盘', '后台启动', '不弹窗口', '隐藏窗口'], windowsOnly: true),
  MuseSettingEntry('关闭窗口时', MuseSettingPage.appearance, keywords: ['托盘', '最小化', '退出', '窗口'], windowsOnly: true),
  // 1.6.0 C8
  MuseSettingEntry('开机自启时静默', MuseSettingPage.autoConnect, keywords: ['开机', '托盘', '不弹窗口'], windowsOnly: true),
  MuseSettingEntry('穿云标题栏', MuseSettingPage.windowAdvanced, keywords: ['标题栏', '系统标题栏', '窗口边框', '窗口'], windowsOnly: true),
  MuseSettingEntry('窗口置顶', MuseSettingPage.windowAdvanced, keywords: ['置顶', '最前面', '总在最前', '窗口'], windowsOnly: true),
  // 1.20.3：按需运行与按 Wi‑Fi 切换模式在同一页「Wi‑Fi 规则」
  MuseSettingEntry('Wi‑Fi 规则', MuseSettingPage.wifiRules, keywords: ['Wi-Fi', 'WiFi', '无线', '按需运行', '暂停', '切换模式']),
  MuseSettingEntry('按需运行', MuseSettingPage.wifiRules, keywords: ['Wi-Fi', 'WiFi', '无线', '暂停', '家里', '公司']),
  MuseSettingEntry('按 Wi‑Fi 切换模式', MuseSettingPage.wifiRules, keywords: ['Wi-Fi', 'WiFi', '无线', '规则', '全局', '模式']),
  MuseSettingEntry('快捷键', MuseSettingPage.windowAdvanced, keywords: ['全局快捷键', '热键', '键盘'], windowsOnly: true),
  // 1.6.0 C9 (Android 通用)；「自动运行」是旧名，仍能搜到
  MuseSettingEntry('打开即连接', MuseSettingPage.autoConnect, keywords: ['自动运行', '自动连接', '启动时连接'], androidOnly: true),
  // 1.20.3：自动连接 → 启动与断线
  MuseSettingEntry('启动与断线', MuseSettingPage.autoConnect, keywords: ['自动连接', '打开即连接', '开机自启', '断线处理', 'Wi‑Fi 规则', '定时连接', '定时断开']),
  MuseSettingEntry('自动连接', MuseSettingPage.autoConnect, keywords: ['打开即连接', '自动运行', '开机自启', '按需运行', '定时连接', '定时断开', '启动与断线']),
  MuseSettingEntry('通知栏断开按钮', MuseSettingPage.privacy, keywords: ['通知', '断开', '停止按钮'], androidOnly: true),
  // 1.10.2；1.20.3：搬到 隐私与通知
  MuseSettingEntry('在最近任务中隐藏', MuseSettingPage.privacy, keywords: ['最近任务', '多任务', '后台列表', '隐藏', '不在最近任务显示'], androidOnly: true),
  MuseSettingEntry('检查更新', MuseSettingPage.about, keywords: ['版本', '更新内容']),
  // 1.6.0 C10；1.20.3：内核 / 内核与资源 / 内核版本 三条留着（旧名），关键词互相覆盖
  MuseSettingEntry('内核与资源', MuseSettingPage.resources, keywords: ['资源', '内核', '规则集', '规则文件', '更新规则', '数据库', '切换内核', '内核版本']),
  MuseSettingEntry('内核', MuseSettingPage.resources, keywords: ['切换内核', '标准内核', '兼容内核', '双内核', '引擎', '代理组', '内核与资源']),
  MuseSettingEntry('地理规则库', MuseSettingPage.resources, keywords: ['geosite', 'geoip', '数据库', '内置规则集', '检查并修复', '资源']),
  MuseSettingEntry('规则集', MuseSettingPage.resources, keywords: ['远程规则集', '规则文件', '下载状态', '资源']),
  MuseSettingEntry('主题预览', MuseSettingPage.themePreview, keywords: ['预览', '主题', '配色', '样式', '单选示例', '开关示例', '开发者选项'], debugOnly: true),
  MuseSettingEntry('内核版本', MuseSettingPage.resources, keywords: ['内核', '版本号', '内核与资源']),
  MuseSettingEntry('版本与构建号', MuseSettingPage.about, keywords: ['构建号', '版本号']),
  // 1.10.0: license, source and the credits on one page under 关于
  MuseSettingEntry('开源许可', MuseSettingPage.openSource, keywords: ['开源许可', '源代码', 'GPL', '许可证']),
  MuseSettingEntry('恢复范围 / 恢复策略', MuseSettingPage.sync, keywords: ['仅订阅', '仅设置', '合并', '覆盖', '预览', '恢复']),
  MuseSettingEntry('调试日志', MuseSettingPage.developer, keywords: ['debug', '日志级别']),
  MuseSettingEntry('清除缓存', MuseSettingPage.developer, keywords: ['缓存', '临时文件']),
  MuseSettingEntry('消息样式测试', MuseSettingPage.developer, keywords: ['提示', 'toast'], debugOnly: true),
  MuseSettingEntry('崩溃记录测试', MuseSettingPage.developer, keywords: ['崩溃', 'crash'], debugOnly: true),
  MuseSettingEntry('重置引导', MuseSettingPage.developer, keywords: ['引导', '新手']),
];

/// Settings matching [query] (title, keywords or page; case-insensitive, every word must match),
/// title matches first. Empty query = nothing. 1.6.0 C10: 开发者选项 entries only with [developer].
/// 1.9.0 #9: 测试页 entries only with [developer] in a debug build ([debugBuild]).
List<MuseSettingEntry> museSearchSettings(String query, {required bool android, required bool windows, bool developer = false, bool debugBuild = kDebugMode}) {
  final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return const [];
  bool visible(MuseSettingEntry e) =>
      (!e.androidOnly || android) &&
      (!e.windowsOnly || windows) &&
      (developer || e.page != MuseSettingPage.developer) &&
      (!e.debugOnly || (developer && debugBuild));
  String hay(MuseSettingEntry e) => [e.title, ...e.keywords, e.page.path].join(' ').toLowerCase();
  final hits = [for (final e in museSettingEntries) if (visible(e) && words.every(hay(e).contains)) e];
  bool inTitle(MuseSettingEntry e) => words.every(e.title.toLowerCase().contains);
  return [...hits.where(inTitle), ...hits.where((e) => !inTitle(e))];
}

/// 1.8.0: the 活动 tab a search result opens (by its title: 日志 / DNS 查询 / everything else 连接).
String museActivityTabKeyForSetting(String title) => switch (title) {
  '日志' => 'logs',
  'DNS 查询' => 'dns',
  // 1.10.0: 统计 is a tab of 活动（1.20.3：诊断不再是 tab，是设置一级）
  '统计' || '流量统计' => 'stats',
  _ => 'connections',
};

/// 1.20.3：诊断页打开到哪一块（出口与解锁 → 'exit'；其余页顶）。
String? museDiagnoseSectionForSetting(String title) => title == '出口与解锁' ? 'exit' : null;
