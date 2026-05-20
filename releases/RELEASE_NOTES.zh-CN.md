# ZBT-Z8803BE OpenWrt main / kernel 6.18.32 正式版

[English](RELEASE_NOTES.md) | [中文](RELEASE_NOTES.zh-CN.md)

面向 **ZBTLink ZBT-Z8803BE** WiFi 7 路由器的自定义 OpenWrt 固件。

- **发布标签:** `v25.12.9-zbt8803be-main6.18`
- **内核:** `6.18.32`
- **构建版本号:** `r32875-81ca4b3ca4`
- **目标平台:** `mediatek/filogic`
- **默认登录:** `root` / `admin`

## 相比 v25.12.8 的变化

- **添加 `install` 工具。** 固件现在包含 `coreutils-install` 包，提供标准 POSIX `install` 命令，便于文件安装和 setup 脚本。
- **简化 WiFi Clients MLD 显示。** WiFi Clients LuCI 页面现在只显示 MLD-capable 标签、链接数和活动频段。MLD 列中移除了冗余的 6 GHz 信号和 TX 速率信息，界面更简洁。

## 验证

- 完整 Docker rebuild 已完成：`r32875-81ca4b3ca4`；内核升级至 6.18.32，包含 coreutils-install 和简化的 WiFi Clients UI。
- staged release assets 通过 `sha256sum -c sha256sums --ignore-missing`。
- manifest 确认包含 `coreutils-install`、`usteer` 和 `luci-app-usteer`。
- manifest 包含：

```text
kernel - 6.18.32~1d3ce6949449162367278daa4d610965-r1
kmod-nft-netdev - 6.18.32-r1
kmod-phy-aquantia - 6.18.32-r1
coreutils-install - 9.9-r2
usteer - 2025.10.04~1d6524c6-r1
luci-app-usteer - 26.120.35050~a611522
wrtbwmon - 0.36-r1
luci-app-wrtbwmon - 2.0.13-r1
```

## 校验值

```text
3c125a4565c4643d3802dd31692119cc3173dc4983da4a894ea83cc10916907b *config.buildinfo
ae37cfd49e2d7a9287a4efc424822e56abecfd427ce380655489a9614227f12e *feeds.buildinfo
0b49dedd2490c63bfdfc9936ae44ed33377a4d8ad3e161d25e324690c9427382 *openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
7f3364eb9a34417ad26795c6759365011347facd79bc8b2712cc0a4a7e949caf *openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
c3c45aae9ff40ec861df9bcad0b3e65111fa372fe93301b32eccb1a6e4e80ee9 *openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
2a9c14559ba2743187a21e3e521b08b1f0b95e3773df0aeae6404892b25b0023 *version.buildinfo
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
