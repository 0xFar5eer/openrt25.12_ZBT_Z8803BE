# ZBT-Z8803BE OpenWrt main / kernel 6.18.33 release

[English](RELEASE_NOTES.md) | [中文](RELEASE_NOTES.zh-CN.md)

Custom OpenWrt build for the **ZBTLink ZBT-Z8803BE** WiFi 7 router.

- **Release tag:** `v25.12.14-zbt8803be-main6.18`
- **Kernel:** `6.18.33`
- **Build revision:** `r34651-08fc94e13c`
- **Target:** `mediatek/filogic`
- **Default login:** `root` / `admin`

## What's new since v25.12.13

- **Rebased onto newer OpenWrt upstream main** while staying on kernel **6.18.33**, then rebuilt the ZBT-Z8803BE image stack on top of that newer base.
- **Retains the issue #6 VPN/proxy/DPI-bypass kernel modules** added in the previous release: TPROXY, NFQUEUE, socket diagnostic, and BBR support for passwall/passwall2, sing-box, xray-core, OpenClash, podkop, zapret/nfqws, and hev-socks5-tproxy style setups.
- **Build flow hardened for repeatable rebases/rebuilds.** The local `.buildenv` helper now regenerates `.config` cleanly from the seed file each run and prunes incompatible feed packages (`openvswitch`, `jool`) that currently break package metadata generation in this tree.

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

- Full Docker rebuild completed on the rebased branch as `r34651-08fc94e13c` with kernel 6.18.33.
- Release artifacts were rebuilt after rebasing `zbt8803be-openwrt-main` onto newer `openwrt-upstream/main`.
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
6f5cb43f6219fa6f111fbf8c1ae4171bc3577da67fcb9dc6aa035e19c2d414bd *config.buildinfo
ae37cfd49e2d7a9287a4efc424822e56abecfd427ce380655489a9614227f12e *feeds.buildinfo
a9c2eea2b567b3a61004981bb94a82f1df029bb289a4c24f6c1a60a1dccae703 *openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
6844a0ce39a8f7e19ab188d0e1eafae8116fb790fec00a587bda4278ee3b2b86 *openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
90a1dee715024cf8ae6b75b40b3f3d772a4f52a667585a58af8fede4fd462d94 *openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
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
