# ZBT-Z8803BE OpenWrt main / kernel 6.18.33 release

[English](RELEASE_NOTES.md) | [中文](RELEASE_NOTES.zh-CN.md)

Custom OpenWrt build for the **ZBTLink ZBT-Z8803BE** WiFi 7 router.

- **Release tag:** `v25.12.13-zbt8803be-main6.18`
- **Kernel:** `6.18.33`
- **Build revision:** `r34651-08fc94e13c`
- **Target:** `mediatek/filogic`
- **Default login:** `root` / `admin`

## What's new since v25.12.12

- **Added VPN/proxy/DPI-bypass kernel modules requested in GitHub issue #6.** The image now includes TPROXY, NFQUEUE, socket diagnostic, and BBR support for passwall/passwall2, sing-box, xray-core, OpenClash, podkop, zapret/nfqws, and hev-socks5-tproxy style setups.
- **No upstream rebase in this release.** This is a minimal rebuild on top of v25.12.12 with only the issue #6 kernel module package additions.

## Notes for PON SFP users

This release supports the router side of an ONU-in-SFP module: SFP cage detection, Ethernet link/PHY support, module EEPROM/DDM inspection, and MDIO/I2C diagnostics. It does **not** turn the router into a PON OLT, and it does not implement a software EPON/GPON MAC; the SFP stick must provide the ONU/PON function internally.

Useful diagnostics after inserting a compatible stick:

```sh
ethtool <sfp-netdev>
ethtool -m <sfp-netdev>
i2cdetect -l
i2csfp -h
mdio --help
```

## Validation

- Full Docker rebuild completed as `r34651-08fc94e13c` with kernel 6.18.33.
- `sha256sum -c sha256sums --ignore-missing` passed for staged assets.
- Manifest confirms `kmod-nft-tproxy`, `kmod-nft-socket`, `kmod-ipt-tproxy`, `kmod-nft-queue`, `kmod-nfnetlink-queue`, `kmod-ipt-nfqueue`, `kmod-inet-diag`, `kmod-netlink-diag`, and `kmod-tcp-bbr` are included for issue #6.
- Manifest includes:

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

## Checksums

```text
f226f8d9be2855d6fdb30a9a54e60f2cdc19028abecca8ba46262f184dfc5bc8 *config.buildinfo
ae37cfd49e2d7a9287a4efc424822e56abecfd427ce380655489a9614227f12e *feeds.buildinfo
9a63fca715067fe7c51f672deef83465131da860319cfa25965371907195cd00 *openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
a30435a9e3793aed02f2bd282d4d4fe014c933939a1b676d7f1c57c74bfb493f *openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
f0af9518d21cb47a2905a60f22df40b14d9b2f7924ad84200b98e9c5d13d886d *openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
2503f023144e11bb00097a4927c8af2cef1c7c8100685e3f97a99465211e006f *version.buildinfo
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
