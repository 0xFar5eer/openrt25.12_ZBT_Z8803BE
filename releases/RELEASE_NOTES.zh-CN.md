# ZBT-Z8803BE OpenWrt main / kernel 6.18.31 正式版

[English](RELEASE_NOTES.md) | [中文](RELEASE_NOTES.zh-CN.md)

> **社区版本。** 由个人独立维护，难免存在 bug 与粗糙之处，欢迎提交 Issue 与 PR。

面向 **ZBTLink ZBT-Z8803BE** WiFi 7 路由器的自定义 OpenWrt 固件。

- **发布标签:** `v25.12.7-zbt8803be-main6.18`
- **OpenWrt 基线:** 上游 `openwrt/openwrt` main HEAD `a7b5bb233f`
- **内核:** `6.18.31`
- **构建版本号:** `r364-8682ae2528`
- **目标平台:** `mediatek/filogic`
- **默认登录:** `root` / `admin`

## 本版变化

### GitHub 源码包构建修复与 Aquantia SFP+ 支持

- **GitHub source tarball 现在可以直接构建。** `.buildenv/build.sh` 会在 `config`、`download` 或 `build` 前检查并生成安全的 `./version`。这避免了 OpenWrt main/apk 在非 git worktree 环境中让 `scripts/getver.sh` 回退到 `unknown`，进而使 `base-files` 生成类似 `260516.34671 unknown` 的非法 APK version。
- **默认内置 Aquantia/Marvell 10G PHY 支持。** 镜像现在选择 `kmod-phy-aquantia`，覆盖 AQR113C 以及同类 Aquantia PHY SFP+ 模块，适用于 ZBT-Z8803BE 的 SFP+ 笼。

### 流量统计现在能正确计入 offload 流量

- **wrtbwmon 从 `inet fw4` forward dispatch 迁移到 `netdev wrtbwmon_acct` 的 ingress + egress hook（priority -300）。** 新 hook 在 fw4 flowtable 之前运行，软件 flow offload 不再绕过每设备统计。上一版在 LAN 客户端走 offload 时漏算 10 倍以上，本版已修复。
- **首次启动迁移脚本 `88-zbt-wrtbwmon-netdev-migrate`** 会清理遗留在 `inet fw4` 的旧 chain/map/set，并把保留下来的 `/etc/wrtbwmon.conf` 中的 `NFT_TABLE` 改写为新表名，旧版升级到本版后会自动接入新统计表。
- **`/etc/wrtbwmon/`（SQLite 数据库目录）已经登记到 `/lib/upgrade/keep.d/wrtbwmon`**，sysupgrade 会自动保留每设备流量历史，不再需要手动编辑 `/etc/sysupgrade.conf`。
- **三处现网刷机时发现的 bug 修复**（参见 `fix(wrtbwmon): unbreak the netdev refactor on the live device`）：BusyBox `tr` 不解析 `[:alnum:]`，导致多个 `ap-mldN` 设备 chain 名重复；`sqlite_init` 成功/失败分支写反，让 init 脚本恒为 inactive；迁移脚本现在会先改写 `NFT_TABLE` 再让新代码接管 nftables。

### 已切换到上游 `openwrt/openwrt` main

- **源码已 rebase 到上游 OpenWrt main HEAD `a7b5bb233f`**（kernel 6.18.31），替换之前的 snapshot 基线。
- **Replay 工具 `.buildenv/replay-customizations.sh`** 现在可以把 ZBT-Z8803BE 自定义层确定性地复现到任何上游快照上：自动生成 `./version`、按目录名生成独立的 Docker 卷 `.buildenv/local.env`，每次运行都会执行 drift 审计。
- **Docker 基础镜像按 manifest digest 固定** 在 `.buildenv/Dockerfile`（`ubuntu:24.04@sha256:c4a8d5503dfb...`），构建主机不会被 Docker Hub 重打 tag 偷偷换底。

### 沿用 v25.12.5 的内容

### USB tethering 备用 WAN

