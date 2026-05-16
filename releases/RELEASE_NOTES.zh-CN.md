# ZBT-Z8803BE OpenWrt main / kernel 6.18 候选版

[English](RELEASE_NOTES.md) | [中文](RELEASE_NOTES.zh-CN.md)

> **社区版本。** 由个人独立维护，难免存在 bug 与粗糙之处，欢迎提交 Issue 与 PR。

面向 **ZBTLink ZBT-Z8803BE** WiFi 7 路由器的自定义 OpenWrt 固件。

- **发布标签:** `v25.12.5-zbt8803be-main6.18`
- **OpenWrt 基线:** 当前 OpenWrt `main` / `r32860-f96b44fbd4`
- **内核:** `6.18.28`
- **目标平台:** `mediatek/filogic`
- **默认登录:** `root` / `admin`

## 本版变化

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

- `./.buildenv/build.sh config` 已完成并写入 `.config`。
- 生成的 `.config` 已选择 `CONFIG_TARGET_mediatek_filogic_DEVICE_zbtlink_zbt-z8803be=y`。
- 生成的 `.config` 已选择 `CONFIG_LINUX_6_18=y`。
- 生成的 `.config` 已选择 `CONFIG_PACKAGE_kmod-usb-net-ipheth=y`、`CONFIG_PACKAGE_usbmuxd=y`、`CONFIG_PACKAGE_libimobiledevice-utils=y` 和 `CONFIG_PACKAGE_libusbmuxd-utils=y`。
- 完整 rebuild 已完成，产物已提取到 `output/mediatek/filogic`。
- staged release assets 已通过 `sha256sum -c sha256sums --ignore-missing`。
- 最终 manifest 包含 `kmod-usb-net-ipheth`、`usbmuxd`、`libimobiledevice`、`libimobiledevice-utils` 和 `libusbmuxd-utils`。
- USB tethering 脚本在 rebuild 前已通过 `sh -n` 语法检查。
- sysupgrade squashfs 已确认包含 `86-zbt-adguardhome-defaults`、`84-zbt-luci-js-compat`，以及 `/usr/share/zbt/apk/` 下的内嵌 AdGuardHome APK。
- 最终 manifest 包含上面列出的自定义应用层，包括 MLO、QoSmate、autocore、cpufreq、wrtbwmon 和 ZBT LuCI apps。
- rebuild 前已在 3FL 上验证 LuCI compat3 行为；发布前已在本地验证新镜像内容。

## 校验值

```text
1841812800da9039cab6ca0bd827f2462951c00e367b23650efe6770ac4dd7dd *config.buildinfo
ae37cfd49e2d7a9287a4efc424822e56abecfd427ce380655489a9614227f12e *feeds.buildinfo
31719cefe6ce1dad70670a0f3613e2f85c96311bb180453db1fbc40dfba9342e *openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
5253300b23ef2604d646a9982b448a0d2c41b02f320fd4a58c52e37525be719f *openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
0a83381413f1c9ff287317b5edc8fb771861d22590f28090b4f615a7d8a1026d *openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
08481bee00f9c0e2ad1019ee69589f92571e6129a86aaa6b93ce900e8939c3c1 *version.buildinfo
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

手动确认后，不保留配置刷机：

```sh
sysupgrade -n openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
```

如果执行 clean reflash，之后运行 setup 并恢复 DB/history 文件。
