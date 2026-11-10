# Changelog

## 穿云

穿云各版本的改动（新在前）。完整说明见 [Releases](https://github.com/yywgov/muse-vpn/releases)。

### 1.20.0 - 2026-11-10

- 首页方向 A（连接卡 + 地图融合）：单独的路由卡并入连接卡——地图做连接卡的底（状态与节点行之间，`MuseHeroMap`），卡片在所有状态都是中性底色（`mt.card`），颜色只留给地图上节点所在国家、▶ 与状态灯
  - 未连接：整幅世界（中央经线东经 150°，中国、日本、美国本土连阿拉斯加、欧洲都不被切）、全灰、无弧线
  - 已连接：按本机 + 节点所在国家 + 整条大圆弧自动取景（`museFitView`，经度跨度 ≥ 64°），只有节点所在国家的点阵变已连接色（对卡片底色 ≥ 3.6:1，比底图点大 1.18 倍且不小于格距 34%，美国、日本、德国都清楚）
  - 国家归属查表 `route_countries.dart`（Natural Earth 1:110m Admin 0 – Countries，公有领域；生成脚本 `tool/world_dots/gen_dot_countries.py`，源数据不进仓库）；香港、新加坡、澳门等 110m 底图上没有独立国土的地区回退为高亮出口城市 3.5° 内的陆地点
  - 换节点 / 连上 / 断开：取景一次性平移缩放 280 ms（`MuseRouteMotion.view`，过渡中直接画点阵、停下后换回预渲染图），国家高亮淡入淡出 250 ms；精简档 ×0.6，关闭档与系统「移除动画」直接到位；无常驻 / 循环动画
  - 原地图下「上海 → 东京 · 实测 · 86 ms」说明行与节点行重复，去掉；分类图例与一句话路由保留，在地图下方（有分类数据时才出现）；经典首页的连接卡不带地图
  - 连接钮改为 56 圆形中性钮（▶ 已连接色、❚❚ 正文色），1.18 的圆 ↔ 圆角方形形变随实心主色按钮一起去掉；按压反馈保留
  - 字阶：状态 28 / 600、时长 15 等宽、节点名 16 / 600、「地区 · 协议」13、延迟彩色小圆点 + 15 等宽数字 +「ms」13；只用内置字体真有的字重
- 下方卡片同步方向 A：圆角 20、内边距 20、标题 13 次要色、数字 26 / 600 等宽与单位 14 次要色分开（不换行空格，`museSplitValue` / `museTileValue`）；卡片高度随系统字号长高（1.3×、2.0× 不溢出）
- 卡片标题行：标题短（如「网速」）时右侧小字用满剩余宽度，800 / 1280 电脑版「↑ 1.0 KB/s」不再被截成「1.0 K…」
- 顶部「订阅名 · N 个节点」改 15 / 400；底部导航与卡片对齐（边距 16、圆角 20、选中块 16，标签 600 / 400）
- 电脑版：800 起双栏、880 图标栏双栏、≥ 1280 节点栏，左栏都是同一张融合连接卡（内边距 24，地图高 = 卡宽 / 2.6，148–220）
- 令牌集中在 `lib/features/muse/widget/muse_tokens_home.dart`（`MuseHomeA`：圆角 20 / 12 / 8、4 / 8 间距、56 圆钮、数值与地图取值）
- 关于 › 开源许可与致谢加「世界地图数据 Natural Earth（公有领域）」
- 测试：v1200_home_test（国家查表与回退、取景、取景过渡 ≤ 300 ms 且结束无帧、减少动效直接到位、连接卡结构、中性卡与 56 圆钮、1.3× / 2.0× 浅深色不溢出、电脑版 800 / 880 / 1280、数字与单位、令牌、原型开关已去掉）；改过的旧断言见下列文件（均注明 1.20.0）

### 1.19.3 - 2026-11-10

- 修复：电脑 / 手机重启或异常退出后偶尔不会自动恢复连接。根因：启动恢复连接时重新订阅日志 / 状态流（取消旧流 → RST_STREAM），内核恰好在写该流的响应 HEADERS；http2 2.3.1 客户端把「已取消流上的 HEADERS」当作连接级 PROTOCOL_ERROR，整条 gRPC 连接被关闭，同一连接上的 ChangeHiddifySettings 失败 → started_by_user 被置 false → 下次启动不再自动连接
  - `pubspec.yaml` `dependency_overrides: http2: ^3.1.0`（dart-lang/http #1799 已修；grpc 至 5.2.0 仍锁 ^2.3.1，待 grpc 支持后移除）
  - 加固：启动恢复连接遇到一次连接 / gRPC 传输类错误时不立刻放弃——先释放内核，等 400 ms（单次，无轮询、无常驻计时器），重建 gRPC 通道并确认内核应答后重试一次；仍失败、内核不应答或错误不是传输类（如配置无效）才判失败并按原逻辑处理（提示、started_by_user=false）。每条失败路径都释放内核；释放记为应用自己的停止，连接守护不会误判。用户手动连接 / 断开的路径不变（`lib/features/muse/logic/startup_restore.dart`，`CoreInterface.resetChannel`、`HiddifyCoreService.reopenChannel`、`ConnectionRepository.reopenCoreChannel`）
- 测试：v1193_grpc_cancel_test（真实 http2 回环复现：2.3.1 红、3.1.0 绿）、v1193_restore_retry_test（一次瞬断后恢复成功、连续两次失败才置 false、内核不应答不重试、配置错误不重试、用户断开 / 手动连接不重试）

### 1.19.2 - 2026-11-09

- 按实机反馈一次改完：
  - 窄窗口：`MuseBreak.laptop` 840 → 1080（1080 宽以内自动图标栏），图标栏 80 → 64，展开侧栏 200 → 184；电脑版布局窗口 900 → 800 起，首页双栏改按**内容区**宽度 ≥ 700 判断（扣掉侧栏），左栏 58% → 56%、栏距 16 → 12
  - 首页去掉大标题「穿云」（手机与电脑；侧栏品牌行、标题栏保留），顶部统一为 48 高工具行「订阅名 · N 个节点」+ 编辑首页（电脑窗口另有测速，手机不加）
  - 路由地图铺满卡片宽度：经度始终 360°（中央经线东经 110° 不变），宽高比比 2.5 扁时按纬度取景（中心北纬 12°，跨度不小于 100°），手机仍是整幅；电脑上限 260 → 240
  - 终点城市名：修复用未展开经度定位（洛杉矶被画到地图左外侧只露出「矶」）；标签测量后整块夹在地图内，靠边向内翻、靠上缘放到点下方，单行不换行；越过东西边缘的弧线从另一侧接回
  - 已连接色 `museLinkedColor`：主色，对卡片底色不足 3:1 时向前景色混合（终点文字 4.5:1）；已连接时起点、终点、弧线同色，未连接 / 连接中起点为中性色；切换 200ms 一次性过渡（精简 ×0.6，关闭档直接终态）
  - 删掉地图下「有流量后显示各类流量走哪里」（无分类数据时不显示任何提示）
  - 内置中文字体：思源黑体 / Noto Sans SC（SIL OFL 1.1）子集化为 MuseHei，400 + 600，GB2312 6763 字 + lib/ 全部用字（`tool/fonts/subset_cjk.py`，源字体不进仓库），两端默认字族；Windows 以 Emoji 为后备；关于 › 开源致谢加思源黑体
- 打磨（第 2 段）：数字字体 Inter 里的汉字回退到内置思源黑体（节点名「东京 02」不再半边系统字体，`MuseFont.fallback`，Windows 再回退 Emoji）；选中节点卡的协议标签用卡片正文色（深色主题原约 1.5:1）；电脑窗口页面标题行 64 → 56（`MuseDesk.titleBarHeight`）；关于页致谢副标题改为全中文
- 测试：v1192_test；改过的旧断言见 v1190_home、v1191_desktop（A1 / A4 / A6 / A7）、v160_c1、v160_c2、v1180（P7 中文回退）（均注明 1.19.2）

### 1.19.1 - 2026-11-09

- 动效审查 10 条（第 1 段）：连接按钮按压反馈（0.96 / 100ms，松开 160ms）；返回改快起曲线；页面进场 380 → 300ms（`MuseMotion.page`）；主题揭开改快起曲线；`MuseRoll` 510 → 300ms；切节点终点 700 → 450ms；分类线与终点在弧线最后 15% 淡入；光点 2 趟 → 1 趟；精简档骨架静态；底部 Tab 切换 220 → 160ms、横移 6% → 3%
- 电脑版界面 A1–A10（第 2 段，令牌 `MuseDesk`）：
  - A1 路由图限高（≤ 260 且 ≤ 窗口高 32%，不低于 160；手机不限）；A2 点阵浅色 32% / 深色 24%，点径按逻辑像素算、最小 1.1，小图隔点取不糊成一片；A3 地图上画本机 / 出口城市名（13 号 w600，卡片底色描边，出口随弧线尾段淡入，未连接不画），图注 13 号并带当前节点延迟
  - A4 首页按**窗口**宽度分栏：≥ 900 双栏（左 58% 连接卡 + 路由图，右卡片），≥ 1280 再加 340 宽节点栏；< 900 与 1.19.0 相同
  - A5 桌面连接卡：状态、计时、模式与 56 的连接按钮同一行居中；节点行放大（节点名 17 / w600、地区 13、延迟 20）
  - A6 桌面首页去掉重复的大标题「穿云」，换成 48 高工具行「订阅名 · N 个节点」+ 测速 + 编辑首页（≥ 1280 时测速在节点栏）
  - A7 侧栏 220 → 200，48 高品牌行（应用图标 + 穿云 + 折叠按钮），选中项圆角 6 + 主色 10% 底 + 左侧 3×16 指示条，悬停 6% / 按下 9%，键盘焦点 2px 描边，侧栏底色与 hairline 分隔；`tool/smoke/app_smoke.ps1` 点击侧栏的坐标同步改为 32 + 48 + 52×2 + 26（检查不变）
  - A8 标题栏：应用图标 + 13 号标题；按钮用 Segoe Fluent Icons 字形（Win10 回退 Segoe MDL2 Assets，两者都没有时用原 Material 图标）；窗口失焦时标题与按钮变灰；底色与侧栏一致
  - A9 宽窗口页面标题统一 24 / w600，单栏内容宽 760 → 840，一级页面标题与卡片左右对齐
  - A10 主题统一 hoverColor / focusColor；可点的 MuseCard 悬停底色提高一级、键盘焦点 2px 主色描边；全部靠指针 / 焦点事件，无计时器、无常驻动画
- 测试：v1191_test、v1191_desktop_test；v160_c8（冒烟脚本侧栏坐标）、v1190_home（图注带延迟）随设计变更更新断言

### 1.19.0 - 2026-11-09

- P1 路由弧线图新首页：点阵世界底图（Natural Earth 公有领域数据离线生成，2,892 B，预渲染一次）+ 本机（上海）到出口城市的大圆弧；连接成功时弧线 1100ms 画出、光点 2 趟后停，切节点终点 700ms 滑动；出口位置标「实测 / 按名称 / 未知」；外观 › 首页样式可切回经典首页（即 1.18 首页，设置 `muse_home_style`，加入设置搜索与同步）
- 分类线：AI / 视频 / 开发 / 直连，线宽随本次连接各类流量占比；数据只在连接页的帧与统计页打开时那次读取顺带累加，无新轮询/计时器；无数据只画主弧线
- P4 一句话路由：路由卡下方「AI 走 东京 · 视频 走 香港 · 其余直连」（各类取流量最多的出站节点，节点名换成城市名），无流量时显示简短提示；首页网速柱按路由颜色堆叠（新首页且有分类数据时；否则退回原单色折线），只随已有网速读数重画
- P5 主题：外观 › 主题「默认 / 浅色 / 纯黑 / 终端绿 / 暖纸」（设置 `muse_theme_style`，加入设置搜索与同步）；默认 = 按原「深浅色」（含纯黑开关、B9 跟随系统纯黑，均保留）；纯黑复用原纯黑配色；终端绿、暖纸为令牌色板（`muse_tokens_theme.dart`），正文与次要文字对各层表面 ≥ 4.5:1；切换时圆形揭开（`MuseThemeReveal`：截旧画面，从点按位置挖圆扩散，标准 400ms；精简 = 旧画面 200ms 淡出；关闭 = 直接切换；结束即释放）
- 修复测试：v1102 外观「在最近任务中隐藏」行被新增设置行挤到屏幕外，先滚动到可见再操作
- 测试：v1190_test、v1190_home_test、v1190_theme_test

### 1.18.0 - 2026-11-09

- P0 动效令牌与页面转场：`widget/muse_motion.dart` 统一令牌——主曲线 cubic(.32,.86,.22,1)、进场 380ms、退场 200ms（emphasized accelerate）、反馈 150ms、到达 450ms，无回弹弹簧（350ms）与「到达」轻回弹弹簧（400ms / bounce 0.15，`MuseSpringCurve` 供隐式动画使用）；修复页面转场线性（原 150/100ms 无曲线），原有 `MuseMotion.curve` / `tabCurve` 改用主曲线
- P6 动效三档：外观 › 动效（跟随系统 / 标准 / 精简 / 关闭，设置 `muse_motion_level`）；跟随系统 = 系统「移除动画」→ 关闭、Android 省电模式 → 精简（Kotlin `ChuanyunPowerWatch` 只在订阅时动态注册 `ACTION_POWER_SAVE_MODE_CHANGED`，不轮询）；精简 = 时长 ×0.6、无回弹、无扫光；关闭 = 直接终态并同时设置 `MediaQuery.disableAnimations`；系统「移除动画」始终优先；修复订阅更新转圈不尊重「移除动画」
- P2 连接按钮形变：同一形状圆 → 圆角方形（半径 32 → 18，连接时到达弹簧、断开时无回弹），图标独立交叉淡入 + 0.9→1 缩放
- P3 数字遮罩滚动（`MuseRoll`）：首页节点名与延迟——旧字 260ms 上滑出、新字延迟 90ms 后 420ms 滑入；实时速率等每秒数值不动画、用等宽数字；等待态文字扫光（`MuseSweep`，1100ms 一趟）代替转圈：连接中标题、切换节点时的节点名、测速按钮、订阅更新图标；只在标准档、可见时运行，各有超时；首页连接中的循环光带移除
- P7 字体：内置 Inter（SIL OFL 1.1）静态 400/500/600/700，子集化为拉丁 + 数字 + 常用符号，共约 190 KB，family `MuseSans`；用于首页大号数字、节点名与延迟；中文逐字回退系统字体；许可随附 `assets/fonts/OFL-Inter.txt`，关于 › 开源许可与致谢、THIRD_PARTY_NOTICES.md 致谢
- 测试：v1180_test；文案白名单加 Inter、SIL

### 1.17.1 - 2026-11-08

- 节点页去掉「最近」一行（顶部最近用过的节点芯片，用户反馈没意义）；「最近使用」数据仍照常记录，Windows 托盘 R18 与「手动选择」继续使用
- 测试：v160_nodes_test 改为断言节点页不再显示「最近」行；v1171_test

### 1.17.0 - 2026-11-08

- B12 应用内更新校验与重试：下载后用 Release 附带的 `.sha256` 文件校验（与 GitHub digest 都有时须一致，否则不安装）；失败保留已下载分段，「重试」按 Range 断点续传，校验失败删除后「重新下载」；新增「正在校验安装包…」与中文失败说明；只清理其他版本的旧下载
- B13 Windows 全局快捷键：注册前用 user32 RegisterHotKey 试探，被其他程序占用的组合不注册并在「快捷键」页标出；默认不绑定（等于关闭），总开关可停用
- R18 Windows 托盘切节点：节点 ▸ 收藏 / 最近使用（当前代理组内、按用户顺序、各最多 10 个，菜单重建时读已存列表，不测速），延迟区分「超时 / 未测」；托盘切换记入最近使用
- R12 Windows 商店应用回环豁免：设置 › 网络「允许商店应用走代理」，点按并确认后经 UAC 用 CheckNetIsolation 为未豁免的 AppContainer 开通回环，绝不自动执行；可只撤销穿云开通的
- R19 Windows 隐藏到托盘时释放界面：隐藏期间页面移出组件树、清图片缓存，显示（含二次启动原生恢复）时重建
- 修复：调试/e2e 构建首页「上次异常」riverpod `_didChangeDependency` 断言——内核启动 bump coreRestartSignalProvider 后，ConnectionNotifier 在 await 之后 `ref.read`；改经 `ref.container` 读取（release 构建不受影响）；e2e 读本机崩溃记录，出现 riverpod 断言即失败
- 测试：v1170_test

### 1.16.0 - 2026-11-08

- B7 按天/按应用流量图：统计页新增「按应用流量」（今天/7 天/30 天，前 8 个应用）；数据只存本机 muse_app_traffic、保留 30 天、不同步不备份；只在打开统计页（读一次 /connections）与连接页开着时（复用每秒帧，30 帧及离开时写入）累计，连接/断开清基线，无后台采样与轮询（logic/app_traffic.dart、data/app_traffic_recorder.dart）；按天图沿用原有
- B8 敏感页禁截屏与后台模糊：节点详情、订阅详情、二维码、导出配置打开期间窗口加 FLAG_SECURE（最近任务缩略图空白），全部关闭即清除；外观「敏感页禁止截屏」默认开、可关（data/secure_screen.dart，ChuanyunHandler set_secure_screen）
- B9 纯黑深色：跟随系统也可开纯黑（系统深色时生效，设置 muse_pure_black_follow）；深色下原有纯黑不变
- B10 新用户一步引导：全新安装首次打开弹一次（粘贴/扫码添加订阅 → 添加后问「现在连接？」），可跳过，只出现一次；老用户升级（打开过旧版或已有订阅）不弹（home/first_guide.dart）
- B11 读屏标签：节点卡片「当前节点，节点 名称，延迟」+ 点按提示，开关行合并朗读，穿云页面纯图标按钮全部带中文提示（测试扫描）
- R25 小组件常用节点：小组件下方显示收藏前 3 个节点，点按经 chuanyun://connect?node= 切换并连接；变化时才推送，无计时器；入口只用应用 Context（onNodeFavs）
- R17 国内应用识别：分应用代理（以下 App 不走代理）⋯「选中常见国内应用」，内置包名清单本机比对，不联网（logic/domestic_apps.dart）
- 测试：v1160_test

### 1.15.0 - 2026-11-08

- R24 连接详情「为什么走这条」：把内核报告的规则（标准内核 `rule_set=[…] => route(…)`，兼容内核 `RuleSet(…)` / `Match`）翻成中文，显示命中规则 → 出站 → 实际节点（logic/route_why.dart）
- R16 连接列表显示发起的应用：内核已报告进程时（Android 包名 / Windows 程序路径）显示图标与名称，详情加「应用」；名称表在连接页打开时读一次，图标按需读、缩小解码、最多缓存 48 个，离开页面释放（connections/conn_app.dart）
- R22 链式代理（前置节点）：节点详情「通过另一个节点连接」，开启前提示会变慢；存进订阅覆写 chains，连接时在运行副本给节点加标准 sing-box `detour`；前置节点不在订阅里或成环时不加；仅标准内核
- R13 DNS 清缓存：活动 › DNS「清空 DNS 缓存」，点按时调用 `POST /cache/dns/flush`（两个内核都有，未改内核）
- R20 DNS 泄漏检测：诊断里点「开始检测」才经本机代理访问一次 edns.ip-api.com 随机子域名，解析服务器在中国大陆时提示可能泄漏；失败中文提示（logic/dns_leak.dart）
- R23 按 Wi‑Fi 切换模式：指定 Wi‑Fi 下自动切到规则/全局，离开恢复，手动修改优先；Android 新增 ChuanyunWifiWatch（EventChannel，仅列表非空时注册 Wi‑Fi 回调），两平台回到穿云时检查一次，无轮询；读 Wi‑Fi 名称前先说明再请求「位置信息」，拒绝时可手动输入
- 本批未做：B6（规则集只在打开应用且过期时更新）——更新间隔与后台定时器在内核里，需另发内核版本，顺延
- 测试：v1150_test

### 1.14.0 - 2026-11-08

- R15 订阅更新出错不覆盖：下载失败与内核检查失败本来就不写入；新增在交给内核前拦下空内容、网页（链接失效/需登录）、没有节点、节点数骤减（原 ≥10 个且剩不到 30%）——保留上次成功的节点并给出中文原因；保存中途失败自动放回上次成功的文件（<profile>.prev）；手动更新遇到骤减可「仍然更新」；后台批量更新的提示与系统通知带上原因
- R21 手动添加/编辑节点：节点 ⋯「手动添加节点」表单（VLESS / VMess / Trojan / Shadowsocks / Hysteria2，TLS、SNI、跳过证书验证、WebSocket）生成分享链接存入当前订阅的覆写；订阅节点详情「编辑节点」改地址/端口/SNI/UUID/密码，只存与订阅不同的字段（按节点名，覆写 edits），连接时叠加到内核读取的运行副本（sing-box JSON 形式），订阅文件本身不改，更新后保留；「恢复订阅原值」；覆写列表显示「修改 N」
- R11 相册图片扫码：扫码页「从相册选择」，系统选图器（不申请存储权限、不压缩），用已有扫码库直接解码文件，不新增依赖
- B4 节点筛选「只看收藏」（收藏、置顶/收藏排序、搜索、按地区折叠为已有功能，加回归测试）
- B5 节点/订阅二维码分享前确认「含有敏感信息」，二维码下保留提醒
- R14 订阅自定义请求头：订阅 ⋯「请求头」，按订阅保存在本机（muse_sub_headers），只随该订阅下载发送；不同步不备份；日志/诊断中 Authorization、Cookie、X-* 头打码
- 测试：v1140_test

### 1.13.0 - 2026-11-08

- 本地崩溃自检：Kotlin 各进程（主进程、兼容内核进程）未捕获异常与服务启动失败（标准/兼容内核 stopAndAlert）写入 filesDir/diagnostics/crash.log（128 KB 轮转一份，仅本机）；Dart 未捕获异常照旧进崩溃记录并标记未读；首页「上次异常」显示时间与一句原因，「复制日志」复制服务与界面两份记录（已脱敏），「知道了」关闭
- 连不上一键诊断（首页连接失败后、活动 › 诊断未连接时）：点「开始诊断」才检查网络（直连百度）、DNS、当前节点服务器 TCP 可达（UDP 协议跳过）、17079 后台内核与本地代理端口占用、其他 VPN（ConnectivityManager TRANSPORT_VPN）；中文结论 + 释放内核 / 打开 VPN 设置 / 切换节点 / 重新检测
- 安全模式：连续 2 次启动失败（服务与界面 5 秒内重复上报只算一次；内核真正运行才清零）进入；停用桌面小组件更新（只读 Application.onCreate 时缓存的标志，服务构造期不碰 Context）与自定义规则（分流规则、远程规则集、从连接加的规则、屏蔽域名、订阅覆写）；首页「退出安全模式」
- 被其他 VPN 顶掉（onRevoke，标准/兼容内核）：通知「穿云已被其他 VPN 断开」+ 首页提示，不自动重连（startedByUser 清除）
- e2e：新增小组件（更新 + 点按 TOGGLE）、快捷开关磁贴（add-tile / click-tile）、开机自启（debug 包 e2e_boot 钩子走 BootReceiver.autoStart）三条启动路径与首页按钮「连→断→再连」
- 停止有上限、不占主线程：e2e #16 两次应用内断开各卡 120 秒——BoxService 在主线程（Flutter 3.29 起也是 Dart 界面线程）同步调用 Mobile.close(4)，内核关闭用了 120 秒（sing-box 各组件 10 秒超时累加），期间界面与平台通道全部停住；穿云进程始终在前台、未被系统冻结（logcat 只冻结了其他应用）。现在内核在独立线程关闭，最多等 10 秒（CoreStop），超时即报已停止、关闭本进程绑定 127.0.0.1:17079 的套接字释放端口，迟到的关闭在后台完成；再次连接前先等它结束（否则会拆掉新连接的 gRPC 服务）；兼容内核同样 10 秒上限；Dart 断开的 gRPC 停止调用 10 秒期限、等待端口关闭改为 12 秒；e2e 新增「任何一次停止不得超过 15 秒」检查并收集应用日志
- 测试：v1130_test；文案白名单加入 VPN

### 1.12.1 - 2026-11-07

- 修复 Android「意外失败 / createService - null」连不上：BoxService 在 Mobile.setup 之后启动失败（stopAndAlert）时没有关闭后台内核（mode 4，127.0.0.1:17079），状态却回到已停止并注销了关闭广播接收器；之后应用内连接先 stop() 等 17079 关闭，等不到就报 createService（无消息 → null）。现在 stopAndAlert 关闭后台内核（与兼容内核一致）并 stopSelf；应用内「停止」在服务已停止时直接关闭本进程残留的后台内核；Dart 再请求一次释放后才报错，并给出中文原因
- 连接失败提示：中文说明 +（alert 名）+ 原因，异常无 message 时显示异常类型，不再显示「null」

### 1.12.0 - 2026-11-07

- 解锁检测：首页「服务状态」只在点按卡片或「刷新」时检测（不再出现时自动检测，无轮询）；Netflix（授权片 / 自制剧两次判断）、YouTube Premium、Disney+、ChatGPT / Claude（cdn-cgi/trace 地区 + 不支持地区表）、TikTok、Prime Video 显示所在地区与「仅自制剧 / 不支持 / 受限」，其他服务仍只看能否打开；单项 10 秒、整次 30 秒上限，结果缓存 10 分钟
- 测速失败原因：内核（patch 0014）在测速结果里带出原因（拒绝 / 解析 / 握手 / 超时），节点卡片显示短词，节点详情给建议；测速流程不变
- 连接一键加规则：「活动 › 连接」详情里设为直连 / 走代理 / 指定节点，可选「仅本次」（断开即失效），规则排在局域网与屏蔽之后、其他规则之前，热重载生效，可撤销；规则页可管理
- 出口 IP 详情：点开才查（ip-api / ipwho 免费接口回退），运营商、ASN、城市、IP 类型，按 IP 缓存 1 天，提示出口是否变化
- 自动最快限定地区：默认全部；选地区后内核 urltest 只在匹配的节点里挑，匹配不到时仍用全部
- 订阅更新后自动测新增节点：仅已连接且前台；后台只记下
- Android：启动器快捷方式「切换规则/全局」（chuanyun://mode）「扫码添加」（chuanyun://scan）「测速」（chuanyun://speedtest），打开穿云后走与界面按钮相同的代码；快捷开关副标题显示节点 · 延迟
- 剪贴板：回前台只调用 hasStrings（不读内容），打开「添加」时才读取识别
- Windows：本地端口被占用时本次自动换空闲端口并提示一次；系统代理绕过列表（默认本机、局域网网段、*.local、<local>）
- 中文化：「Geo 数据库」→「地理规则库」，内核启动失败等提示改中文；新增文案扫描测试，界面字符串出现非白名单英文即失败
- 测试：v1120_test；v1104 服务状态卡片测试改为点按才检测

### 1.11.1 - 2026-11-06

- 修复 1.11.0 启动闪退（Android 一打开就退出）：根因是桌面小组件跟随连接状态的代码——BoxService / CompatService 在所属 Service 的字段初始化时构造（此时 Service 还没有 base context），1.11.0 在构造函数里 `status.observeForever { ChuanyunWidget.onStatus(service, it) }`，LiveData 注册后立即回调当前状态，`service.getSharedPreferences` 落到 base 为 null 的 ContextWrapper 上抛 NullPointerException；MainActivity 每次启动都 bindService(BIND_AUTO_CREATE) 创建 VPNService（主进程），于是每次打开即崩。修复：小组件只用应用 Context（Application.attachBaseContext 时已就绪，早于任何组件创建），onStatus / onNode 不再接收 Service / Activity 的 Context，且整体 try/catch(Throwable)，小组件出任何问题都不会拖垮服务或应用。功能不回退：内核仍为 5.0.0-muse.23，小组件、隐藏图标恢复等 1.11.0 改动全部保留
- 测试：v1111_test（服务构造期不得把 Service 交给小组件、小组件入口全部兜底且只用应用 Context、所有在 Service 字段初始化时构造的对象的 init 块不得调用 Context 方法）

### 1.11.0 - 2026-11-06

- 节点页 A 双列卡片：顶部「手动选择 / 自动最快 xx / 负载均衡」分段（取代原来的两行组卡），节点为双列小卡（国旗 + 地区小字、节点名粗体、协议小标签、右下延迟数字按快慢着色 + 小号 ms），选中卡主色浅底 + 主色描边 + 右上勾；正在被自动最快 / 负载均衡使用的节点只描边；标题下一行「订阅名 · N 个节点」，右侧搜索 + 测速胶囊按钮；宽窗口自动多列；「⋯ › 布局」去掉（节点页固定为卡片，首页选节点面板与 Windows 侧栏仍为列表）
- 节点失效自动切换：独立开关（节点 › ⋯ › 节点设置，默认开，原属「智能保持连接」）；当前手选节点连续两次测速失败时，换到同地区最快的可用节点（没有则自动最快，再没有则全组最快），弹一条提示，原节点连续两次测通后换回；只读已有测速结果，不加定时器或额外测速
- Android 桌面小组件：一键连接 / 断开（走 com.chuanyun.app.action.TOGGLE，与快捷开关同一路径），显示连接状态、当前节点与延迟；updatePeriodMillis=0，只在服务状态变化（BoxService / CompatService 各自观察）或穿云告知节点 / 延迟变化时重绘
- APK 瘦身：标准内核 TAGS 去掉 with_embedded_tor、with_openvpn、with_openconnect（新内核版本，见 dependencies.properties），其余构建标签与行为不变
- 首页：当前节点行与节点卡同一风格（地区 · 协议小字、节点名粗体、延迟着色 + 小号 ms）；「内网 IP」卡默认隐藏（迁移 3→4 对已保存的首页布局也隐藏一次）；网速卡在未连接或最近 3 个采样都低于 1 KB/s 时显示「今日流量」
- 订阅页：剩余流量与到期各一条进度条（标签 + 剩余百分比 / 天数，≤10% 或 ≤3 天变红）；提醒改为剩余 ≤10%（用完再提醒一次）或 ≤3 天到期时各提醒一次（每个计费周期），不再在用到 80% 时提醒
- 冷启动：内置规则文件每个版本只复制一次（偏好 muse_rule_sets_installed 记录 版本+构建号，文件都在就跳过），不再每次启动从安装包读出约 1.6 MB 逐个比较大小；Android 高刷新率请求挪到首帧之后；日志记录「first frame at N ms」便于真机对比
- 设置精简（位置变化）：
  - 自动连接：只留「打开即连接」（Android，原名「自动运行」）与「开机自启」（+「开机自启时静默」，Windows）；智能保持连接、按需运行、每天定时连接 / 断开、静默启动（Windows）收进页内「更多」
  - 外观：去掉「配色风格」（固定为忠实）和「文字缩放」（跟随系统字号）；已保存的值保留但不再读取；Windows 的穿云标题栏、快捷键、窗口置顶收进「窗口 › 高级」
  - 网络：去掉「连接质量提醒」（原每分钟测一次）；负载均衡策略、IPv6、Fake-IP、切换节点时关闭旧连接收进「高级」，TLS 分片与屏蔽 QUIC 仍在外面
  - 节点设置：订阅 UA、重复判断收进「高级」；新增「节点失效自动切换」
  - 去掉：隐藏桌面图标（已隐藏的图标在升级后自动恢复一次）、统计「导出 CSV」
  - 「备份与同步」整页去掉（含 WebDAV 同步、局域网同步、自动备份、每周本地快照）；「设置 › 关于」底部新增「导出配置 / 导入配置」，文件格式不变，旧备份（含加密的）照常导入，恢复预览（仅订阅 / 仅设置、合并 / 覆盖）不变，订阅只增不删
  - 设置首页 7 项：外观、自动连接、分应用代理、网络、活动、内核与资源、关于；设置搜索：删掉的设置不再出现，旧名称（备份与同步、自动运行、订阅 UA、窗口置顶等）跳到新位置并自动展开「更多 / 高级」
- 测试：v1110_test（失效切换目标与提示、设置首页与搜索、迁移、各页「更多 / 高级」、关于页导出导入、节点卡片四种屏幕深浅色与大字号、小组件、首页今日流量、订阅进度条与提醒、冷启动测量、版本说明）；内核 TestMuseSlimStandardCoreTags

### 1.10.4 - 2026-11-06

- 测速（标准内核 5.0.0-muse.22，patch 0013）：每个节点只开一条连接——连接 + TLS + 第一次请求之后，在同一条保持连接上再发 3 次 HEAD，取这 3 次往返的中位数作为延迟（不含握手，与原「真实延迟」语义一致，连接从 4 条减到 1 条）；第一次往返出来就先显示，后两次修正。服务器不保持连接时最多另开一条，仍取不到往返就用首次请求的时间，不再因第二次请求失败误判超时
- 超时分层：首轮建立连接限时 5 秒（全超时的 5/8，3–5 秒），2.5 秒仍无回应时再并行试一条连接；连接被拒、域名不存在立刻判定，不重测；真超时的节点 1 秒后插队重测（3 条连接并行、满 8 秒），仍不通才显示「超时」
- 自适应并发：从设置值（默认 8）起步，一轮无超时就 +4，最多 3 倍（24）；最近结果里出现 3 次超时就退回 8；切换网络回到 8。全局同时打开的测速连接不超过 24 条（1.10.3 的 8 × 3），预检/重测的额外连接只在额度内开
- 去重与复用：配置完全相同（只名字不同）的节点只测一次、结果共享（热重载后停用共享）；自动检测（亮屏、依赖变化）对 60 秒内测过的节点复用结果，手动「测速」、重测、失效节点始终重测
- 测速地址仍为 generate_204，HEAD + keep-alive
- 兼容内核（同一提交）：首轮 5 秒、被拒立即判定、超时节点 1 秒后单独重测（满超时，不再等整批结束）、同样的自适应并发（8 → 24）
- 模拟对比（拥塞家庭宽带模型，40 组随机节点平均）：50 个节点 49.1 → 26.2 秒，100 个 85.2 → 45.0 秒，200 个 163.8 → 84.8 秒（约 −47%）；正常节点首次出数 15.8 → 8.5 / 30.7 → 15.2 / 60.3 → 28.4 秒；误报超时 54 / 104 / 180 → 0 / 0 / 2；同时打开的连接峰值都是 24
- 首页「服务状态」一直「检测中」修复：根因是切换节点（自动最快 / 负载均衡自动换节点，或节点列表刷新时短暂为空）会清空结果，而卡片只在「连接状态变化」时才发起检测，结果被清空后再也不会重测；检测中途被清空也会把这次检测丢掉。现在：换节点只让缓存过期、保留已有结果；结果为空且已连接时卡片自动发起检测；每项都有终态（可用 + 耗时 / 超时 / 不可用 / 受限），单项 5 秒、整次最长 30 秒，没回应的记为「超时」；点卡片重新检测；不加轮询、不加常驻动画
- 测试：内核 muse_fast_test / muse_samples_test / muse_speedtest_sim_test / muse_same_as_test，兼容内核 testgate_test；应用 v1104_test

### 1.10.3 - 2026-11-04

- 测速：中国移动等家庭宽带下大量节点显示「超时」。原因是测速时同时发起的连接太多（16 个节点并发，每个节点 1 次预热 + 5 次同时探测，峰值约 80 条新连接），家庭宽带的会话数限制 / QoS 会丢掉其中一部分，原本能用的节点被判成超时；5 秒超时也不够慢线路丢一个包后重传
- 标准内核 5.0.0-muse.21：默认并发 16 → 8，每节点同时探测 5 → 3 次，默认超时 5 → 8 秒；没有可用结果的节点第一次失败不再立刻显示「超时」，3 秒后单独重测一次（满超时，排在本轮测速之后），再失败才显示「超时」
- 兼容内核（同一提交）：默认 8 并发 / 8 秒；失败节点在本轮结束 2 秒后重测一次，重测前显示为「测速中」
- 应用：测速默认值改为 8 并发、8 秒（开发者选项里改过的值保留）；节点在重测期间显示「测速中」，全部有结果才结束测速，进度不把重测中的节点算作完成；测速最长等待按重测一轮计算（上限 2 分钟）
- 节点地址解析不变：节点域名经 223.5.5.5 / 119.29.29.29（UDP、TCP 回退）解析，不用运营商 DNS，TCP 连接 IPv4 优先、IPv6 回退
- 测试：v1103_test（默认值、重测中显示、结束条件、进度）；内核 muse_latency_test / muse_parallel_test / h_balancer_test、兼容内核 TestUrlTestRetriesFailedOnce / TestTestDefaults1103

### 1.10.2 - 2026-11-03

- 「在最近任务中隐藏」恢复：开关移到「设置 › 外观 › 通知与图标」（仅 Android）；存储 key 仍为 exclude_from_recents，MainActivity 每次回到前台按已存值重新应用（与 1.9.1 一致）；设置搜索「最近任务」「隐藏」可找到
- 节点页：工具栏（搜索 / 测速 / ⋯）与搜索框固定在列表上方，进入时自动滚到当前节点后不再被滚出屏幕；自动滚动改为每次进入节点页且当前节点变了才滚（跟随页面可见性，无轮询），在首页换节点后再进节点页会定位到新节点，在节点页内点选不跳动
- 修复「滚动到当前节点」在列表已离开时报错（ScrollController not attached）
- 「活动 › 连接」在手机横屏等矮屏幕上顶部内容溢出 6 px：矮于 400 dp 时顶部与列表一起滚动，竖屏不变
- 「活动 › 诊断」检测中途切换标签或返回时不再在后台对已销毁的页面调用 ref（StateError）
- 测试：v1102_sweep_test（设置各子页、节点、规则、订阅、活动五个标签、关于在手机竖/横屏、平板竖/横屏、浅/深色及 320 宽 1.3 倍字号下无溢出、无 FlutterError；节点页「⋯」每一项可用）、v1102_test

### 1.10.1 - 2026-11-03

- 「关于」页：检查更新改成明显的「点击检测更新」（主色，可点；检查 / 下载时显示「正在检查更新…」「正在下载 N%」），版本信息「版本（构建号）· 内核」移到它正下方，小号灰字，不可点；连点图标 7 次开启开发者选项不变
- 开发者选项里的提示改为「在『关于』连点图标 7 次可再次打开」（与实际操作一致）

### 1.10.0 - 2026-11-03

1.9.2 未单独发布，其安全修复并入本版。

- 安全（GHSA-frr6-h895-5pxp，High）：构建工具链升级到 Flutter 3.47.8（Dart 3.13.7）。旧版 dart:io 在 Android / Windows 上信任已泄露私钥的 eMudhra 中间证书，处于中间人位置的攻击者可冒充订阅服务器、更新服务器或同步服务器；本版起应用自身的 HTTPS 连接（订阅拉取、应用内更新、同步）拒绝这批证书
- 安全（Go CVE-2026-111943，并含 CVE-2026-97031 修复）：标准内核 5.0.0-muse.20 与兼容内核均改用 Go 1.26.10 构建，内核 crypto/x509 同样拒绝这批中间证书
- CI：代码生成（build_runner / slang）单独一个任务，用 Flutter 3.38.5 生成源码后交给 3.47.8 构建（生成器依赖的 analyzer 7.x 读不了 Flutter 3.47 源码，曾导致 1.9.2 构建卡住 6 小时）；发布的应用只由 3.47.8 编译
- 「关于」页：只留居中图标、名称和一行「版本（构建号）· 内核」小字；点这行即检查更新（有新版弹窗含更新内容，无则提示已是最新，下载进度也显示在这行）；底部「开源许可与致谢」进入子页（许可、源代码、GPL 致谢）
- 「节点」页：去掉顶部「当前节点」卡（列表高亮并自动滚到当前节点）；工具栏收成「搜索」「测速」和「⋯」菜单（筛选 / 排序 / 布局 / 多选 / 节点设置）；去掉行尾绿点，延迟数字按快慢着色，协议标签弱化
- 节点「不可用」开关与分组去掉：超时节点自然排到末尾，延迟处显示「超时」
- 设置首页收成 8 项：外观、自动连接（含智能保持连接）、分应用代理、网络（含原「高级」：负载均衡、TLS 分片、IPv6、Fake-IP、屏蔽 QUIC、切换节点时关闭旧连接）、活动（连接 / 日志 / DNS / 统计 / 诊断）、备份与同步、内核与资源、关于；Android / Windows 专属项按平台放进对应页
- 规则入口只保留订阅页「规则」（分流 / 订阅覆写）；「去广告」在分流标签，覆写 JSON 编辑在规则页「⋯」；「订阅自动更新」在订阅页「⋯」
- 删除「帮助与隐私」「后台保活」页；Android 首次连接时如未加入电池优化白名单，只提示一次跳转系统设置（无后台唤醒或轮询）
- 所有删除或挪动的旧名称在设置搜索里仍可找到并跳到新位置；设置存储 key 不变，已有设置不丢

### 1.9.1 - 2026-11-02

- Android 发布 armeabi-v7a（32 位 ARM，约 63 MB）与 x86_64（约 67 MB）安装包，各自带对应架构的标准内核与兼容内核及 .sha256；arm64 包不变
- 应用内更新按当前运行架构选择安装包，对应架构的包不存在时不提示更新

### 1.9.0 - 2026-11-02

- 新增「设置 › 帮助与隐私」：名词解释（可搜索）、穿云在本机保存什么 / 不上传什么、导入订阅后可清空剪贴板
- 统计可导出 CSV；备份与同步新增「每周本地快照」（默认关，保留最近 5 份，与恢复前 / 更新前的自动备份分开计数）
- 规则测试支持一次粘贴多个域名；分流规则可导出为 sing-box 格式；网络页可一键恢复推荐 DNS
- 订阅菜单新增「打开官网 / 续费」；订阅自动更新时间按订阅错开最多 10%
- 检查更新确认框显示安装包大小；CHANGELOG 补齐 1.3.0 / 1.4.0，并增加测试保证与应用内更新说明同步；新增 PR 自检模板
- 新增「规则」页：分流 / 订阅覆写两个标签；订阅页、设置「分流」和设置搜索都打开新页
- 订阅覆写：每个订阅可加自定义规则、追加节点（分享链接）、代理组（名称正则筛选，手动 / 自动）；连接时运行时合成，订阅文件不改、更新后保留，按订阅保存并参与同步；「高级」可直接编辑覆写 JSON。已知限制：兼容内核 + sing-box JSON 订阅时追加的代理组暂不生效（规则、节点生效）
- 首次使用引导：无订阅时首页三选一——粘贴链接 / 扫码（仅手机）/ 从文件导入；原「添加订阅」保留为「更多方式」
- 设置整理：新增「自动连接」页（自动运行、按需运行、定时连接 / 断开、开机自启及静默）；Android 新增「后台保活」页；「备份与同步」「内核与资源」各合为一页；导出备份与脱敏备份合成一个按钮（弹窗勾选「脱敏」）；测试页只在 debug 构建出现；旧名称在设置搜索中仍可找到并跳到新页
- 兼容内核稳定性：意外停止按 2/5/10/30/60 秒退避自动重启，系统网络变化时通知内核重置旧连接（事件驱动，不轮询）；Android 服务被系统销毁而进程仍在时限频自拉起
- 兼容内核：默认分流用到的规则集（geosite-cn / geoip-cn / 去广告，约 0.58 MB）随包内置，首次连接无需联网；Windows 兼容内核直接读取 SIP008 与 WireGuard 订阅；不再请求规则数据中不存在的列表
- 体积：去掉未使用的图标字体包，APK 约小 0.9 MB
- 其他：清理遗留 TODO、拆分节点列表与设置大文件、Windows 恢复冒烟测试改为等待状态并重试、新增真机测试清单 docs/device-test-checklist.md

### 1.8.0 - 2026-11-01

- 新增「活动」页：原「连接」「日志」两页合并为一页三个标签（连接 / 日志 / DNS），设置 › 活动、侧边栏「活动」、首页「连接统计」卡片都打开它；旧位置 /settings/connections、/settings/logs 自动打开对应标签，设置搜索「连接」「日志」「DNS 查询」直达对应标签。连接标签里「活动 / 请求」改称「进行中 / 请求」
- DNS 标签：每条查询显示域名与类型、实际应答的 DNS（223.5.5.5、tcp://119.29.29.29、远程 DNS、Fake-IP、系统 DNS 等，DNS 分组内显示实际应答的成员）、返回的 IP、耗时、缓存标记；可搜索域名 / IP / DNS，长按只看该域名，点按复制，清空（同时清空内核缓冲）
- 只在当前标签开启对应数据流，切换标签立即停止；DNS 记录只在 DNS 标签打开时由内核采集（无订阅时内核不做额外工作，无新增定时器、轮询或后台唤醒）
- 兼容内核没有 DNS 查询记录，DNS 标签显示「当前内核不支持」
- 内核 5.0.0-muse.19：sing-box DNS 客户端增加查询记录钩子与本地接口 /dns/queries（500 条环形缓冲，websocket 订阅时推送；DELETE 清空），标准 DNS 行为不变；新增 Go 测试；新增测试 v180_test

### 1.7.1 - 2026-10-30

- 配色修正：主题色（primary）按所选色号原样显示——按钮、选中态、开关、连接按钮等；按钮上的文字按 WCAG 对比度自动选黑或白（≥4.5:1）。主色容器、页面、分割线等大面积颜色仍由算法生成（取原色色相、较高饱和度）。深色模式下过暗的颜色（与深色页面对比不足 3:1）会适度提亮，浅色模式与正常亮度颜色始终是原色值
- 新增配色风格「忠实」（Material 3 Fidelity）并设为默认；已保存的「标准」（旧默认）自动迁移为「忠实」，其他风格保持不变。「鲜明」「着色」同样保留原色
- 主题色调整：苤蓝 #6B798E → 宝蓝 #4B5CC4、月白 #D6ECF0 → 松花 #BCE672、苍蝇灰 #36282B → 胭脂 #9D2933；朱瑾 #C41E3A 不见于中国传统色色表，修正为最接近的枣红 #C32136；其余 6 色核对无误。已选旧色的设置自动迁移到对应新色（同步来的旧值同样识别）。状态灯四色不变
- 设置迁移版本 2 → 3；新增测试 v171_test

### 1.7.0 - 2026-10-30

- 双内核：设置 › 内核 可在标准内核与兼容内核之间切换（默认标准内核）；Windows 与 Android 都支持，兼容内核在 Android 上运行于独立进程
- 订阅兼容模式：兼容内核下订阅原样保存（Clash YAML 的代理组与规则、分享链接原样使用）；切回标准内核时自动转换并保留原文，来回切换不丢内容；订阅同步仍只增不删
- 兼容内核不支持的节点保留在订阅里，节点列表灰显「当前内核不支持：协议」
- 兼容内核的分流与 DNS 与标准内核一致：规则模式下国内域名 / IP 直连，国内域名用国内 DNS 解析
- 兼容内核进程被系统结束后自动恢复连接（用户断开、VPN 权限被收回、启动失败时不恢复；无新增定时器或轮询）
- 以下国内网络修复（原计划 1.6.4，合并到本版发布）：
- 修复：开着穿云时部分国内网站很卡。原因是国内 DNS 分组遇到合法的空结果（没有 IPv6 地址的网站的 AAAA、HTTPS 记录、不存在的域名）不采纳，依次改问 223.5.5.5 的 TCP/TLS 和直连的 8.8.8.8（UDP/TCP/TLS），而 tls://8.8.8.8 在国内常被丢弃，一次查询最长等到 10 秒超时；8.8.8.8 的结果还会把国内网站指向不适合本地网络的 CDN 节点。现在国内 DNS 分组只含国内服务器：所选服务器（默认 udp://223.5.5.5）及其 TCP、再到 119.29.29.29（UDP/TCP）；远程 DNS 分组为所选服务器 + 一个经节点的 TCP 备用
- 修复：DNS 缓存永不过期、国内结果的 TTL 被改写为 1 天（系统和应用也按 1 天缓存），切换 Wi‑Fi / 移动数据或运营商后仍用旧网络的 CDN 节点（常为跨网慢节点）。国内结果现在保留服务器给的 TTL，缓存按时过期；过期记录先返回一次（TTL 1）同时刷新（乐观缓存，1 小时内有效），只在有查询时刷新，不新增定时器；缓存容量 4096
- 修复：系统代理（Windows 默认）下，不在 geosite-cn 里的国内网站因为目标是域名、geoip-cn 规则匹配不到而走了节点。现在在「国内直连」规则前先按 DNS 规则解析域名（与 TUN 模式拿到的结果一致；Fake-IP 下不解析）
- 内核 5.0.0-muse.18（只改穿云生成的配置，sing-box 本身未改）；新增配置生成测试：国内 DNS 分组只含国内服务器且直连、国内域名 / 国内 IP（TUN 与系统代理）走直连、国外走节点、国内 QUIC 不被拦截
- 未改：TUN 栈（Android 只用 gVisor）、MTU 9000、strict_route、测速与自动选择（只影响新连接，不打断已有连接）、「屏蔽 QUIC」（默认关闭）

### 1.6.3 - 2026-10-30

- 首页新增「编辑」按钮，可显示更多卡片：服务状态、代理组、连接统计、内网 IP、内存等
- 入口：首页顶部右侧铅笔图标（提示「编辑首页」）和卡片列表末尾的「编辑首页」按钮，手机与宽屏 / Windows 都可见；长按卡片照常可用
- 编辑面板新增说明：打开开关显示卡片、关闭隐藏，按住左侧把手拖动排序
- 不新增后台唤醒、轮询或常驻动画

### 1.6.2 - 2026-10-29

- 中国传统色主题：景泰蓝等 10 色——景泰蓝 #2775B6（默认）、苤蓝 #6B798E、竹青 #789262、月白 #D6ECF0、苍蝇灰 #36282B、朱瑾 #C41E3A、藤黄 #FFB61E、青碧 #48C0A3、丁香 #CCA4E3、赭石 #845A33；色块悬停 / 长按显示色名，设置搜索可按色名搜到「主题色」
- 状态灯改用传统色（固定，不随主题色变化）：葱青 #0EB83A（正常 / 延迟低）、杏黄 #FFA631（注意）、朱砂 #FF461F（失败 / 超时 / 删除类操作）、墨灰 #758A99（未测试 / 未连接）
- 兼容：以前保存的主题色自动对应到新预设（蓝→景泰蓝、绿→竹青、青→青碧、紫→丁香、靛→苤蓝、粉→朱瑾、橙→藤黄），旧设备同步来的旧值同样识别；自定义 #RRGGBB 照常可用，且配色直接由所选颜色本身生成
- 可读性：月白、藤黄、丁香等浅色上的选中勾与文字改用深色；所有 10 色 × 7 种配色风格 × 深浅 / 纯黑下按钮与选中态文字对比度经测试达标
- 性能：主题色的派生颜色与配色方案按值缓存，只在更换时计算一次；不新增后台唤醒、轮询或常驻动画

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

### 1.4.0 - 2026-10-22

- 节点测速更快：有界并发、按节点数调整超时，打开即显示上次延迟，测速中可停止
- 节点：重命名、备注、隐藏，名称美化，正则筛选/排除，隐藏重复节点；按地区分组可折叠并显示最低延迟；详情显示地址、落地 IP、健康度
- 分流预设：AI、流媒体、Telegram、游戏、苹果、微软、Steam、学术、国内银行、隐私拦截；规则测试；自定义 hosts；规则导入导出
- 坚果云 WebDAV 同步（加密上传）与本地备份/恢复；流量统计（日/月）与月度报告；远程 DNS 预设
- 外观：主题色、字体大小、隐私模式；订阅二维码分享
- Windows：主页卡片按列数自适应，网速与本次流量合并为「流量」卡；移除 Ctrl+Alt+P 快捷键

### 1.3.0 - 2026-10-21

- 全新界面：首页改为仪表盘（连接卡片 + 网速、流量、剩余流量、到期、出口 IP、去广告），长按卡片可排序或隐藏
- 浅色背景改为淡蓝渐变加云朵，深色模式改为夜空蓝；节点列表移到单独的「节点」页，未连接时也能选节点
- 「智能保持连接」一个开关管掉线重连、换最佳节点、内核重启；出口检测、外网检测、一键诊断合并为「诊断」
- 添加订阅统一为一个「添加」入口；去广告可选 关 / 温和 / 强力

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
