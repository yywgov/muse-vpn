// 穿云 1.16.0 R17 - 国内应用识别：分应用代理（「以下 App 不走代理」）里一键选中手机上已装的常见国内
// 应用。名单是内置的包名清单，完全在本机比对，不联网、不扫描签名、不在后台运行；只在用户点按时
// 比对一次。选中后与手动勾选一样，可逐个取消或用「撤销」恢复。
// Part of 穿云 (GPLv3).

import 'package:hiddify/features/muse/logic/per_app_tools.dart';

/// 常见国内应用的包名（精确匹配）。只收录主流、包名稳定的应用。
const museDomesticPackages = <String>{
  // 社交 / 通讯
  'com.tencent.mm', 'com.tencent.mobileqq', 'com.tencent.tim', 'com.tencent.wework', 'com.alibaba.android.rimet',
  'com.ss.android.lark', 'com.sina.weibo', 'com.xingin.xhs', 'com.zhihu.android', 'com.douban.frodo',
  'com.baidu.tieba', 'com.immomo.momo', 'com.tencent.qqlite',
  // 支付 / 银行
  'com.eg.android.AlipayGphone', 'com.unionpay', 'com.chinamworld.main', 'com.icbc', 'com.chinamworld.bocmbci',
  'cmb.pb', 'com.cmbchina.ccd.pluto.cmbActivity', 'com.android.bankabc', 'com.bankcomm.Bankcomm', 'com.ecitic.bank.mobile',
  'com.spdbccc.app', 'com.cebbank.mobile.cemb', 'com.pingan.paces.ccms', 'com.webank.wemoney', 'com.jd.jrapp',
  // 购物 / 外卖 / 生活
  'com.taobao.taobao', 'com.tmall.wireless', 'com.jingdong.app.mall', 'com.xunmeng.pinduoduo', 'com.sankuai.meituan',
  'me.ele', 'com.sankuai.meituan.takeoutnew', 'com.dianping.v1', 'com.taobao.idlefish', 'com.achievo.vipshop',
  'com.suning.mobile.ebuy', 'com.taobao.litetao', 'com.smile.gifmaker', 'com.ss.android.ugc.aweme.lite',
  'com.wudaokou.hippo', 'com.yek.android.kfc.activitys', 'com.mcdonalds.gma.cn', 'com.lucky.luckyclient',
  // 出行 / 地图
  'com.sdu.didi.psnger', 'com.autonavi.minimap', 'com.baidu.BaiduMap', 'com.tencent.map', 'com.MobileTicket',
  'ctrip.android.view', 'com.Qunar', 'com.taobao.trip', 'com.jingyao.easybike', 'com.hellobike.atlas',
  'com.umetrip.android.msky.app', 'com.tongcheng.android',
  // 视频 / 音乐 / 阅读
  'com.ss.android.ugc.aweme', 'com.kuaishou.nebula', 'tv.danmaku.bili', 'com.qiyi.video', 'com.tencent.qqlive',
  'com.youku.phone', 'com.hunantv.imgo.activity', 'com.netease.cloudmusic', 'com.tencent.qqmusic', 'cn.kuwo.player',
  'com.kugou.android', 'com.ximalaya.ting.android', 'com.ss.android.article.news', 'com.ss.android.article.lite',
  'com.tencent.news', 'com.netease.newsreader.activity', 'com.qq.reader', 'com.dragon.read', 'com.duokan.reader',
  'com.tencent.weread', 'air.tv.douyu.android', 'com.duowan.kiwi', 'com.ss.android.ugc.live',
  // 工具 / 网盘 / 办公
  'com.baidu.searchbox', 'com.baidu.netdisk', 'com.UCMobile', 'com.quark.browser', 'com.tencent.mtt',
  'com.alibaba.android.alicloud', 'com.alicloud.databox', 'cn.wps.moffice_eng', 'com.tencent.docs', 'com.youdao.dict',
  'com.netease.mail', 'com.tencent.androidqqmail', 'com.ss.android.lark.kami', 'com.tencent.wemeet.app',
  'com.kingsoft.email', 'com.sohu.inputmethod.sogou', 'com.iflytek.inputmethod', 'com.baidu.input',
  // 政务 / 运营商
  'com.tencent.gamehelper.smoba', 'cn.gov.tax.its', 'com.ccb.ccbsharelife', 'com.greenpoint.android.mc10086.activity',
  'com.sinovatech.unicom.ui', 'com.ct.client', 'cn.gov.pbc.dcep', 'com.zhangyou.zs.chinaids',
  // 游戏
  'com.tencent.tmgp.sgame', 'com.tencent.tmgp.pubgmhd', 'com.miHoYo.Yuanshen', 'com.netease.party',
};

/// 已装的常见国内应用里还没选中的包名（按 [installed] 的顺序）。
List<String> museDomesticTargets(List<MuseAppRow> installed, Map<String, int> flags) => [
  for (final a in installed)
    if (museDomesticPackages.contains(a.packageName) && !museAppActive(flags[a.packageName])) a.packageName,
];

/// 点按后的提示。
String museDomesticSummary({required int added, required int already}) {
  if (added == 0 && already == 0) return '没有找到常见国内应用';
  if (added == 0) return '常见国内应用已全部选中（$already 个）';
  return already == 0 ? '已选中 $added 个常见国内应用' : '已选中 $added 个常见国内应用（另有 $already 个原本已选）';
}
