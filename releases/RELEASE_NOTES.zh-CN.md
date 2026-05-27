# ZBT-Z8803BE OpenWrt main / kernel 6.18.33 正式版

[English](RELEASE_NOTES.md) | [中文](RELEASE_NOTES.zh-CN.md)

面向 **ZBTLink ZBT-Z8803BE** WiFi 7 路由器的自定义 OpenWrt 固件。

- **发布标签:** `v25.12.13-zbt8803be-main6.18`
- **内核:** `6.18.33`
- **构建版本号:** `r34651-08fc94e13c`
- **目标平台:** `mediatek/filogic`
- **默认登录:** `root` / `admin`

## 相比 v25.12.12 的变化

- **新增 GitHub issue #6 请求的 VPN/代理/DPI 绕过内核模块。** 固件现在包含 TPROXY、NFQUEUE、socket diagnostic 与 BBR 支持，适配 passwall/passwall2、sing-box、xray-core、OpenClash、podkop、zapret/nfqws、hev-socks5-tproxy 等场景。
- **本版本没有重新 rebase 上游。** 这是基于 v25.12.12 的最小重构建，只加入 issue #6 请求的内核模块包。

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

- 完整 Docker rebuild 已完成：`r34651-08fc94e13c`，内核 6.18.33。
- staged release assets 通过 `sha256sum -c sha256sums --ignore-missing`。
- manifest 确认包含 `kmod-nft-tproxy`、`kmod-nft-socket`、`kmod-ipt-tproxy`、`kmod-nft-queue`、`kmod-nfnetlink-queue`、`kmod-ipt-nfqueue`、`kmod-inet-diag`、`kmod-netlink-diag`、`kmod-tcp-bbr`，对应 issue #6。
- manifest 包含：

```text
kernel - 6.18.33~b5bed36ea0c8dbdc37cedd79a92febea-r1
kmod-inet-diag - 6.18.33-r1
kmod-ipt-nfqueue - 6.18.33-r1
kmod-ipt-tproxy - 6.18.33-r1
kmod-netlink-diag - 6.18.33-r1
kmod-nfnetlink-queue - 6.18.33-r1
kmod-nft-queue - 6.18.33-r1
kmod-nft-socket - 6.18.33-r1
kmod-nft-tproxy - 6.18.33-r1
kmod-tcp-bbr - 6.18.33-r1
kmod-tun - 6.18.33-r1
```

## 校验值

```text
f226f8d9be2855d6fdb30a9a54e60f2cdc19028abecca8ba46262f184dfc5bc8 *config.buildinfo
ae37cfd49e2d7a9287a4efc424822e56abecfd427ce380655489a9614227f12e *feeds.buildinfo
9a63fca715067fe7c51f672deef83465131da860319cfa25965371907195cd00 *openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
a30435a9e3793aed02f2bd282d4d4fe014c933939a1b676d7f1c57c74bfb493f *openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
f0af9518d21cb47a2905a60f22df40b14d9b2f7924ad84200b98e9c5d13d886d *openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
2503f023144e11bb00097a4927c8af2cef1c7c8100685e3f97a99465211e006f *version.buildinfo
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
