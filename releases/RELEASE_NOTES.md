# ZBT-Z8803BE OpenWrt main / kernel 6.18.32 release

[English](RELEASE_NOTES.md) | [中文](RELEASE_NOTES.zh-CN.md)

Custom OpenWrt build for the **ZBTLink ZBT-Z8803BE** WiFi 7 router.

- **Release tag:** `v25.12.9-zbt8803be-main6.18`
- **Kernel:** `6.18.32`
- **Build revision:** `r32875-81ca4b3ca4`
- **Target:** `mediatek/filogic`
- **Default login:** `root` / `admin`

## What's new since v25.12.8

- **Added `install` utility from coreutils.** The `coreutils-install` package is now included in the firmware, providing the standard POSIX `install` command for easier file installation and setup scripting.
- **Simplified WiFi Clients MLD display.** The WiFi Clients LuCI page now shows only the MLD-capable label, link count, and active bands. Redundant 6 GHz signal and TX rate information has been removed from the MLD column for a cleaner UI.

## Validation

- Full Docker rebuild completed as `r32875-81ca4b3ca4` with kernel 6.18.32, coreutils-install, and simplified WiFi Clients UI.
- `sha256sum -c sha256sums --ignore-missing` passed for staged assets.
- Manifest confirms `coreutils-install`, `usteer`, and `luci-app-usteer` are included.
- Manifest includes:

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

## Checksums

```text
3c125a4565c4643d3802dd31692119cc3173dc4983da4a894ea83cc10916907b *config.buildinfo
ae37cfd49e2d7a9287a4efc424822e56abecfd427ce380655489a9614227f12e *feeds.buildinfo
0b49dedd2490c63bfdfc9936ae44ed33377a4d8ad3e161d25e324690c9427382 *openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
7f3364eb9a34417ad26795c6759365011347facd79bc8b2712cc0a4a7e949caf *openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
c3c45aae9ff40ec861df9bcad0b3e65111fa372fe93301b32eccb1a6e4e80ee9 *openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
2a9c14559ba2743187a21e3e521b08b1f0b95e3773df0aeae6404892b25b0023 *version.buildinfo
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
