# ZBT-Z8803BE OpenWrt main / kernel 6.18.32 正式版

[English](RELEASE_NOTES.md) | [中文](RELEASE_NOTES.zh-CN.md)

面向 **ZBTLink ZBT-Z8803BE** WiFi 7 路由器的自定义 OpenWrt 固件。

- **发布标签:** `v25.12.11-zbt8803be-main6.18`
- **内核:** `6.18.32`
- **构建版本号:** `r32886-ff65d053dc`
- **目标平台:** `mediatek/filogic`
- **默认登录:** `root` / `admin`

## 相比 v25.12.10 的变化

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

- 完整 Docker rebuild 已完成：`r32886-ff65d053dc`，内核 6.18.32。
- staged release assets 通过 `sha256sum -c sha256sums --ignore-missing`。
- manifest 确认包含 `kmod-tun`、`i2c-tools`、`i2csfp`、`mdio-tools`、`mii-tool`、`kmod-mdio-netlink`、`kmod-sfp`、`kmod-phy-aquantia`。
- manifest 包含：

```text
kernel - 6.18.32~c855ebc1035e17e215441b25f3daa05d-r1
kmod-tun - 6.18.32-r1
i2c-tools - 4.4-r2
i2csfp - 2025.08.05~1b9b4e0f-r1
mdio-tools - 1.3.1-r3
mii-tool - 2.10-r2
kmod-mdio-netlink - 6.18.32.1.3.1-r2
kmod-sfp - 6.18.32-r1
kmod-phy-aquantia - 6.18.32-r1
ethtool - 6.19-r2
ip-full - 6.18.0-r2
```

## 校验值

```text
73ebcffff91ae63a33da0d7c5a7c8b169ac8d9c830cdebc6b018568cd3ad7a0e *config.buildinfo
ae37cfd49e2d7a9287a4efc424822e56abecfd427ce380655489a9614227f12e *feeds.buildinfo
8b8af9f7b299c7f6dd1113b8109c56c6e8d9f380a13fe4771ae266c988eb5cf0 *openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
1d6bc473063f8236863a8a0af1f5d21bd7f8fc11c201950007b8b0c1260d5b5e *openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
513bfbbbd1fec05ad6e01e4fb8da09dd203cbd9198929de35f559568f17dfd64 *openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
7f8cbc1b05c24c513befc47edf65599242bdb01353ab87dd8e1eaf4a396688c6 *version.buildinfo
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
