# ZBT-Z8803BE OpenWrt main / kernel 6.18.34 正式版

[English](RELEASE_NOTES.md) | [中文](RELEASE_NOTES.zh-CN.md)

面向 **ZBTLink ZBT-Z8803BE** WiFi 7 路由器的自定义 OpenWrt 固件。

- **发布标签:** `v25.12.016`
- **内核:** `6.18.34`
- **构建版本号:** `r34764-819875e2d1`
- **目标平台:** `mediatek/filogic`
- **默认登录:** `root` / `admin`

## 本次版本更新

- **解决 GitHub issue #7 提到的 SFP 作为 WAN 默认行为问题。**
- **保留 `eth1` 为 RJ45 WAN，`eth2` 为 SFP WAN。**
- **两个有线上联现在都会在首次启动时自动生效，且 IPv4/IPv6 默认配置一致。**
- **如果两个有线上联同时接入，默认按路由 metric 优先使用 SFP，RJ45 作为回退。**
- **`wan_sfp` 与 `wan_sfp6` 默认加入 firewall 的 `wan` zone。**
- **原有确定性 DNS 策略和高 metric 的蜂窝回退逻辑保持不变。**

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

- 已完成完整 Docker rebuild：`r34764-819875e2d1`，内核 6.18.34。
- 已补齐 `wan` / `wan6` 与 `wan_sfp` / `wan_sfp6` 的首次启动 metric 默认值。
- 已确保 `wan6` 与 `wan_sfp6` 在旧配置缺失时也会自动创建。
- 已补充双有线 WAN 首次启动验证说明。
- manifest 包含：

```text
kernel - 6.18.34~b5bed36ea0c8dbdc37cedd79a92febea-r1
kmod-phy-aquantia - 6.18.34-r1
kmod-sfp - 6.18.34-r1
```

## 校验值

```text
f226f8d9be2855d6fdb30a9a54e60f2cdc19028abecca8ba46262f184dfc5bc8 *config.buildinfo
ae37cfd49e2d7a9287a4efc424822e56abecfd427ce380655489a9614227f12e *feeds.buildinfo
6b417afd3de82f06d8279f9748e9dd135168b0deeefb8f571c02288af1687f3b *openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
563436090b583af71c60abaff86d08dadc048ab4ab45479acc96aa967d2d4c5d *openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
8f6ed9bfc98222735d883fab1c0f6c31bfac0fad0dd5ff928d32eae877bd2072 *openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
4b36ec5747ddf223b41ddf41f84e631882f8db2f9ba449ef4cf336f4bfe42465 *version.buildinfo
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
