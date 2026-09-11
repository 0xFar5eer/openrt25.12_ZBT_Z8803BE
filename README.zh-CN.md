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
- **发布标签:** `v25.12.022`

## 下载

发布构建完成后，请使用 GitHub 最新 Release 中的文件：

- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin`
- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin`
- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest`
- `sha256sums`
- `config.buildinfo`
- `feeds.buildinfo`
- `version.buildinfo`
- `packages-aarch64_cortex-a53.tar.gz`
- `RELEASE_NOTES.md`
- `RELEASE_NOTES.zh-CN.md`

## 校验值

```text
37d2364c3219afb26b9c9b2e6ccdea8a73fe7941de2a0d39b2bb0a9368991ea9  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
ff1e023ee2aa1170778552db9e58e334226d3c60d5ef0f3c4daa6250cb2a02cf  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
b7773d432b257ac851b2c973e0397bcbb6eb6f588aa32c0740806c1c8715fc7a  openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
fc7b71089f4e1ab3f280294d4bdb64b7acff1018a207b73f99de16e0b771a9ae  packages-aarch64_cortex-a53.tar.gz
```

## 已包含功能

- **OpenWrt 25.12.2 基线:** 不依赖 MediaTek vendor feed。
- **WiFi 7 三频:** 2.4 GHz、5 GHz、6 GHz、EHT320、WPA3、支持 MLO；LuCI 的 **网络 → WiFi 7 MLO** 提供按需启用的 MLO 配置。
- **Shell timeout:** 已包含 GNU `timeout`，路径为 `/usr/bin/timeout`。
- **PH WiFi 默认值:** 国家码 `PH`，启用 PH 允许的完整信道集合，固件不额外限制 txpower/channel，并由驱动按法规自动选择最大发射功率。
- **LuCI:** HTTPS、中文翻译、软件包管理器，以及聚焦于 Health、Temperature、Modem Events 和 QModem 的 Services/服务菜单。
- **自定义 LuCI 应用:** About、Health、Temperature 和 Modem Events。
- **已移除的可选套件:** 流量统计、QoS、DDNS、NAS、DNS 过滤和广泛诊断工具不预装；可按需通过软件包管理器安装。
- **QModem Next:** 现代 JS 调制解调器界面，内置短信、监控、AT 调试和调制解调器控制。
- **运营商 TTL 修复（默认关闭）:** LuCI 的 **调制解调器 → QModem → TTL** 可改写转发流量的 IPv4 TTL / IPv6 hop limit，用于应对会在会话建立数秒后主动断开的运营商（issue #9）。预置为 `64` 且默认**关闭**，因为启用后同时会关闭硬件 flow offloading。QMI 模式下固件的 `donot_nat=1` 请求根本不会送达 modem（只有 NCM/ECM 拨号路径会发它），因此以 QMI 拨号的 Quectel 仍在做 NAT，运营商看到的是 63——此时应使用 `65`。后台探针（`zbt-modem-nat-probe`，在蜂窝 ifup 时触发）会根据拨号器获得的地址识别出 modem-NAT 场景并自动把值提到 `65`；它不会替你启用插件，如果你手动改过该值它也会永久停用。在 GUI 中关闭 TTL 不会自动恢复 flow offloading，需手动执行 `uci set firewall.@defaults[0].flow_offloading='1' && uci commit firewall && /etc/init.d/firewall restart`。
- **调制解调器栈:** QMI、MBIM、NCM、MHI、USB serial、QModem、`sms_tool_q`。
- **Z8803BE-T SIM 接线说明:** 此精确型号/版本中，SIM1 固定连接 modem1，SIM2 固定连接 modem2；单个模块不能控制两张 SIM 卡，因此不支持 SIM 切换。
- **公开固件默认值:** 5G1 在冷启动时供电以枚举 USB 调制解调器；5G2 默认关闭直到手动启用。手动启用 5G2 后，固件按 USB 路径选择对应的 QModem 配置和 WAN 集成，不修改 5G1 的配置。
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
- **Discord:** `0xFar5eer#6504`

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
