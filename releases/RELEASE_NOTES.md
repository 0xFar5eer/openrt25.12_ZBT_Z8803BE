# ZBT-Z8803BE OpenWrt main / kernel 6.18.31 release

[English](RELEASE_NOTES.md) | [中文](RELEASE_NOTES.zh-CN.md)

Custom OpenWrt build for the **ZBTLink ZBT-Z8803BE** WiFi 7 router.

- **Release tag:** `v25.12.7-zbt8803be-main6.18`
- **OpenWrt base:** upstream `openwrt/openwrt` main HEAD `a7b5bb233f`
- **Kernel:** `6.18.31`
- **Build revision:** `r364-8682ae2528`
- **Target:** `mediatek/filogic`
- **Default login:** `root` / `admin`

## What's new since v25.12.6

- **Fixed GitHub source tarball builds.** `.buildenv/build.sh` now creates a safe `./version` before `config`, `download`, or `build` when the file is missing, avoiding the apk error caused by invalid versions such as `260516.34671 unknown`.
- **Added Aquantia/Marvell 10G SFP+ PHY support.** `kmod-phy-aquantia` is now built into the image for AQR113C and related Aquantia PHY SFP+ modules.

No OpenWrt base, kernel, or wrtbwmon netdev behavior changed from v25.12.6.

## Validation

- Full rebuild completed as `r364-8682ae2528`.
- `sha256sum -c sha256sums --ignore-missing` passed for staged assets.
- Manifest includes:

```text
kmod-phy-aquantia - 6.18.31-r1
kmod-nft-netdev - 6.18.31-r1
wrtbwmon - 0.36-r1
```

## Checksums

```text
4d913f988401ac01e6c989d1ae07b31b316a143cbdc625b8d6164da1444bf410 *config.buildinfo
ae37cfd49e2d7a9287a4efc424822e56abecfd427ce380655489a9614227f12e *feeds.buildinfo
df09cbf8c926e73eb15b43d057b2ae7b850b47aa15b7e5c365736d409211923b *openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
71984653705e0a1af73a3fc74521bb1e76488f0991d7a478254aae5f40a17a4d *openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
a58f638fcd670ba302e810501a6470544cab4f8f1b318595e7e26a2e2fde8a52 *openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
cf7f42d03a5adbb0b72b4444da0b8c467b360389639bb01c81442761212a7b32 *version.buildinfo
```

## Flash

Preserve settings and app history:

```sh
scp openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin root@<router>:/tmp/
ssh root@<router> 'sysupgrade -v /tmp/openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin'
```

Clean reset:

```sh
sysupgrade -n openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
```
