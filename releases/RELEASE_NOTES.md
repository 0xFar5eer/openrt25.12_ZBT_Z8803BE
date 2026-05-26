# ZBT-Z8803BE OpenWrt main / kernel 6.18.32 release

[English](RELEASE_NOTES.md) | [中文](RELEASE_NOTES.zh-CN.md)

Custom OpenWrt build for the **ZBTLink ZBT-Z8803BE** WiFi 7 router.

- **Release tag:** `v25.12.11-zbt8803be-main6.18`
- **Kernel:** `6.18.32`
- **Build revision:** `r32886-ff65d053dc`
- **Target:** `mediatek/filogic`
- **Default login:** `root` / `admin`

## What's new since v25.12.10

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

- Full Docker rebuild completed as `r32886-ff65d053dc` with kernel 6.18.32.
- `sha256sum -c sha256sums --ignore-missing` passed for staged assets.
- Manifest confirms `kmod-tun`, `i2c-tools`, `i2csfp`, `mdio-tools`, `mii-tool`, `kmod-mdio-netlink`, `kmod-sfp`, and `kmod-phy-aquantia` are included.
- Manifest includes:

```text
kernel - 6.18.32~c855ebc1035e17e215441b25f3daa05d-r1
kmod-tun - 6.18.32-r1
i2c-tools - 4.4-r2
i2csfp - 2025.08.05~1b9b4e0f-r1
mdio-tools - 1.3.1-r3
mii-tool - 2.10-r2
kmod-mdio-netlink - 6.18.32.1.3.1-r2
kmod-sfp - 6.18.32-r1
kmod-phy-aquantia - 6.18.32-r1
ethtool - 6.19-r2
ip-full - 6.18.0-r2
```

## Checksums

```text
73ebcffff91ae63a33da0d7c5a7c8b169ac8d9c830cdebc6b018568cd3ad7a0e *config.buildinfo
ae37cfd49e2d7a9287a4efc424822e56abecfd427ce380655489a9614227f12e *feeds.buildinfo
8b8af9f7b299c7f6dd1113b8109c56c6e8d9f380a13fe4771ae266c988eb5cf0 *openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
1d6bc473063f8236863a8a0af1f5d21bd7f8fc11c201950007b8b0c1260d5b5e *openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
513bfbbbd1fec05ad6e01e4fb8da09dd203cbd9198929de35f559568f17dfd64 *openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
7f8cbc1b05c24c513befc47edf65599242bdb01353ab87dd8e1eaf4a396688c6 *version.buildinfo
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
