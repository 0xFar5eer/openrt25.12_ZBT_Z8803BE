![OpenWrt logo](include/logo.png)

# ZBTLink ZBT-Z8803BE OpenWrt 固件

[English](README.md) | [中文](README.zh-CN.md)

> **社区版本。** 此固件由个人独立维护，并非来自厂商或 OpenWrt 官方项目，难免存在 bug 和粗糙之处。欢迎大家提交 Issue 与 PR。

这是面向 **ZBTLink ZBT-Z8803BE** WiFi 7 路由器的当前自定义 OpenWrt 固件。

- **OpenWrt 基线:** 官方 `v25.12.2` / `r32802-f505120278`
- **内核:** Linux `6.12.74`
- **目标平台:** `mediatek/filogic`
- **设备:** MediaTek MT7988A / Filogic 880 + MT7996 系列三频 WiFi 7
- **发布标签:** `v25.12.2-1-zbt8803be`

## 下载

请使用 GitHub 最新 Release 中的文件：

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
7920ca111cd83f09b84613ff204237887dd6e801175f8ea37421b9783ea1760b  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
8574017bbdfd41ab4f52eec40645dab95e3dc9502056e7dd1197f85a242b9e83  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
f41ebb5fa5de5e6b2d890b482f2c9e0cf8e65dbe1423521eb265f319c806c0d0  openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
```

## 已包含功能

- **主线 OpenWrt 25.12.2:** 不依赖 MediaTek vendor feed。
- **WiFi 7 三频:** 2.4 GHz、5 GHz、6 GHz、EHT320、WPA3、支持 MLO。
- **PH WiFi 默认值:** 国家码 `PH`，启用 PH 允许的完整信道集合，固件不再额外限制 txpower/channel，并由驱动按法规自动选择最大发射功率。
- **LuCI:** HTTPS、Argon 深色主题、中文翻译、软件包管理器。
- **QModem Next:** 现代 JS 调制解调器界面，内置短信、监控、AT 调试、SIM 切换。
- **调制解调器栈:** QMI、MBIM、NCM、MHI、USB serial、QModem、`sms_tool_q`。
- **内置 SIM 切换:** QModem Next 通过 `AT+QUIMSLOT` 控制 SIM 卡槽。
- **调制解调器 LED:** 固件默认启用 LED 服务和状态轮询。
- **默认调制解调器供电:** 槽位 1 开启（`5g1=1`），槽位 2 关闭（`5g2=0`）。
- **网络:** WireGuard、SQM/CAKE、DDNS、firewall4/nftables。
- **WAN 故障切换默认值:** 首次启动即写入 WAN metric `10` 与 WWAN/QModem metric `20`，支持拔网线自动切换。
- **存储:** USB 3.0、ext4、vfat、exfat、ntfs3、Samba 4、SFTP。
- **监控:** autocore、cpufreq、collectd/statistics、WiFi history。
- **温度监控:** 内置 ZBT 温度图表，支持不同模块的避让温度线和风扇 PWM 记录。
- **Shell 默认项:** banner、彩色提示符、常用别名和工具。
- **软件源:** 已配置 OpenWrt + ImmortalWrt overlay APK 源。

## 已验证

已验证：

- WAN 主路由正常
- WAN 链路断开时 WWAN 备线路由可正常接管
- 重启后故障切换 metric 持久化正常
- DNS/互联网正常
- WiFi/MLO 正常
- QModem Next 与 SIM 切换功能正常
- 调制解调器 LED 服务正常

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
cp .buildenv/zbt8803be.config .config
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
- 未启用硬件 NAT/offload；本固件保持主线 OpenWrt 路线。
- PH WiFi 默认值遵循 `wireless-regdb`，仅移除固件侧额外的 txpower/channel 限制；修改国家码、信道或天线增益前请自行确认当地合规性。

## 反馈与联系

- **Issue / PR:** https://github.com/0xFar5eer/openwrt25.12_ZBT_Z8803BE/issues
- **Telegram:** https://t.me/Far5eer

由于本固件是社区版本，欢迎各位提交 Issue 与 PR，发现任何问题请直接反馈。同样的信息也会显示在路由器的 SSH 登录 banner 与 LuCI 中 **系统 -> 关于此固件** 页面。

## 致谢

- [@pttuan](https://github.com/pttuan) —— OpenWrt 主线板级支持 [openwrt#23053](https://github.com/openwrt/openwrt/pull/23053)：DT 原生风扇、GPIO 看门狗、热管理冷却映射、现代 LED 绑定。
- [FUjr/QModem](https://github.com/FUjr/QModem) —— 本固件采用的 QModem Next 现代 JS 界面，包含内置 SIM 切换页面（`AT+QUIMSLOT`）。
- [OneB1t/Z8803BE-research](https://github.com/OneB1t/Z8803BE-research) —— 对原厂 21.02-SNAPSHOT 固件的研究，揭示了失效的 opkg 软件源以及内置的回传通道。
- [OpenWrt mainline](https://openwrt.org) —— 本固件的基础发行版，不依赖联发科 vendor feed。
- [ImmortalWrt](https://github.com/immortalwrt) —— 构建过程中使用的补充软件包与 LuCI 资源。
