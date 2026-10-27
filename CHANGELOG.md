# Changelog

## 穿云

穿云各版本的改动（新在前）。完整说明见 [Releases](https://github.com/yywgov/muse-vpn/releases)。

### 1.6.1 - 2026-10-28

- 修复：页面无法滑到最底部、最后几项被底栏遮挡（1.6.0 悬浮底栏盖住了每个可滚动页面底部约 100 dp）。手机上页面现在止于底栏顶边（悬浮 / 固定两种底栏），平板侧栏与 Windows 窗口止于系统手势条 / 三键导航之上；共用的底部留白只读 MediaQuery 现有值
- 新配色：整个应用改用由主题色生成的 Material 3 配色（表面近中性，深色四级表面，纯黑仍为 #000）；外观新增「配色风格」：标准（默认）/ 鲜艳 / 表现力 / 柔和 / 鲜明（保留主题色本身）/ 着色（表面带主题色）/ 单色，参与同步与备份，设置搜索可搜到
- 组件样式：首页连接卡、底栏与侧栏的色调选中指示、分组列表与设置分组标题、节点选中标记、分段按钮；订阅卡片改为 M3 填充卡（当前订阅为次要容器色，左侧菜单方块，菜单图标统一为 outlined）
- 性能与耗电：配色方案与 ThemeData 按（主题色、配色风格、深浅、纯黑、字体）缓存，切换风格只计算一次、切回已用过的风格不再计算；首页「已连接」计时只在页面可见且应用在前台时运行；本版不新增任何后台唤醒、轮询或常驻动画

### 1.6.0 - 2026-10-27

- 界面：新的设计基础（配色、表面层级、超椭圆圆角、字号阶梯）；所有平台按窗口宽度布局——窄屏底栏（悬浮 / 固定可选）、中等宽度图标侧栏、宽屏可展开侧栏（记住展开状态，直达「连接」，开启日志记录后直达「日志」）；切换页面 淡入 / 滑动，尊重「减少动画」；窗口最小 360×560；Android 预测性返回
- 连接与日志：新「连接」页（活动连接 / 请求记录，搜索、排序、关闭单条或全部、详情、屏蔽此域名并可撤销）；新「日志」页（日志记录开关、级别、搜索、暂停、复制 / 导出已脱敏，最多保留 1000 行、不写磁盘）；手动切换节点后自动关闭旧连接（可关）；本地控制接口使用每台设备单独生成的密钥
- 首页：新增 服务状态（Google、GitHub、YouTube、ChatGPT 等 13 个服务经当前节点检测，缓存 10 分钟）、代理组、连接统计、内网 IP（点按复制）、内存，Windows 新增 网络接管（系统代理 / TUN）；新卡片默认隐藏，可在编辑首页里打开；宽窗口四列
- 节点：列表 / 卡片布局，紧凑 / 标准 / 宽松卡型（列数随宽度与字号），「滚动到当前节点」千节点可用；节点页不再限制宽度
- 订阅：1–3 列卡片、拖动排序（只记顺序，不删订阅）、复制链接（先确认）、查看运行配置（已脱敏）、批量粘贴多条订阅链接
- 外观：新增 青 / 靛 / 粉 / 橙 主题色与自定义十六进制颜色（最多保存 8 个）；深色下「纯黑」；「文字缩放」80–140 % 取代字体大小（旧设置自动换算）；主题预览
- Windows：托盘新增 系统代理 / TUN 模式、开机自启、复制终端代理命令（CMD / PowerShell / Bash），节点子菜单最多 30 个 +「更多…」；全局快捷键 7 个动作（默认不绑定，须带 Ctrl / Alt / Win，拒绝常用系统组合与重复）；穿云标题栏（可改回系统标题栏）与窗口置顶；静默启动、开机自启时静默；按需运行（列入的 Wi‑Fi 上暂停、离开后恢复，手动操作优先）
- Android：自动化指令 com.chuanyun.app.action.START / STOP / TOGGLE；通知栏「断开」按钮可关；自动运行（每次打开只连一次）；按需运行（只在开启时申请位置信息权限，读不到 Wi‑Fi 名称时不改连接）；分应用代理 排序、全选 / 反选、只看联网应用、剪贴板导入（非法包名忽略）/ 导出、清除所有选择；设置 › 通用（Android）
- 设置：新「资源」页（内置规则集 名称 / 大小 / 写入时间，检查并修复缺失或损坏的副本，远程规则集列表）；从备份恢复先预览，可选 恢复范围（全部 / 仅订阅 / 仅设置）与策略（合并 / 覆盖，覆盖需二次确认，恢复前自动备份，订阅只增不删）；关于页显示版本与构建号、内核版本与开源致谢；连点版本号 7 次开启开发者选项（清除测速记录、调试日志、清除缓存、重置引导等）；设置搜索覆盖新增项目
- 性能：节点延迟更新只重建对应节点（1000 个节点逐个出结果时每次最多重建 2 行），排序变化时行移动而不重建；首页「已连接」计时独立刷新，不再每秒重建整张卡片；修复离开连接 / 日志页后、内核没有新日志时数据流不关闭的问题；启动时新功能（快捷键、按需运行、服务检测、资源页）不做任何工作

### 1.5.4 - 2026-10-26

- 节点筛选：按协议筛选；节点可加本地标签（家宽 / 流媒体 / 游戏 / 自定义）并按标签筛选；可手动指定节点地区（覆盖名称识别）；按地区排序时不常用地区默认折叠，记住用户的展开 / 折叠
- 节点页：顶部固定当前节点卡（点开详情）；「最近」快捷切回最近用过的节点（最多 5 个）；详情显示最近 10 次延迟迷你折线（超时为红点）
- 节点详情：二维码分享；「复制节点」可选 链接 / Clash / JSON 配置；中转节点（中转 / IPLC / IEPL / 专线等）显示入口与出口
- 收藏：节点页排序菜单「收藏排序…」拖动排序，可恢复按列表顺序
- 去重：设置 › 节点 ›「重复判断」可选 协议+地址+端口（默认）/ 地址+端口 / 完整参数
- 清除不可用节点：先预览将隐藏的节点（收藏和正在使用的保留），确认后可撤销；只隐藏，不删除订阅里的节点

### 1.5.3 - 2026-10-25

- 修复：切换订阅后「节点」页仍显示上一个订阅的节点。原因是连接中切换时，旧内核的节点列表被当成新订阅的列表显示并保存。现在每个订阅单独保存节点列表；连接中切换会等内核重载到新订阅后再显示，断开时直接显示该订阅自己的列表（从未连接过的订阅显示「连接后显示节点」）
- 节点页：顶部显示「订阅名 · N 个节点」；协议改为名字后的小标签（VLESS、HY2、SS…），第二行只显示备注；未知地区节点用灰色图标；「自动最快」和首页显示的节点名与列表一致（使用美化/重命名后的名字）
- 出口 IP：按订阅、节点、分流模式和本地网络缓存结果并保存，打开首页或诊断时立即显示；只有节点 / 订阅 / 连接状态 / 网络变化或超过 10 分钟才重新检测；检测时保留旧结果并显示小转圈；诊断里新增「刷新」

### 1.5.2 - 2026-10-24

- 修复：新版服务器拒绝 REALITY 节点连接。内核升级到 5.0.0-muse.17，握手里上报的客户端版本号从 1.8.1 改为 26.10.21，可通过服务端的最低客户端版本限制（部分服务端默认要求 26.3.27 及以上）

### 1.5.1 - 2026-10-24

- 界面：首页「去广告」关 / 温和 / 强力 分段切换重做——三段等宽、文字水平垂直居中（中文不再偏下）、选中块四周等距且高度随字号放大，320px + 2× 字号不溢出；「统计」的 日 / 周 / 月 改用同一控件
- 更新：移除「关于」里的「Beta 通道」开关（项目不发布预发布版），应用内更新只检查正式版；旧设置值保留但不再读取

### 1.5.0 - 2026-10-24

- REALITY：内核升级到 5.0.0-muse.16，只有原生带抗量子密钥的 Chrome/Edge 指纹才发送 X25519MLKEM768，Firefox/随机指纹改用 X25519；握手失败自动换另一种方式重试一次并记住
- 连接：按钮状态机（连接中可取消、断开中不重复触发）、连接阶段文字、启动前本地预检（端口/订阅/MTU/DNS/测速地址）、常见错误翻译成人话（保留原始信息）、内核出错时诊断里保留最后 200 行内核日志
- 节点：千节点订阅列表按需构建、测速进度「已测 x / y」、详情显示传输/TLS/ALPN/指纹/端口跳跃、当前节点 5 MB 下载测速
- 订阅：更新方式 自动/走代理/直连；更新失败显示 HTTP 状态码与建议；单个订阅的「只显示/排除」；没有流量头时从「剩余流量/到期」条目或 STATUS= 读取；订阅链接默认打码；明文 http 订阅提醒
- 分流：粘贴 Clash/Surge 规则自动转换；局域网规则固定第一且不可关；连接中修改设置、规则、hosts、指定节点自动热重载
- 高级选项（默认关闭）：IPv6 优先 v4/v6、Fake-IP（局域网/对时/联网检测排除）、屏蔽 QUIC
- 设置搜索；流量统计新增「周」；恢复备份或应用更新前自动备份当前配置（保留 5 份，可在「同步与备份 › 自动备份」还原）；更新下载换镜像时保留已下载的分段
- Windows：托盘三态（灰/蓝/连接但上不了网时橙），安装版通知发送者显示「穿云」；局域网同步失败提示同一 Wi‑Fi / AP 隔离 / 防火墙
- 诊断：一键「反馈问题」（复制脱敏诊断与崩溃记录并打开 GitHub Issue）
- 界面：全 App 统一线性图标、浅色次级文字对比度 ≥4.5:1、骨架屏、统一 Toast、尊重系统「减少动画」、320px + 2× 字号首页自动单列、去广告磁贴默认隐藏、长说明收进 ⓘ、小版本只显示红点；测速并发/超时移到开发者选项
- 发布：Release 附 .sha256 校验文件；CI 记录 APK 体积并扫描依赖漏洞

### 1.4.1 - 2026-10-23

- 修复 2026 年 9 月以后新开服务器上的 REALITY 节点连不上：内核升级到 5.0.0-muse.15，恢复 REALITY 的抗量子密钥交换（X25519MLKEM768）
- 局域网扫码同步：同一网络下两台设备扫码即可同步订阅与设置；坚果云 WebDAV 移到「更多」
- 分流预设增至 25 个：新增 Google、YouTube、Netflix、Spotify、TikTok、X、Meta、Discord、GitHub 开发者、海外支付、加密货币、Amazon、国内 App 直连、BT 直连、游戏下载直连；预设分组并支持搜索
- 应用内更新：多个镜像自动选最快，新增 Beta 通道
- 连接诊断向导与一键修复；电脑睡眠唤醒后自动重新检测连接
- Windows：修复异常退出后残留系统代理导致没网
- 安卓：检测应用在后台被系统杀掉，并给出保活设置指南
- 节点多选、指定节点、远程规则集、订阅 UA、订阅更新差异、流量提醒、定时连接、连接质量提醒、命令行参数与 `chuanyun://` 链接、崩溃日志导出
- 修复：流量重复统计、定时连接第二天不触发、同步覆盖本地或已删除的订阅复活、弹窗泄漏、大字号下首页卡片溢出、更新包安全校验

### 1.2.9 - 2026-10-21

- 修复 Cloudflare Workers/Pages 自建 VLESS/Trojan 节点（edgetunnel、CF-Workers-SUB 等「CF官方优选」订阅）开启 ECH 后在穿云里全部测速超时、显示「INVALID INITIALIZE OUTBOUND…」的问题：链接里的 `ech=cloudflare-ech.com+https://dns.alidns.com/dns-query` 现在按 Xray 的含义处理（向 DNS 查询 ECH 配置），查询走直连 DNS，查不到时不带 ECH 继续连接
- 兼容更多节点写法：未知的 uTLS 指纹（fp）回退为 chrome、SNI 为空时用 Host、sing-box/Clash 配置里路径带 `?ed=` 转成 0-RTT 早期数据、VLESS 加密字段写成 aes-128-gcm 等、非法 packet_encoding
- 已经导入的订阅无需更新即生效
- 无法使用的节点副标题改为「节点配置不兼容：原因」，长按节点可查看并复制完整错误

### 1.2.8 - 2026-10-21

- 去广告分「温和 / 强力」两档，默认温和，避免误拦导致 App 打不开
- 长按节点：收藏置顶、只测这个节点
- 自动隐藏「剩余流量 / 到期 / 官网」等非节点条目（设置里可关）
- 记住每个订阅上次选择的节点
- 流量用到 80%、用完、到期前 3 天发通知（Windows 也有）
- 订阅自动更新间隔可选，更新失败会提示
- 连上后自动检测外网，不通时首页提示换节点
- 新增一键诊断；导出日志自动脱敏
- 升级后首次打开弹出本次更新内容
- Windows 托盘图标连上即变蓝，右键菜单显示当前网速

### 1.2.7 - 2026-10-20

- 重新发布 1.2.6 的改动（1.2.6 的 Windows 包因构建检查偶发失败未发出）

### 1.2.6 - 2026-10-20

- Windows 安装包自带 VC++ 运行库，修复部分电脑提示找不到 VCRUNTIME140.dll 无法启动

### 1.2.5 - 2026-10-19

- 首页显示本次流量与当前节点
- 节点排序：延迟 / 订阅顺序 / 按地区
- 长按节点查看详情；下拉测速、更新订阅
- 订阅卡显示用量、剩余天数、更新时间
- 新手空状态引导；测速结果淡入
- 测速更稳定：不再因预热丢包误报超时

### 1.2.4 - 2026-10-19

- 连接更快：规则集随应用内置，不再等待下载
- 超时节点立即归入「不可用」
- 固定发布签名，应用内更新可直接覆盖安装；更新下载更快
- 修复 Windows 全局快捷键导致的启动崩溃

---

## 上游 Hiddify 历史版本

以下为上游 [Hiddify](https://github.com/hiddify/hiddify-app) 的原始更新日志，保留原文。

## [0.16.0.dev] - 2024-2-18

### New Features and Improvements

- Changed App name to **Hiddify**
- Changed App icon
- Added Mux (**Experimental**)
- Added Cloudflare WARP (**Experimental**)
- Added connection info
  - when connected, name of the active node, speed and IP address are shown on home page
  - delay indicator below connection button shows active node's ping
- Added VPN Service (Windows & Linux) (**Experimental**)
  - VPN Service circumvents need for administrator permission while using TUN
- Changed in-app icons (using [Fluent UI System Icons](https://github.com/microsoft/fluentui-system-icons))
- Redesigned navigation flow, separating config options
- Added haptic feedback
- Added detailed subscription info in profile edit page
- Added Chinese Taiwan language. [PR#410](https://github.com/hiddify/hiddify-next/pull/410) by [junlin03](https://github.com/junlin03) and [PR#491](https://github.com/hiddify/hiddify-next/pull/491) by [kouhe3](https://github.com/kouhe3)
- Added Japanese Readme. [PR#371](https://github.com/hiddify/hiddify-next/pull/371) by [Ikko Eltociear Ashimine](https://github.com/eltociear)

### Bug Fixes

- Fixed TLS Tricks bugs
- Fixed logs on iOS. [PR#414](https://github.com/hiddify/hiddify-next/pull/414) by [Amir Mohammadi](https://github.com/amirsaam) and [PR#416](https://github.com/hiddify/hiddify-next/pull/416) by [Ebrahim Tahernejad](https://github.com/EbrahimTahernejad)
- Fixed Android service mode
- Fixed UI inconsistencies
- Fixed Readme download URL. [PR#482](https://github.com/hiddify/hiddify-next/pull/482) by [Ali Afsharzadeh](https://github.com/guoard)

## [0.14.1.dev] - 2024-1-19

### New Features and Improvements

- Redesigned profile options on mobile
- Improved configuration parser
- Added export config json in iOS
- Added iOS URL scheme. [PR#343](https://github.com/hiddify/hiddify-next/pull/343) by [Amir Mohammadi](https://github.com/amirsaam)
- Added option to reset VPN profile on iOS

### Bug Fixes

- Fixed TLS Tricks causing app crash
- Fixed connection status on iOS app relaunch
- Fixed iOS connection stats
- Fixed infinite subscription traffic
- Fixed infinite subscription expiry. [PR#334](https://github.com/hiddify/hiddify-next/pull/334) by [Pavel Volkov](https://github.com/pvolkov)

## [0.14.0.dev] - 2024-1-14

### New Features and Improvements

- Published initial iOS beta version on TestFlight
  - Thanks to contributions from [GFWFighter](https://github.com/GFWFighter) and [Amir Mohammadi](https://github.com/amirsaam)
  - iOS version is still in heavy development phase and there are known bugs
- Added Spanish language. [PR#314](https://github.com/hiddify/hiddify-next/pull/314) by [AvatarStark](https://github.com/AvatarStark)
- Changed Routing Assets page layout, separating assets by type
- Improved descriptions for some of the options in settings page

### Bug Fixes

- Fixed Deep links on Windows
- Fixed minor UI bugs
- Fixed subscription profiles with infinite traffic

## [0.13.6] - 2024-1-7

- First stable 0.13.x release. check changes from 0.13.0.dev to 0.13.5.dev for more details.

## [0.13.5.dev] - 2024-1-6

### New Features and Improvements

- Updated sing-box to version 1.7.8
- Improved TLS Fragmentation. [PR#12](https://github.com/hiddify/hiddify-sing-box/pull/12) by [Kyōchikutō | キョウチクトウ](https://github.com/kyochikuto)
- Improved v2ray config parser
- Added cancel button on new profile modal
- Changed default Connection Test URL

### Bug Fixes

- Fixed Android service mode
- Fixed QR code scanner not scanning deep links

## [0.13.4.dev] - 2024-1-4

### New Features and Improvements

- Added update all subscriptions
  - Force update all subscription profiles regardless of their interval
- Added basic authorization support
- Changed app http client, improving experience when fetching profiles, geo assets etc.

### Bug Fixes

- Fixed profile auto update service
- Fixed localization mistakes in Chinese. [PR#288](https://github.com/hiddify/hiddify-next/pull/288) by [wldjdjsks](https://github.com/huajizhige)

## [0.13.3.dev] - 2024-1-2

### New Features and Improvements

- Added Bypass LAN option (Experimental)
- Added Connection from LAN option (Experimental)
- Added DNS Routing option
- Changed outbound options section to TLS Tricks

### Bug Fixes

- Fixed profile edit bug where you were unable to change existing profile's URL
- Fixed localization mistakes in Chinese. [PR#287](https://github.com/hiddify/hiddify-next/pull/287) by [Wu Jiahao](https://github.com/wujiahao15)

## [0.13.2.dev] - 2023-12-31

### Bug Fixes

- Fixed db migration bug

## [0.13.1.dev] - 2023-12-31

### New Features and Improvements

- Added experimental feature flag in settings
- Added notice dialog when connecting with experimental features

### Bug Fixes

- Fixed multiple instance launch on windows
- Removed auto connect on desktop which caused bugs on auto launch etc.
- Fixed inlang localization setup

## [0.13.0.dev] - 2023-12-29

### New Features and Improvements

- Added desktop shortcuts
  - Add profile from clipboard by pressing `CTRL+V` (`CMD+V` on macOS)
  - Close App window by pressing `CTRL+W` (`CMD+W` on macOS)
  - Quit App by pressing `CTRL+Q` (`CMD+Q` on macOS)
  - Open settings page by pressing `CMD+,` on macOS
- Added Android high refresh rate screen support

### Bug Fixes

- Fixed silent start bug where screen would blink
- Refactored Window management and system tray, fixing minor bugs
- Fixed windows portable release again!

## [0.12.3] - 2023-12-28

### New Features and Improvements

- Added version number in window title on desktop
- Added Afghanistan (af) region with default bypass rules

### Bug Fixes

- Fixed modal bug where config options were unmodifiable. [PR#267](https://github.com/hiddify/hiddify-next/pull/267) by [在7楼](https://github.com/RayWangQvQ)
- Fixed windows portable release

## [0.12.2] - 2023-12-23

### New Features and Improvements

- Updated Sing-box to Version 1.7.6

### Bug Fixes

- Fixed app log file not including stacktrace
- Fixed initialization process failing for non-essential dependencies
- Fixed analytics preferences requiring app restart

## [0.12.1] - 2023-12-21

### Bug Fixes

- Fixed Android service mode
- Fixed [preferences initialization error on Windows and Linux](https://github.com/flutter/flutter/issues/89211)
- Fixed incorrect privacy policy URL
- Bumped Android compile and target SDK version (34)

## [0.12.0] - 2023-12-20

### New Features and Improvements

- Added TLS Tricks (experimental)
  - Including TLS fragments and Mixed SNI case. This feature might effect performance and battery life
- Added dynamic notification on Android
  - Active profile name and transfer speed are now shown in notification
- Added basic D-pad support for Android TV
- Added soffchen to recommended geo assets
- Added option to reset Config Options
- Improved text input field's accessibility and traversal

### Bug Fixes

- Refactored significant portions of the app
- Fixed incorrect profile parsing when missing headers
- Fixed geo assets bug where assets were deactivated
- Changed default memory limit option on desktop, fixing out of memory bug on macOS
- Fixed macOS icon
- Fixed system tray behavior
- Fixed incorrect casing of locale names
- Updated sing-box to version 1.7.0
- Fixed Chinese typography bug (thanks to [betaxab](https://github.com/betaxab))
- Fixed localization mistakes in Russian. [PR#189](https://github.com/hiddify/hiddify-next/pull/189) by [jomertix](https://github.com/jomertix)

## [0.11.1] - 2023-11-19

### Bug Fixes

- Fixed Android manifest bug.

## [0.11.0] - 2023-11-19

### New Features and Improvements

- Changed Responsive UI Behavior
  - Now app is responsive on all platforms with appropriate routing setup.
- Added Simplified Service Modes
  - Choose between VPN(Tun), System Proxy and Proxy only modes. (System Proxy available on desktop)
- Added Share Functionality
  - Share configuration as json(export to clipboard) or share subscription link as QR code.
- Redesigned System Tray on Desktop
  - Options have been simplified and a new mode selector and navigation options are added.
- Added Privilege Checks for VPN(TUN) on Desktop
- Added Auto Connect on Start
  - On desktop, app will try to connect to the last used profile on startup. (if last session was not explicitly disconnected by the user)
- Added AppCast Update Checker
  - Checking for new versions of the app will use a more reliable approach on all platforms.
- Added Geo Asset Settings
  - Update geo assets and use recommended providers
- Added **winget** Release
  - Now you're able to install and update Hiddify on Windows using [winget](https://learn.microsoft.com/en-us/windows/package-manager/winget/).
- Added Turkish Translations. [PR#173](https://github.com/hiddify/hiddify-next/pull/173) by [Hasan Karlı](https://github.com/hasankarli)
- Changed in-app Toasts
- Updated Core Sing-box Version to 1.7.0
- Improved Network Reliability While Adding/Updating Subscriptions
- Improved QR Code Scanner

### Bug Fixes

- Removed **execute config as is** option which caused crashes and confusion for users.
- Fixed android service revoke and restart.
- Fixed github release update checker.
- Fixed translator script. [PR#108](https://github.com/hiddify/hiddify-next/pull/108) by [Hirad Rasoolinejad](https://github.com/Hiiirad)
- Fixed localization mistakes in Chinese. [PR#113](https://github.com/hiddify/hiddify-next/pull/113) and [PR#123](https://github.com/hiddify/hiddify-next/pull/123) by [Nyar233](https://github.com/Nyar233)
- Fixed localization mistakes in Chinese Readme. [PR#137](https://github.com/hiddify/hiddify-next/pull/137) by [wldjdjsks](https://github.com/huajizhige)
- Fixed localization mistakes in Chinese. [PR#138](https://github.com/hiddify/hiddify-next/pull/138) and [PR#165](https://github.com/hiddify/hiddify-next/pull/165) by [wldjdjsks](https://github.com/huajizhige)
- Fixed localization mistakes in Russian. [PR#155](https://github.com/hiddify/hiddify-next/pull/155), [PR#162](https://github.com/hiddify/hiddify-next/pull/162) and [PR#169](https://github.com/hiddify/hiddify-next/pull/169) by [solokot](https://github.com/solokot)
- Fixed linux build libs command. [PR#161](https://github.com/hiddify/hiddify-next/pull/161) by [Aloxaf](https://github.com/Aloxaf)
- Fixed localization mistakes in Russian. [PR#164](https://github.com/hiddify/hiddify-next/pull/164) and [PR#168](https://github.com/hiddify/hiddify-next/pull/168) by [jomertix](https://github.com/jomertix)
- Fixed localization mistakes in Chinese. [PR#179](https://github.com/hiddify/hiddify-next/pull/179) by [betaxab](https://github.com/betaxab)
- Fixed localization mistakes in Chinese Readme. [PR#172](https://github.com/hiddify/hiddify-next/pull/172) by [Locas](https://github.com/Locas56227)

## [0.10.0] - 2023-10-27

### New Features and Improvements

- Added Basic region-based routing rules
  - Based on your selected region (Iran, China or Russia), local ip and domains are bypassed.
- Redesigned Logs page
  - Now you're able to pause stream and clear logs. Also logs are delivered more consistently, with less resource consumption.
- Added tag of selected outbound of selectors to proxies page
  - Selected outbound tag of selectors like URLTests are now shown in other selectors as well.
- Added color to delay number in proxies page
- Memory limit option
  - Limit sing-box core memory usage.
- Revamped theme preferences settings
- Added initial iOS implementation. [PR#98](https://github.com/hiddify/hiddify-next/pull/98) by [GFWFighter](https://github.com/GFWFighter)
- Added Russian region
- Added Terms and Conditions and Privacy policy to about page

### Bug Fixes

- Removed reconnection on auto profile updates
- Fixed filtering logs by level
- Fixed localization mistakes in Russian. [PR#95](https://github.com/hiddify/hiddify-next/pull/95) by [solokot](https://github.com/solokot)
- Fixed localization mistakes in Russian. [PR#74](https://github.com/hiddify/hiddify-next/pull/74) by [Elshad Guseynov](https://github.com/lifeindarkside)

[0.16.0.dev]: https://github.com/hiddify/hiddify-next/releases/tag/v0.16.0.dev
[0.14.1.dev]: https://github.com/hiddify/hiddify-next/releases/tag/v0.14.1.dev
[0.14.0.dev]: https://github.com/hiddify/hiddify-next/releases/tag/v0.14.0.dev
[0.13.6]: https://github.com/hiddify/hiddify-next/releases/tag/v0.13.6
[0.13.5.dev]: https://github.com/hiddify/hiddify-next/releases/tag/v0.13.5.dev
[0.13.4.dev]: https://github.com/hiddify/hiddify-next/releases/tag/v0.13.4.dev
[0.13.3.dev]: https://github.com/hiddify/hiddify-next/releases/tag/v0.13.3.dev
[0.13.2.dev]: https://github.com/hiddify/hiddify-next/releases/tag/v0.13.2.dev
[0.13.1.dev]: https://github.com/hiddify/hiddify-next/releases/tag/v0.13.1.dev
[0.13.0.dev]: https://github.com/hiddify/hiddify-next/releases/tag/v0.13.0.dev
[0.12.3]: https://github.com/hiddify/hiddify-next/releases/tag/v0.12.3
[0.12.2]: https://github.com/hiddify/hiddify-next/releases/tag/v0.12.2
[0.12.1]: https://github.com/hiddify/hiddify-next/releases/tag/v0.12.1
[0.12.0]: https://github.com/hiddify/hiddify-next/releases/tag/v0.12.0
[0.11.1]: https://github.com/hiddify/hiddify-next/releases/tag/v0.11.1
[0.11.0]: https://github.com/hiddify/hiddify-next/releases/tag/v0.11.0
[0.10.0]: https://github.com/hiddify/hiddify-next/releases/tag/v0.10.0
