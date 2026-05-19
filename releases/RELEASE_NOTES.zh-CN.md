# ZBT-Z8803BE OpenWrt main / kernel 6.18.31 正式版

[English](RELEASE_NOTES.md) | [中文](RELEASE_NOTES.zh-CN.md)

面向 **ZBTLink ZBT-Z8803BE** WiFi 7 路由器的自定义 OpenWrt 固件。

- **发布标签:** `v25.12.7-zbt8803be-main6.18`
- **OpenWrt 基线:** 上游 `openwrt/openwrt` main HEAD `a7b5bb233f`
- **内核:** `6.18.31`
- **构建版本号:** `r364-8682ae2528`
- **目标平台:** `mediatek/filogic`
- **默认登录:** `root` / `admin`

## 相比 v25.12.6 的变化

- **修复 GitHub source tarball 构建。** `.buildenv/build.sh` 会在 `config`、`download` 或 `build` 前自动生成安全的 `./version`，避免 apk 因 `260516.34671 unknown` 这类非法版本号报错。
- **新增 Aquantia/Marvell 10G SFP+ PHY 支持。** 镜像默认内置 `kmod-phy-aquantia`，用于 AQR113C 以及同类 Aquantia PHY SFP+ 模块。

OpenWrt 基线、内核版本、wrtbwmon netdev 行为与 v25.12.6 相同。

## 验证

- 完整 rebuild 已完成：`r364-8682ae2528`。
- staged release assets 通过 `sha256sum -c sha256sums --ignore-missing`。
- manifest 包含：

```text
kmod-phy-aquantia - 6.18.31-r1
kmod-nft-netdev - 6.18.31-r1
wrtbwmon - 0.36-r1
```

## 校验值

```text
4d913f988401ac01e6c989d1ae07b31b316a143cbdc625b8d6164da1444bf410 *config.buildinfo
ae37cfd49e2d7a9287a4efc424822e56abecfd427ce380655489a9614227f12e *feeds.buildinfo
df09cbf8c926e73eb15b43d057b2ae7b850b47aa15b7e5c365736d409211923b *openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
71984653705e0a1af73a3fc74521bb1e76488f0991d7a478254aae5f40a17a4d *openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
a58f638fcd670ba302e810501a6470544cab4f8f1b318595e7e26a2e2fde8a52 *openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
cf7f42d03a5adbb0b72b4444da0b8c467b360389639bb01c81442761212a7b32 *version.buildinfo
```

## 刷机

保留配置与应用历史：

```sh
scp openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin root@<router>:/tmp/
ssh root@<router> 'sysupgrade -v /tmp/openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin'
```

清零刷机：

```sh
sysupgrade -n openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
```
