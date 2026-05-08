# ZBT-Z8803BE OpenWrt v25.12.2-4-zbt8803be maintenance release

[English](RELEASE_NOTES.md) | [中文](RELEASE_NOTES.zh-CN.md)

> **Community build.** Maintained by a single contributor; expect rough edges. Bug reports and pull requests are welcome.

Custom OpenWrt build for the **ZBTLink ZBT-Z8803BE** WiFi 7 router.

- **Release tag:** `v25.12.2-4-zbt8803be`
- **OpenWrt base:** official `v25.12.2` / `r32802-f505120278`
- **Kernel:** `6.12.74`
- **Target:** `mediatek/filogic`
- **Default login:** `root` / `admin`

## What's new since `v25.12.2-3-zbt8803be`

- **Wired MAC assignment fix.** DTS wired interfaces now pass an explicit NVMEM cell index for `gmac0`, `gmac1`, and `gmac2`, addressing OpenWrt PR `#23053` review comments from `@joelinux60` for [`gmac0`](https://github.com/openwrt/openwrt/pull/23053#discussion_r3206902888), [`gmac1`](https://github.com/openwrt/openwrt/pull/23053#discussion_r3206909949), and [`gmac2`](https://github.com/openwrt/openwrt/pull/23053#discussion_r3206915357).

## Validation

- DTS change passed `git diff --check`.
- LuCI About JavaScript passed `node --check`.
- Firmware was rebuilt from this release branch and extracted to `output/mediatek/filogic`.

## Checksums

```text
b77564da2e70eead5b8a3dc554c0be8bd2e32c162d9cad9713c89b9191f714cf  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
845c4e33127aa28c2d15ef7fe29c4a1abbc19205432d387dd9df2b02adb77d1c  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
d1657eba3df03621517132b396c5a0bcdbc44d86fe3c0c91f3743140e8108dee  openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
63398546ed712f52f82d199fa1911e646573292b83de268217a3c256d9a094e2  sha256sums
0d1ac3f38d93e39e61e064f4f14062918333ba99a5e8fe1ac7c8c805101623d2  config.buildinfo
ae37cfd49e2d7a9287a4efc424822e56abecfd427ce380655489a9614227f12e  feeds.buildinfo
05f6cea7ac9e5c3d2d73225400b4dc3cf51eb8002f54cf6d05e5934c1805c60c  version.buildinfo
```

## Assets

Upload exactly these files:

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

## Flash

Existing OpenWrt:

```sh
sysupgrade openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
```

Clean reset:

```sh
sysupgrade -n openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
```
