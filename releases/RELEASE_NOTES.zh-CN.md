# ZBT-Z8803BE OpenWrt v25.12.2-4-zbt8803be 维护版

[English](RELEASE_NOTES.md) | [中文](RELEASE_NOTES.zh-CN.md)

> **社区版本。** 由个人独立维护，难免存在 bug 与粗糙之处，欢迎提交 Issue 与 PR。

面向 **ZBTLink ZBT-Z8803BE** WiFi 7 路由器的自定义 OpenWrt 固件。

- **发布标签:** `v25.12.2-4-zbt8803be`
- **OpenWrt 基线:** 官方 `v25.12.2` / `r32802-f505120278`
- **内核:** `6.12.74`
- **目标平台:** `mediatek/filogic`
- **默认登录:** `root` / `admin`

## 相比 `v25.12.2-3-zbt8803be` 的变化

- **修复有线 MAC 分配。** DTS 为 `gmac0`、`gmac1`、`gmac2` 的有线接口显式传入 NVMEM cell 索引，回应 OpenWrt PR `#23053` 中 `@joelinux60` 对 [`gmac0`](https://github.com/openwrt/openwrt/pull/23053#discussion_r3206902888)、[`gmac1`](https://github.com/openwrt/openwrt/pull/23053#discussion_r3206909949)、[`gmac2`](https://github.com/openwrt/openwrt/pull/23053#discussion_r3206915357) 的 review comments。

## 验证

- DTS 修改通过 `git diff --check`。
- LuCI About JavaScript 通过 `node --check`。
- 固件已从当前发布分支重新构建并提取到 `output/mediatek/filogic`。

## 校验值

```text
b77564da2e70eead5b8a3dc554c0be8bd2e32c162d9cad9713c89b9191f714cf  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
845c4e33127aa28c2d15ef7fe29c4a1abbc19205432d387dd9df2b02adb77d1c  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
d1657eba3df03621517132b396c5a0bcdbc44d86fe3c0c91f3743140e8108dee  openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
63398546ed712f52f82d199fa1911e646573292b83de268217a3c256d9a094e2  sha256sums
0d1ac3f38d93e39e61e064f4f14062918333ba99a5e8fe1ac7c8c805101623d2  config.buildinfo
ae37cfd49e2d7a9287a4efc424822e56abecfd427ce380655489a9614227f12e  feeds.buildinfo
05f6cea7ac9e5c3d2d73225400b4dc3cf51eb8002f54cf6d05e5934c1805c60c  version.buildinfo
```

## 发布文件

上传以下文件：

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

## 刷机

从现有 OpenWrt 升级：

```sh
sysupgrade openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
```

清空配置刷机：

```sh
sysupgrade -n openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
```
