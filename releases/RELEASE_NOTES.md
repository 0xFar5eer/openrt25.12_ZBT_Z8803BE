# ZBT-Z8803BE OpenWrt main / kernel 6.18.33 release

[English](RELEASE_NOTES.md) | [中文](RELEASE_NOTES.zh-CN.md)

Custom OpenWrt build for the **ZBTLink ZBT-Z8803BE** WiFi 7 router.

- **Release tag:** `v25.12.12-zbt8803be-main6.18`
- **Kernel:** `6.18.33`
- **Build revision:** `r1-81fde127a8`
- **Target:** `mediatek/filogic`
- **Default login:** `root` / `admin`

## What's new since v25.12.11

- **Rebased onto latest upstream OpenWrt main with kernel 6.18.33.** Local ZBT-Z8803BE customizations were replayed onto the refreshed upstream tree and rebuilt from the new base.
- **Added TUN/TAP support for userspace VPN and proxy tools.** The image now includes `kmod-tun`, providing `/dev/net/tun` for tools such as sing-box, xray-core, OpenVPN, wireguard-go, and podkop. This addresses GitHub issue #5.
- **Added SFP/optical diagnostic tooling for ONU-in-SFP sticks.** The image now includes `i2c-tools`, `i2csfp`, `mdio-tools`, and `mii-tool` alongside existing `kmod-sfp`, `kmod-phy-aquantia`, `ethtool`, and `ip-full` support. This is intended for SC/UPC or SC/APC GPON/EPON ONU SFP modules with onboard PON MAC/OMCI logic and SFF-8472 digital diagnostics.

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

- Full Docker rebuild completed as `r1-81fde127a8` with kernel 6.18.33.
- `sha256sum -c sha256sums --ignore-missing` passed for staged assets.
- Manifest confirms `kmod-tun`, `i2c-tools`, `i2csfp`, `mdio-tools`, `mii-tool`, `kmod-mdio-netlink`, `kmod-sfp`, and `kmod-phy-aquantia` are included.
- Manifest includes:

```text
kernel - 6.18.33~f20f4bdfe29c23a826260e96eee4651d-r1
kmod-tun - 6.18.33-r1
i2c-tools - 4.4-r2
i2csfp - 2025.08.05~1b9b4e0f-r1
mdio-tools - 1.3.1-r3
mii-tool - 2.10-r2
kmod-mdio-netlink - 6.18.33.1.3.1-r2
kmod-sfp - 6.18.33-r1
kmod-phy-aquantia - 6.18.33-r1
ethtool - 6.19-r2
ip-full - 6.18.0-r2
```

## Checksums

```text
73ebcffff91ae63a33da0d7c5a7c8b169ac8d9c830cdebc6b018568cd3ad7a0e *config.buildinfo
ae37cfd49e2d7a9287a4efc424822e56abecfd427ce380655489a9614227f12e *feeds.buildinfo
b5d0540d1d4e5dab3df034652ed704345fbbfce46a4a49b9643a95294c8d3683 *openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
b05d102c3da12bd255ed4668d55a7581978ad30f7c9d65ea366fd120afd92e17 *openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
0839cf21f4aa61c4ec13a948d18504ea24ca6b790a995dac22a672c40eb85ce7 *openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
b3c49ceec35c43f20da3896afc728e569df7c1ace68d820759535c14c95d46b3 *version.buildinfo
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
