# ZBT-Z8803BE OpenWrt main / kernel 6.18.33 正式版

[English](RELEASE_NOTES.md) | [中文](RELEASE_NOTES.zh-CN.md)

面向 **ZBTLink ZBT-Z8803BE** WiFi 7 路由器的自定义 OpenWrt 固件。

- **发布标签:** `v25.12.14-zbt8803be-main6.18`
- **内核:** `6.18.33`
- **构建版本号:** `r34651-08fc94e13c`
- **目标平台:** `mediatek/filogic`
- **默认登录:** `root` / `admin`

## 相比 v25.12.13 的变化

- **rebase 到更新的 OpenWrt upstream main，** 同时继续保持内核 **6.18.33**，并在新的上游基线之上重新构建 ZBT-Z8803BE 固件。
- **保留上一版为 GitHub issue #6 增加的 VPN/代理/DPI 绕过内核模块：** TPROXY、NFQUEUE、socket diagnostic 与 BBR，适配 passwall/passwall2、sing-box、xray-core、OpenClash、podkop、zapret/nfqws、hev-socks5-tproxy 等场景。
- **增强了重复 rebase / rebuild 的构建稳定性。** 本地 `.buildenv` helper 现在会在每次运行时从 seed 文件重新生成 `.config`，并移除当前会破坏包元数据生成的 feed 包 `openvswitch` 与 `jool`。

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

- rebased 分支上已完成完整 Docker rebuild：`r34651-08fc94e13c`，内核 6.18.33。
- release 资产是在 `zbt8803be-openwrt-main` rebase 到更新的 `openwrt-upstream/main` 之后重新生成的。
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
6f5cb43f6219fa6f111fbf8c1ae4171bc3577da67fcb9dc6aa035e19c2d414bd *config.buildinfo
ae37cfd49e2d7a9287a4efc424822e56abecfd427ce380655489a9614227f12e *feeds.buildinfo
a9c2eea2b567b3a61004981bb94a82f1df029bb289a4c24f6c1a60a1dccae703 *openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
6844a0ce39a8f7e19ab188d0e1eafae8116fb790fec00a587bda4278ee3b2b86 *openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
90a1dee715024cf8ae6b75b40b3f3d772a4f52a667585a58af8fede4fd462d94 *openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
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
