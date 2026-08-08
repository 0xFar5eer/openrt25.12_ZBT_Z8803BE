![OpenWrt logo](include/logo.png)

# ZBTLink ZBT-Z8803BE OpenWrt 固件

[English](README.md) | [中文](README.zh-CN.md)

> **社区版本。** 此固件由个人独立维护，并非来自厂商或 OpenWrt 官方项目，难免存在 bug 和粗糙之处。欢迎大家提交 Issue 与 PR。

面向 **ZBTLink ZBT-Z8803BE** WiFi 7 路由器的自定义 OpenWrt 固件。

## 捐赠
可选捐赠将用于支持维护和测试：

- **ERC20 / BEP20 — USDT、USDC、ETH、BNB：** `0xd1122130ad6e9ab948212087a90797e3129bfc1c`
- **TRC20 — TRX、USDT：** `TTcT5m4BriHKyNrB4KYyLMK4ZGn54Nk6z2`
- **BTC：** `12N34ZYeiwxKEcM5FSnkgnHwxhW6pE3r4m`
- **LTC：** `LLNtEGeZ5C6QnSY6BU1MYAZjh8MJpF6zsK`

- **OpenWrt 基线:** OpenWrt `25.12.2` / `r32858-16347e93b6`
- **内核:** Linux `6.12.74`
- **目标平台:** `mediatek/filogic`
- **设备:** MediaTek MT7988A / Filogic 880 + MT7996 系列三频 WiFi 7
- **发布标签:** `v25.12.018`

## 下载

发布构建完成后，请使用 GitHub 最新 Release 中的文件：

- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin`
- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin`
- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest`
- `sha256sums`
- `config.buildinfo`
- `feeds.buildinfo`
- `version.buildinfo`
- `RELEASE_NOTES.md`
- `RELEASE_NOTES.zh-CN.md`

## 校验值

```text
64e791598268bbf5b29141bc0a7bac17479b7b189a2d6dc565992f6a0db2d0de  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
070e89ab5415ae67c319c8b245b2c9f69d2894615f1e3e0fce67201e77725c31  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
6875eae6712978d9487f8dfcfc6b978854d1e618e7eebc4412ea554f6fc8e63c  openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
```

## 已包含功能

- **OpenWrt 25.12.2 基线:** 不依赖 MediaTek vendor feed。
- **WiFi 7 三频:** 2.4 GHz、5 GHz、6 GHz、EHT320、WPA3、支持 MLO。
- **PH WiFi 默认值:** 国家码 `PH`，启用 PH 允许的完整信道集合，固件不额外限制 txpower/channel，并由驱动按法规自动选择最大发射功率。
- **LuCI:** HTTPS、中文翻译、软件包管理器，以及聚焦于 Health、Temperature、Modem Events 和 QModem 的 Services/服务菜单。
- **自定义 LuCI 应用:** About、Health、Temperature 和 Modem Events。
- **已移除的可选套件:** 流量统计、QoS、DDNS、NAS、DNS 过滤和广泛诊断工具不预装；可按需通过软件包管理器安装。
- **QModem Next:** 现代 JS 调制解调器界面，内置短信、监控、AT 调试和调制解调器控制。
- **调制解调器栈:** QMI、MBIM、NCM、MHI、USB serial、QModem、`sms_tool_q`。
- **Z8803BE-T SIM 接线说明:** 此精确型号/版本中，SIM1 固定连接 modem1，SIM2 固定连接 modem2；单个模块不能控制两张 SIM 卡，因此不支持 SIM 切换。
- **公开固件默认值:** 5G1 在冷启动时供电以枚举 USB 调制解调器；5G2 默认关闭直到手动启用。有线 WAN/SFP 优先，cellular 默认休眠并使用 metric `200` 且不作为默认路由。
- **存储:** USB 3.0、ext4、vfat、exfat 和 SFTP。
- **监控:** 路由器健康状态、autocore、温度历史和 modem 事件历史。
- **Shell 默认项:** banner、彩色提示符和常用别名；额外诊断工具按需通过软件包管理器安装。
- **软件源:** 已配置 OpenWrt + ImmortalWrt overlay APK 源。

## 安装

### 从现有 OpenWrt 升级

```sh
sysupgrade openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
```

清空配置刷机：

```sh
sysupgrade -n openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
```

### U-Boot 恢复刷机

1. 按住 **Reset** 后上电，直到进入恢复模式。
2. 打开 `http://192.168.1.1`。
3. 上传 `squashfs-sysupgrade.bin` 镜像。
4. 等待设备重启。

首次启动默认登录：

- **IP:** `192.168.1.1`
- **用户:** `root`
- **密码:** `admin`

请立即修改默认密码。

## 构建

使用仓库内 Docker 构建脚本：

```sh
./.buildenv/build.sh init
./.buildenv/build.sh feeds
./.buildenv/build.sh config
./.buildenv/build.sh download
./.buildenv/build.sh build
./.buildenv/build.sh extract
```

输出镜像：

```text
output/mediatek/filogic/openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
```

## 说明

- SFP+ 已包含，但此处未做实体硬件验证。
- 当前分支基于 OpenWrt `25.12.2` 和 Linux `6.12.74`。
- PH WiFi 默认值遵循 `wireless-regdb`；修改国家码、信道或天线增益前请自行确认当地合规性。

## 反馈与联系

- **Issue / PR:** https://github.com/0xFar5eer/openwrt25.12_ZBT_Z8803BE/issues
- **Email:** [0xfar5eer@gmail.com](mailto:0xfar5eer@gmail.com)

欢迎提交 Issue 与 PR。同样的信息也会显示在路由器的 SSH 登录 banner 与 LuCI 中 **系统 -> 关于此固件** 页面。

## 致谢

- [@pttuan](https://github.com/pttuan) —— OpenWrt 主线板级支持 [openwrt#23053](https://github.com/openwrt/openwrt/pull/23053)：DT 原生风扇、GPIO 看门狗、热管理冷却映射、现代 LED 绑定。
- [@sjanulonoks](https://github.com/sjanulonoks) —— 建议加入风扇控制优化，并参与本版本的整体测试，帮助调校和验证这版 ZBT-Z8803BE 固件。
- [FUjr/QModem](https://github.com/FUjr/QModem) —— 本固件采用的 QModem Next 现代 JS 界面；此精确 Z8803BE-T 版本中 SIM1/SIM2 分别接到两个 M.2 调制解调器，因此已禁用 SIM 切换。
- [OneB1t/Z8803BE-research](https://github.com/OneB1t/Z8803BE-research) —— 对原厂 21.02-SNAPSHOT 固件的研究，揭示了失效的 opkg 软件源以及内置的回传通道。
- [OpenWrt mainline](https://openwrt.org) —— 本固件的基础发行版。
- [ImmortalWrt](https://github.com/immortalwrt) —— 构建过程中使用的补充软件包与 LuCI 资源。

## 捐赠
可选捐赠将用于支持维护和测试：

- **ERC20 / BEP20 — USDT、USDC、ETH、BNB：** `0xd1122130ad6e9ab948212087a90797e3129bfc1c`
- **TRC20 — TRX、USDT：** `TTcT5m4BriHKyNrB4KYyLMK4ZGn54Nk6z2`
- **BTC：** `12N34ZYeiwxKEcM5FSnkgnHwxhW6pE3r4m`
- **LTC：** `LLNtEGeZ5C6QnSY6BU1MYAZjh8MJpF6zsK`
