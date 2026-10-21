<div align="center">

<img src="docs/images/logo.svg" width="112" alt="穿云" />

# 穿云

**简洁、稳定、开箱即用的代理客户端 · Android / Windows**

导入订阅，点一下就连上。测速、选节点、订阅流量提醒、出了问题一键诊断，都在一个干净的界面里。

[![最新版本](https://img.shields.io/github/v/release/yywgov/muse-vpn?style=flat-square&label=%E6%9C%80%E6%96%B0%E7%89%88%E6%9C%AC&color=3B8BFF)](https://github.com/yywgov/muse-vpn/releases/latest)
[![下载量](https://img.shields.io/github/downloads/yywgov/muse-vpn/total?style=flat-square&label=%E4%B8%8B%E8%BD%BD%E9%87%8F&color=1A4FD6)](https://github.com/yywgov/muse-vpn/releases)
[![发布日期](https://img.shields.io/github/release-date/yywgov/muse-vpn?style=flat-square&label=%E5%8F%91%E5%B8%83%E6%97%A5%E6%9C%9F)](https://github.com/yywgov/muse-vpn/releases/latest)
[![平台](https://img.shields.io/badge/%E5%B9%B3%E5%8F%B0-Android%20%7C%20Windows-5B9BFF?style=flat-square)](#-下载)
[![许可证](https://img.shields.io/badge/%E8%AE%B8%E5%8F%AF%E8%AF%81-GPLv3%20%E6%89%A9%E5%B1%95%20%C2%B7%20%E9%9D%9E%E5%95%86%E7%94%A8-555?style=flat-square)](LICENSE.md)

[下载](#-下载) · [功能](#-功能亮点) · [快速上手](#-快速上手) · [常见问题](#-常见问题) · [更新日志](CHANGELOG.md)

</div>

---

## 📦 下载

| 平台 | 安装包 | 说明 |
| :--- | :--- | :--- |
| 🤖 **Android** | [Chuanyun-Android-arm64.apk](https://github.com/yywgov/muse-vpn/releases/latest/download/Chuanyun-Android-arm64.apk) | arm64 设备（近几年的手机基本都是） |
| 🪟 **Windows 安装版** | [Chuanyun-Windows-x64-Setup.exe](https://github.com/yywgov/muse-vpn/releases/latest/download/Chuanyun-Windows-x64-Setup.exe) | 推荐，自带 VC++ 运行库，支持应用内更新 |
| 🗂️ **Windows 便携版** | [Chuanyun-Windows-x64.zip](https://github.com/yywgov/muse-vpn/releases/latest/download/Chuanyun-Windows-x64.zip) | 解压即用，无需安装 |

> 链接始终指向最新版本。历史版本见 [Releases](https://github.com/yywgov/muse-vpn/releases)。已安装的用户在 **设置 › 关于 › 检查更新** 里即可升级。

## ✨ 功能亮点

### 🚀 连接
- **一键连接**：大按钮开关，**规则 / 全局** 两种模式随时切换；规则集随应用内置，连接不用等下载。
- **自动最快**：连上后同时测速所有节点，几秒内选出最快的一个。
- **节点失效自动切换**：手选的节点连续测速失败时临时切到「自动最快」，恢复后自动切回。
- **连通性提示**：连上后自动检测能否访问外网，不通时首页直接提示换节点。
- **出口检测**：显示出口 IP 与地区，以及 Google、ChatGPT、Netflix 是否可用。

### 🌐 节点
- **测速与排序**：按延迟 / 订阅顺序 / 地区排序与分组，下拉即可重新测速。
- **收藏与单测**：长按节点可收藏置顶、只测这个节点、查看详情。
- **自动整理**：不可用节点自动收起；「剩余流量 / 到期 / 官网」这类非节点条目自动隐藏（可关）。
- **记住选择**：每个订阅单独记住上次用的节点。
- **节点搜索**：节点多时按名称快速查找。

### 📋 订阅
- **剪贴板导入**：复制订阅链接后打开应用，顶部会提示一键导入。
- **流量与到期**：订阅卡显示已用流量、剩余天数和更新时间。
- **用量提醒**：流量用到 80%、用完、到期前 3 天各提醒一次（Android 与 Windows 都有）。
- **自动更新订阅**：更新间隔可选，更新失败会提示。

### 🛡️ 去广告与隐私
- **去广告**：分「温和 / 强力」两档，默认温和，尽量避免误拦导致 App 打不开。
- **分应用代理**（Android）：选择哪些应用走代理。
- **隐私选项**（Android）：可隐藏桌面图标、不出现在最近任务中。
- **日志脱敏**：导出的日志自动去掉订阅链接、密码、服务器地址等敏感信息。

### 🪟 Windows 专属
- **系统托盘**：连上即变蓝，右键菜单显示网速，可直接切换节点与 规则 / 全局。
- **全局快捷键**：`Ctrl + Alt + P` 随处连接 / 断开（可在设置中关闭）。
- **断线不断网**：连接守护会在异常时自动恢复系统代理，不会让整台电脑没网。
- **运行模式**：默认系统代理，可选 TUN 模式（需管理员权限）；支持开机自启。

### 🩺 省心
- **一键诊断**：依次检查 网络 → DNS → 节点 → 系统代理 / VPN → 外网，用大白话告诉你卡在哪。
- **应用内更新**：在应用里检查并安装新版本；升级后首次打开会弹出本次更新内容。

## 🏁 快速上手

1. **安装**：从上方 [下载](#-下载) 对应平台的安装包并安装。
2. **导入订阅**：复制服务商给你的订阅链接，打开穿云，点 **粘贴导入**（或顶部弹出的「导入」）。
3. **选节点**：在首页节点列表里点 **测速**，挑一个延迟低的节点；不想挑就用「自动最快」。
4. **连接**：点中间的大按钮即可连接。日常用 **规则** 模式即可，国内网站直连、其余走代理。

## ❓ 常见问题

<details>
<summary><b>Windows 打开时提示找不到 VCRUNTIME140.dll 等 DLL？</b></summary>

1.2.7 起 Windows 安装包已自带 VC++ 运行库，请下载最新的安装版重新安装即可。
</details>

<details>
<summary><b>已连接，但网页或图片加载很慢？</b></summary>

多半是当前节点慢或拥堵。先下拉重新测速，换一个延迟更低的节点；也可以切到「自动最快」。
</details>

<details>
<summary><b>显示已连接，却无法访问外网？</b></summary>

首页出现「无法访问外网」提示时，先换个节点试试。仍不行就打开 **一键诊断**，它会告诉你是网络、DNS、节点还是系统代理出了问题；需要反馈时可导出日志（已自动脱敏）。
</details>

<details>
<summary><b>Android 上用一会儿就自动断开？</b></summary>

请按首次连接后的引导，允许穿云 **后台运行**（关闭电池优化），部分机型还需开启 **自启动**。
</details>

## 🙏 致谢与许可证

穿云基于 [Hiddify](https://github.com/hiddify/hiddify-app) 二次开发，代理内核为 [sing-box](https://github.com/SagerNet/sing-box)。感谢两个项目的作者与贡献者。

本项目作为 [hiddify/hiddify-app](https://github.com/hiddify/hiddify-app) 的开源分支发布，遵循 [LICENSE.md](LICENSE.md)（Hiddify Extended GPLv3）：

- 源代码完全公开，所有发布版本均由 GitHub Actions 自动构建；
- **禁止任何商业用途**（包括售卖与广告）；
- 基于本项目的修改须以同一许可证开源。

**相对 Hiddify 的主要改动**：应用更名为「穿云」并重新设计中文界面（Android 包名 `com.musevpn.app`，可与 Hiddify 共存）；新增上文「功能亮点」中的连接守护、节点管理、订阅提醒、去广告分级、一键诊断、托盘与快捷键、应用内更新等功能；修复 Android 开机自启未在清单中注册的问题。逐版本的改动见 [CHANGELOG.md](CHANGELOG.md) 与 [Releases](https://github.com/yywgov/muse-vpn/releases)。上游原始 README 存档于 [docs/upstream](docs/upstream/)。

<div align="center">
<sub>穿云 · 仅供学习与个人使用，请遵守当地法律法规。</sub>
</div>