- **Android USB tethering 会作为次级 WAN。** 使用 `rndis_host`、`cdc_ether` 或 `cdc_ncm` 的 USB Ethernet tether 设备会被 hotplug 检测，并分配给 `network.usb_tether`。
- **已内置 iPhone USB tethering 所需包。** 镜像现在选择 `kmod-usb-net-ipheth`、`usbmuxd`、`libimobiledevice`、`libimobiledevice-utils` 和 `libusbmuxd-utils`。
- **有线 WAN 仍然优先。** 默认有线 WAN 保持 metric `10`；USB tethering 使用 metric `50`，因此优先级低于有线 WAN，但可作为故障切换路径。
- **包含首次启动和手动 setup。** 镜像首次启动会创建 `network.usb_tether`，把它加入 firewall `wan` zone，启用 `usbmuxd`，并提供 `/usr/sbin/zbt-usb-tether-setup` 用于手动配对和检查。

### OpenWrt main / kernel 6.18 rebase

- **固件源码已切换到 OpenWrt main。** ZBT-Z8803BE 板级支持和自定义软件层现在叠加在当前 OpenWrt main 上，而不是旧的 25.12 分支。
- **MediaTek 6.18 kernel 路线。** MediaTek target 当前使用 `KERNEL_PATCHVER:=6.18`。
- **保留 ZBT-Z8803BE image profile。** 镜像 profile 仍为 `zbtlink_zbt-z8803be`，并保留 `SUPPORTED_DEVICES += zbtlink,zbt-z8803be,mt7988a-nand` 兼容旧镜像升级。
- **自定义固件应用已迁移到新基线。** 本构建保留之前的自定义应用层：About、Health、Temperature、Modem Events、Speedtest、WiFi Clients、Traffic Statistics / wrtbwmon、MLO tooling、QoSmate、autocore 和 cpufreq。
- **AdGuard Home 已变为固件级默认项。** 固件内嵌官方预构建 AdGuardHome APK，首次启动本地安装；随后 dnsmasq 会转发到 `127.0.0.1#5454` 的 AdGuard，并使用 setup 脚本同款 DoH 上游、过滤器、拦截规则和白名单。
- **LuCI `.format()` 兼容修复已带缓存刷新。** 镜像包含 `zbt_luci_format_compat3` formatter shim 和 `zbt_luci_compat3` revision 后缀，浏览器刷新缓存后，当前 LuCI 菜单/页面中 `_('...').format(...)` 调用可正常工作。

### 感谢 Hauke 在 OpenWrt PR 中的 board/DTS review

