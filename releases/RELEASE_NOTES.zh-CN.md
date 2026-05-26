# ZBT-Z8803BE OpenWrt main / kernel 6.18.33 正式版

[English](RELEASE_NOTES.md) | [中文](RELEASE_NOTES.zh-CN.md)

面向 **ZBTLink ZBT-Z8803BE** WiFi 7 路由器的自定义 OpenWrt 固件。

- **发布标签:** `v25.12.12-zbt8803be-main6.18`
- **内核:** `6.18.33`
- **构建版本号:** `r1-81fde127a8`
- **目标平台:** `mediatek/filogic`
- **默认登录:** `root` / `admin`

## 相比 v25.12.11 的变化

- **基于最新 OpenWrt main 重新同步，内核更新到 6.18.33。** 本地 ZBT-Z8803BE 定制内容已重新 replay 到新的上游代码树并完成重构建。
- **新增 TUN/TAP 支持，适配用户态 VPN/代理工具。** 固件现在包含 `kmod-tun`，提供 `/dev/net/tun`，可供 sing-box、xray-core、OpenVPN、wireguard-go、podkop 等工具使用。本项对应 GitHub issue #5。
- **新增 SFP/光模块诊断工具，方便 ONU-in-SFP 棒调试。** 固件现在包含 `i2c-tools`、`i2csfp`、`mdio-tools`、`mii-tool`，并继续保留已有的 `kmod-sfp`、`kmod-phy-aquantia`、`ethtool`、`ip-full` 支持。适用于带内部 PON MAC/OMCI 逻辑、支持 SFF-8472 DDM 的 SC/UPC 或 SC/APC GPON/EPON ONU SFP 光模块。

## PON SFP 用户说明

本版本支持的是路由器侧能力：SFP cage 检测、以太网链路/PHY 支持、模块 EEPROM/DDM 读取、MDIO/I2C 诊断。它**不会**把路由器变成 PON OLT，也不会在软件里实现 EPON/GPON MAC；SFP 棒本身必须内置 ONU/PON 功能。

插入兼容光模块后可使用：

```sh
ethtool <sfp-netdev>
ethtool -m <sfp-netdev>
i2cdetect -l
i2csfp -h
mdio --help
```

## 验证

- 完整 Docker rebuild 已完成：`r1-81fde127a8`，内核 6.18.33。
- staged release assets 通过 `sha256sum -c sha256sums --ignore-missing`。
- manifest 确认包含 `kmod-tun`、`i2c-tools`、`i2csfp`、`mdio-tools`、`mii-tool`、`kmod-mdio-netlink`、`kmod-sfp`、`kmod-phy-aquantia`。
- manifest 包含：

```text
kernel - 6.18.33~f20f4bdfe29c23a826260e96eee4651d-r1
kmod-tun - 6.18.33-r1
i2c-tools - 4.4-r2
i2csfp - 2025.08.05~1b9b4e0f-r1
mdio-tools - 1.3.1-r3
mii-tool - 2.10-r2
kmod-mdio-netlink - 6.18.33.1.3.1-r2
kmod-sfp - 6.18.33-r1
kmod-phy-aquantia - 6.18.33-r1
ethtool - 6.19-r2
ip-full - 6.18.0-r2
```

## 校验值

```text
73ebcffff91ae63a33da0d7c5a7c8b169ac8d9c830cdebc6b018568cd3ad7a0e *config.buildinfo
ae37cfd49e2d7a9287a4efc424822e56abecfd427ce380655489a9614227f12e *feeds.buildinfo
b5d0540d1d4e5dab3df034652ed704345fbbfce46a4a49b9643a95294c8d3683 *openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
b05d102c3da12bd255ed4668d55a7581978ad30f7c9d65ea366fd120afd92e17 *openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
0839cf21f4aa61c4ec13a948d18504ea24ca6b790a995dac22a672c40eb85ce7 *openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
b3c49ceec35c43f20da3896afc728e569df7c1ace68d820759535c14c95d46b3 *version.buildinfo
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
