# ZBT-Z8803BE OpenWrt main / kernel 6.18.28 正式版

[English](RELEASE_NOTES.md) | [中文](RELEASE_NOTES.zh-CN.md)

面向 **ZBTLink ZBT-Z8803BE** WiFi 7 路由器的自定义 OpenWrt 固件。

- **发布标签:** `v25.12.8-zbt8803be-main6.18`
- **内核:** `6.18.28`
- **构建版本号:** `r32875-11fafa0ecd`
- **目标平台:** `mediatek/filogic`
- **默认登录:** `root` / `admin`

## 相比 v25.12.7 的变化

- **移除固件文档/配置路径中的 crash-forensics。** 公开镜像和固件配置不再保留过期的 `zbt-crash-forensics` 引用。
- **更新 Traffic Statistics 提示。** wrtbwmon 的 LuCI 设置页面现在会提示：按客户端 nftables 计数在某些路由器上可能降低 Internet/LAN 吞吐；建议只在需要排查哪个客户端、域名或总流量过高时临时启用，用完再关闭。
- **崩溃根因按电源/电压问题处理。** 私有 setup 和 live router 上的 crash-forensics 已移除，因为该崩溃调查不再需要。

## 验证

- 完整 Docker rebuild 已完成：`r32875-11fafa0ecd`；期间清理了 Docker 磁盘空间，并重建了受中断影响的 Python host PGO 产物。
- staged release assets 通过 `sha256sum -c sha256sums --ignore-missing`。
- manifest/config 扫描确认没有 `zbt-crash`、`zbt_crash` 或 `crash-forensics` 引用。
- manifest 包含：

```text
kernel - 6.18.28~1d3ce6949449162367278daa4d610965-r1
kmod-nft-netdev - 6.18.28-r1
kmod-phy-aquantia - 6.18.28-r1
wrtbwmon - 0.36-r1
luci-app-wrtbwmon - 2.0.13-r1
```

## 校验值

```text
4d913f988401ac01e6c989d1ae07b31b316a143cbdc625b8d6164da1444bf410 *config.buildinfo
ae37cfd49e2d7a9287a4efc424822e56abecfd427ce380655489a9614227f12e *feeds.buildinfo
373d7a4c3cf2994fec81e5fb36659beccec74371e807ee6bb3ba2d54b8c1e82c *openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
b3075c2e2b93ccab8e4f4c1d959387cfb346c412e8f4a3ffd31ecbce9fb4e831 *openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
64005a4f4609cf35481b198c0a345107326114aa4a1cddbd0b4dd8203b78e703 *openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
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