感谢 [Hauke Mehrtens](https://github.com/hauke) 在 [openwrt/openwrt#23053](https://github.com/openwrt/openwrt/pull/23053) 中的最新 review。本固件已应用相关板级支持清理：

- **NVMEM MAC cells。** 根据 Hauke 的说明，只有引用 `compatible = "mac-base"` 且带 `#nvmem-cell-cells = <1>` 的 provider 时才需要显式 index；因此移除了 `gmac0`、`gmac1`、`gmac2` MAC 引用中的多余 `0` index：[comment](https://github.com/openwrt/openwrt/pull/23053#issuecomment-4450882616)。
- **5G modem LEDs。** 将 `5g1` / `5g2` LED 从普通 `label` 节点改为标准 `LED_FUNCTION_MOBILE`，并使用 `function-enumerator` 区分两个 modem 状态灯：[review comment](https://github.com/openwrt/openwrt/pull/23053#discussion_r3241518122)。
- **默认 WAN 拆分。** 首次启动网络配置现在只把 2.5G RJ45 口 `eth1` 作为默认 WAN；SFP+ `eth2` 单独暴露为 inactive `wan_sfp`，不再和 `eth1` 一起 bridge 到 WAN：[review comment](https://github.com/openwrt/openwrt/pull/23053#discussion_r3241580300)。
- **未使用的 fixed regulators。** 移除了从 reference board 带来的、但当前 DTS 未消费的 fixed `regulator-1p8v` 和 `regulator-3p3v` 节点：[review comment](https://github.com/openwrt/openwrt/pull/23053#discussion_r3241532510)。
- **Thermal fan map 校验。** 根据 Hauke 对 `level 3` / `<&fan 3 3>` 映射的 review，确认 CPU thermal fan cooling map 与注释一致：[review comment](https://github.com/openwrt/openwrt/pull/23053#discussion_r3241527161)。
- **保持 upstream DTS 方向。** DTS 直接使用 `mt7988a.dtsi`，保留 upstream-compatible 的 `compatible = "zbtlink,zbt-z8803be", "mediatek,mt7988a"`，并保持 OpenWrt LED/MAC aliases 与当前 PR review 方向一致。

## 验证状态

- `./.buildenv/build.sh config` 已完成并写入 `.config`（config + feeds buildinfos 已生成）。
- 生成的 `.config` 已选择 `CONFIG_TARGET_mediatek_filogic_DEVICE_zbtlink_zbt-z8803be=y`、`CONFIG_LINUX_6_18=y`、`CONFIG_PACKAGE_kmod-nft-netdev=y` 和 `CONFIG_PACKAGE_kmod-phy-aquantia=y`。
- 完整 rebuild 已完成（`r364-8682ae2528`），产物已提取到 `output/mediatek/filogic`。
- staged release assets 通过 `sha256sum -c sha256sums --ignore-missing`。
- 最终 manifest 包含 `kmod-phy-aquantia`、`kmod-nft-netdev`、自定义应用层（luci-app-zbt-{about,health,modem-events,speedtest,temperature,wifi-clients}、luci-app-mlo、luci-app-wrtbwmon、qosmate + luci-app-qosmate、autocore、cpufreq、luci-theme-argon + luci-app-argon-config），modem 栈（qmodem + luci-app-qmodem-{monitor,next}、kmod-usb-serial-{option,qualcomm,wwan}），以及 USB tethering 栈（kmod-usb-net-ipheth、usbmuxd、libimobiledevice、libimobiledevice-utils、libusbmuxd-utils）。
- sysupgrade squashfs 包含品牌 MOTD banner、ImmortalWrt APK 签名 key、缓存在 `/usr/share/zbt/apk/` 下的 AdGuardHome + LuCI APK、全部 26 个 ZBT uci-defaults （包括 `88-zbt-wrtbwmon-netdev-migrate`）、全部 hotplug glue，以及 12 个 `/usr/sbin/zbt-*` helper。
- netdev wrtbwmon 行为已在上一版构建中于 `3fl.lan` 刷机验证：sysupgrade 后 netdev 表 `wrtbwmon_acct` 启动成功，`ap-mld{0,1,2}`、`lan{0,1,2}`、`phy0.{0,1}-apN` 共 22 个 ingress+egress chain 都在位；测试流量下计数器正常增长；保留下来的 `traffic.db` 跨刷机完整保留。本次 v25.12.7 rebuild 已在本地验证 issue #4 相关变更：`./version` 自动生成与 manifest 中包含 `kmod-phy-aquantia`。

## 校验值

```text
4d913f988401ac01e6c989d1ae07b31b316a143cbdc625b8d6164da1444bf410 *config.buildinfo
ae37cfd49e2d7a9287a4efc424822e56abecfd427ce380655489a9614227f12e *feeds.buildinfo
df09cbf8c926e73eb15b43d057b2ae7b850b47aa15b7e5c365736d409211923b *openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
71984653705e0a1af73a3fc74521bb1e76488f0991d7a478254aae5f40a17a4d *openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
a58f638fcd670ba302e810501a6470544cab4f8f1b318595e7e26a2e2fde8a52 *openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
cf7f42d03a5adbb0b72b4444da0b8c467b360389639bb01c81442761212a7b32 *version.buildinfo
```

## 发布文件

成功构建并通过校验后，上传以下文件：

```text
openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
sha256sums
config.buildinfo
feeds.buildinfo
version.buildinfo
RELEASE_NOTES.md
RELEASE_NOTES.zh-CN.md
```

## 刷机计划

保留 UCI 配置与每设备流量历史的原地升级：

```sh
scp openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin root@<router>:/tmp/
ssh root@<router> 'sysupgrade -v /tmp/openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin'
```

本版随包发货的 `/lib/upgrade/keep.d/wrtbwmon` 会自动保留 `/etc/wrtbwmon/` 和 `/etc/wrtbwmon.conf`；老版本需在刷机前手动在 `/etc/sysupgrade.conf` 里加上 `/etc/wrtbwmon` 和 `/etc/wifihistory`。

清零刷机（不保留任何配置）：

```sh
sysupgrade -n openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
```
