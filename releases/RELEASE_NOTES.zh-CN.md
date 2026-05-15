# ZBT-Z8803BE OpenWrt main / kernel 6.18 候选版

[English](RELEASE_NOTES.md) | [中文](RELEASE_NOTES.zh-CN.md)

> **社区版本。** 由个人独立维护，难免存在 bug 与粗糙之处，欢迎提交 Issue 与 PR。

面向 **ZBTLink ZBT-Z8803BE** WiFi 7 路由器的自定义 OpenWrt 固件。

- **发布标签:** 等待 clean reflash 验证后确定
- **OpenWrt 基线:** 当前 OpenWrt `main` / `r303+1-d841179375`
- **内核:** `6.18.28`
- **目标平台:** `mediatek/filogic`
- **默认登录:** `root` / `admin`

## 本版变化

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
- 完整 rebuild 已完成，产物已提取到 `output/mediatek/filogic`。
- staged release assets 已通过 `sha256sum -c sha256sums --ignore-missing`。
- sysupgrade squashfs 已确认包含 `86-zbt-adguardhome-defaults`、`84-zbt-luci-js-compat`，以及 `/usr/share/zbt/apk/` 下的内嵌 AdGuardHome APK。
- 最终 manifest 包含上面列出的自定义应用层，包括 MLO、QoSmate、autocore、cpufreq、wrtbwmon 和 ZBT LuCI apps。
- rebuild 前已在 3FL 上验证 LuCI compat3 行为；发布前已在本地验证新镜像内容。

## 校验值

```text
291d52d106f823bb129b0d007b3f7a3fa79bafaac41cdee3e42044aab5efeb36 *config.buildinfo
ae37cfd49e2d7a9287a4efc424822e56abecfd427ce380655489a9614227f12e *feeds.buildinfo
c65dd17640567042ab4349124571df6448362caaf35472644e0e299d7dccf9b7 *openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
dd571dfe6d82d003c9bb73947c93a7d588494c2019e8aca755146871029ec2fb *openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
2ae4f56dd79908e5ee37bc98e006bcba66e74a21c4d53b0196f8388cf05c57dc *openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
f814ce4b83e191a6148421107142da56b42a1771f191c79f86d2ca3b8918a688 *version.buildinfo
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

之后运行 setup 并恢复 DB/history 文件，全部验证通过后再发布 release。
