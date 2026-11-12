// 穿云 1.22.0 F20 - 术语表（界面用词，一处定义）。只管界面文案，存储键、偏好名、内核字段都不变；
// 旧叫法留在设置搜索的关键词里，搜旧名照样找得到。协议名（VLESS、Hysteria2 等）不翻译。
//   代理组 / 策略组 → 分组
//   模式（规则 / 全局） → 分流模式
//   运行模式 / 网络接管（TUN / 系统代理） → 接管方式
//   覆写 / 订阅覆写 → 订阅修改
//   出站 → 交给；入站 → 来自；链路 → 经过
//   测速（延迟） → 测延迟；下载测速 → 测网速
// Part of 穿云 (GPLv3).

import 'package:hiddify/singbox/model/singbox_config_enum.dart' show ServiceMode;

/// 节点的集合（订阅里的 selector / urltest 等）。
const museGroupTerm = '分组';

/// 规则 / 全局。
const museRouteModeTitle = '分流模式';

/// TUN / 系统代理（Windows）。
const museTakeoverTermTitle = '接管方式';

/// 单个订阅叠加在订阅上的规则、节点、分组（原「覆写」）。
const museOverrideTitle = '订阅修改';

/// 延迟测试按钮。
const museLatencyTestTitle = '测延迟';

/// 下载测试。
const museSpeedTestTitle = '测网速';

/// 接管方式的取值。
String museTakeoverTitle(ServiceMode mode) => mode == ServiceMode.tun ? 'TUN' : '系统代理';
