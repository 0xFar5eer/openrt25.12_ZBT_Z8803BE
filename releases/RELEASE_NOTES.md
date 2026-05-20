# ZBT-Z8803BE OpenWrt main / kernel 6.18.28 release

[English](RELEASE_NOTES.md) | [中文](RELEASE_NOTES.zh-CN.md)

Custom OpenWrt build for the **ZBTLink ZBT-Z8803BE** WiFi 7 router.

- **Release tag:** `v25.12.9-zbt8803be-main6.18`
- **Kernel:** `6.18.28`
- **Build revision:** `r32875-30cfe28ac8`
- **Target:** `mediatek/filogic`
- **Default login:** `root` / `admin`

## What's new since v25.12.8

- **Added `install` utility from coreutils.** The `coreutils-install` package is now included in the firmware, providing the standard POSIX `install` command for easier file installation and setup scripting.
- **Simplified WiFi Clients MLD display.** The WiFi Clients LuCI page now shows only the MLD-capable label, link count, and active bands. Redundant 6 GHz signal and TX rate information has been removed from the MLD column for a cleaner UI.
- **Added usteer configuration to setup scripts.** Both the main router setup (`013-wifi.sh`) and AP bootstrap (`ap-bootstrap.sh`) now explicitly configure and enable usteer with conservative settings for roaming and band steering across the main SSID.

## Validation

- Full Docker rebuild completed as `r32875-30cfe28ac8` with usteer, coreutils-install, and simplified WiFi Clients UI.
- `sha256sum -c sha256sums --ignore-missing` passed for staged assets.
- Manifest confirms `coreutils-install`, `usteer`, and `luci-app-usteer` are included.
- Manifest includes:

```text
kernel - 6.18.28~1d3ce6949449162367278daa4d610965-r1
kmod-nft-netdev - 6.18.28-r1
kmod-phy-aquantia - 6.18.28-r1
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
b166db87d158f1d7fe939dffe50796d893f52dd24969d1acc627f32154d00446 *openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
fbe2fbb8eabcd54bc5e94ecf7869a75be87b960761bdeff782695d7223ca81a2 *openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
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
