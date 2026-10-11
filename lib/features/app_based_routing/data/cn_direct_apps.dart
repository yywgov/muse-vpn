// 穿云 - built-in 「常用国内 App 不走代理」 preset (app-based routing, bypass mode, region cn).
// These apps skip the VPN entirely: faster, and banks / 反诈 apps see the plain network.
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

const cnDirectApps = <String>{
  // 社交 / 办公
  'com.tencent.mm', // 微信
  'com.tencent.mobileqq', // QQ
  'com.tencent.tim', // TIM
  'com.tencent.wework', // 企业微信
  'com.alibaba.android.rimet', // 钉钉
  'com.ss.android.lark', // 飞书
  'com.tencent.wemeet.app', // 腾讯会议
  'com.sina.weibo', // 微博
  'com.zhihu.android', // 知乎
  'com.baidu.tieba', // 百度贴吧
  'cn.wps.moffice_eng', // WPS
  // 支付 / 购物 / 生活
  'com.eg.android.AlipayGphone', // 支付宝
  'com.unionpay', // 云闪付
  'com.taobao.taobao', // 淘宝
  'com.tmall.wireless', // 天猫
  'com.taobao.idlefish', // 闲鱼
  'com.jingdong.app.mall', // 京东
  'com.xunmeng.pinduoduo', // 拼多多
  'com.sankuai.meituan', // 美团
  'com.sankuai.meituan.takeoutnew', // 美团外卖
  'com.dianping.v1', // 大众点评
  'me.ele', // 饿了么
  'com.cainiao.wireless', // 菜鸟
  'com.sf.activity', // 顺丰速运
  'com.xingin.xhs', // 小红书
  // 视频 / 音乐 / 资讯
  'com.ss.android.ugc.aweme', // 抖音
  'com.ss.android.ugc.aweme.lite', // 抖音极速版
  'com.ss.android.article.news', // 今日头条
  'com.smile.gifmaker', // 快手
  'com.kuaishou.nebula', // 快手极速版
  'tv.danmaku.bili', // 哔哩哔哩
  'com.tencent.qqlive', // 腾讯视频
  'com.qiyi.video', // 爱奇艺
  'com.youku.phone', // 优酷
  'com.hunantv.imgo.activity', // 芒果TV
  'com.netease.cloudmusic', // 网易云音乐
  'com.tencent.qqmusic', // QQ音乐
  'com.kugou.android', // 酷狗音乐
  'com.baidu.searchbox', // 百度
  'com.baidu.netdisk', // 百度网盘
  'com.quark.browser', // 夸克
  'com.UCMobile', // UC浏览器
  'cn.xuexi.android', // 学习强国
  // 出行 / 地图
  'com.autonavi.minimap', // 高德地图
  'com.baidu.BaiduMap', // 百度地图
  'com.sdu.didi.psnger', // 滴滴出行
  'com.MobileTicket', // 铁路12306
  'ctrip.android.view', // 携程
  'com.Qunar', // 去哪儿
  'com.taobao.trip', // 飞猪
  'com.jingyao.easybike', // 哈啰
  'com.tmri.app.main', // 交管12123
  // 政务
  'com.hicorenational.antifraud', // 国家反诈中心
  'cn.gov.tax.its', // 个人所得税
  // 银行
  'com.icbc', // 工商银行
  'com.chinamworld.main', // 建设银行
  'com.android.bankabc', // 农业银行
  'com.chinamworld.bocmbci', // 中国银行
  'cmb.pb', // 招商银行
  'com.cmbchina.ccd.pluto.cmbActivity', // 掌上生活
  'com.bankcomm.Bankcomm', // 交通银行
  'com.bankcomm.maidanba', // 买单吧
  'com.yitong.mbank.psbc', // 邮储银行
  'com.ecitic.bank.mobile', // 中信银行
  'com.cebbank.mobile.cemb', // 光大银行
  'cn.com.cmbc.newmbank', // 民生银行
  'com.pingan.paces.ccms', // 平安口袋银行
  'com.cib.cibmb', // 兴业银行
  'cn.com.spdb.mobilebank.per', // 浦发银行
  'com.hxb.mobile.client', // 华夏银行
  'com.cgbchina.xpt', // 广发银行
  // 运营商
  'com.greenpoint.android.mc10086.activity', // 中国移动
  'com.sinovatech.unicom.ui', // 中国联通
  'com.ct.client', // 中国电信
  // ColorOS 自带
  'com.heytap.market', // 软件商店
  'com.heytap.browser', // 浏览器
  'com.finshell.wallet', // 钱包
};
