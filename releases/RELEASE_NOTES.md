# ZBT-Z8803BE OpenWrt main / kernel 6.18 release candidate

[English](RELEASE_NOTES.md) | [中文](RELEASE_NOTES.zh-CN.md)

> **Community build.** Maintained by a single contributor; expect rough edges. Bug reports and pull requests are welcome.

Custom OpenWrt build for the **ZBTLink ZBT-Z8803BE** WiFi 7 router.

- **Release tag:** `v25.12.5-zbt8803be-main6.18`
- **OpenWrt base:** current OpenWrt `main` / `r32860-f96b44fbd4`
- **Kernel:** `6.18.28`
- **Target:** `mediatek/filogic`
- **Default login:** `root` / `admin`

## What's new

### USB tethering failover

- **Android USB tethering is configured as a secondary WAN path.** USB Ethernet tether devices using `rndis_host`, `cdc_ether`, or `cdc_ncm` are detected by hotplug and assigned to `network.usb_tether`.
- **iPhone USB tethering packages are included.** The image now selects `kmod-usb-net-ipheth`, `usbmuxd`, `libimobiledevice`, `libimobiledevice-utils`, and `libusbmuxd-utils`.
- **Wired WAN remains preferred.** The default wired WAN interface keeps metric `10`; USB tethering uses metric `50`, so it is lower priority than wired WAN while still usable as failover.
- **First-boot and manual setup are included.** The image creates `network.usb_tether` on first boot, adds it to the firewall `wan` zone, enables `usbmuxd`, and includes `/usr/sbin/zbt-usb-tether-setup` for manual pairing/setup checks.

### OpenWrt main / kernel 6.18 rebase

- **Rebased firmware source onto OpenWrt main.** The ZBT-Z8803BE board support and custom package layer are now carried on top of current OpenWrt main instead of the older 25.12 branch.
- **MediaTek 6.18 kernel path.** The MediaTek target now uses `KERNEL_PATCHVER:=6.18`.
- **ZBT-Z8803BE image profile preserved.** The image profile remains `zbtlink_zbt-z8803be` with legacy `SUPPORTED_DEVICES += zbtlink,zbt-z8803be,mt7988a-nand` compatibility for older flashed images.
- **Custom firmware apps restored on the new base.** The build includes the previous custom app layer: About, Health, Temperature, Modem Events, Speedtest, WiFi Clients, Traffic Statistics / wrtbwmon, MLO tooling, QoSmate, autocore, and cpufreq.
- **AdGuard Home is now firmware-level.** Official prebuilt AdGuardHome APKs are embedded in the image and installed locally on first boot, then dnsmasq is wired to AdGuard on `127.0.0.1#5454` with the same DoH upstreams, filters, block rules, and allowlists used by the setup scripts.
- **LuCI `.format()` compatibility is cache-busted.** The image carries the `zbt_luci_format_compat3` formatter shim and `zbt_luci_compat3` revision suffix so current LuCI menu/view code using `_('...').format(...)` works after browser cache refresh.

### Board/DTS cleanup credited to Hauke's OpenWrt review

Thanks to [Hauke Mehrtens](https://github.com/hauke) for the latest review on [openwrt/openwrt#23053](https://github.com/openwrt/openwrt/pull/23053). This firmware applies the relevant board-support cleanups from that discussion:

- **NVMEM MAC cells.** Removed unnecessary explicit `0` indexes from `gmac0`, `gmac1`, and `gmac2` MAC references after Hauke clarified that indexes are only needed for `compatible = "mac-base"` providers with `#nvmem-cell-cells = <1>`: [comment](https://github.com/openwrt/openwrt/pull/23053#issuecomment-4450882616).
- **5G modem LEDs.** Replaced plain `label = "5g1"` / `label = "5g2"` LED nodes with standard `LED_FUNCTION_MOBILE` metadata and enumerators for the two modem status LEDs: [review comment](https://github.com/openwrt/openwrt/pull/23053#discussion_r3241518122).
- **Default WAN split.** Changed first-boot networking so only the 2.5G RJ45 port `eth1` is default WAN, while SFP+ `eth2` is exposed separately as inactive `wan_sfp` instead of being bridged into WAN: [review comment](https://github.com/openwrt/openwrt/pull/23053#discussion_r3241580300).
- **Unused fixed regulators.** Removed the unused fixed `regulator-1p8v` and `regulator-3p3v` nodes that were carried from the reference board but are not consumed by this DTS: [review comment](https://github.com/openwrt/openwrt/pull/23053#discussion_r3241532510).
- **Thermal fan map sanity.** Verified the CPU thermal fan cooling map/comment alignment following Hauke's review of the `level 3` / `<&fan 3 3>` mapping: [review comment](https://github.com/openwrt/openwrt/pull/23053#discussion_r3241527161).
- **Upstream DTS direction retained.** The DTS uses `mt7988a.dtsi` directly, keeps the upstream-compatible `compatible = "zbtlink,zbt-z8803be", "mediatek,mt7988a"` string, and keeps the OpenWrt LED/MAC aliases aligned with the current PR review direction.

## Validation status

- `./.buildenv/build.sh config` completed and wrote `.config`.
- Generated `.config` selects `CONFIG_TARGET_mediatek_filogic_DEVICE_zbtlink_zbt-z8803be=y`.
- Generated `.config` selects `CONFIG_LINUX_6_18=y`.
- Generated `.config` selects `CONFIG_PACKAGE_kmod-usb-net-ipheth=y`, `CONFIG_PACKAGE_usbmuxd=y`, `CONFIG_PACKAGE_libimobiledevice-utils=y`, and `CONFIG_PACKAGE_libusbmuxd-utils=y`.
- Full rebuild completed and artifacts were extracted to `output/mediatek/filogic`.
- Staged release assets passed `sha256sum -c sha256sums --ignore-missing`.
- Final manifest includes `kmod-usb-net-ipheth`, `usbmuxd`, `libimobiledevice`, `libimobiledevice-utils`, and `libusbmuxd-utils`.
- USB tethering scripts passed `sh -n` syntax checks before the rebuild.
- Sysupgrade squashfs contains `86-zbt-adguardhome-defaults`, `84-zbt-luci-js-compat`, and the embedded AdGuardHome APKs under `/usr/share/zbt/apk/`.
- Final manifest includes the custom app layer listed above, including MLO, QoSmate, autocore, cpufreq, wrtbwmon, and the ZBT LuCI apps.
- Live LuCI compat3 behavior was verified on 3FL before rebuild; the rebuilt image content was verified locally before publishing.

## Checksums

```text
1841812800da9039cab6ca0bd827f2462951c00e367b23650efe6770ac4dd7dd *config.buildinfo
ae37cfd49e2d7a9287a4efc424822e56abecfd427ce380655489a9614227f12e *feeds.buildinfo
31719cefe6ce1dad70670a0f3613e2f85c96311bb180453db1fbc40dfba9342e *openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
5253300b23ef2604d646a9982b448a0d2c41b02f320fd4a58c52e37525be719f *openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
0a83381413f1c9ff287317b5edc8fb771861d22590f28090b4f615a7d8a1026d *openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
08481bee00f9c0e2ad1019ee69589f92571e6129a86aaa6b93ce900e8939c3c1 *version.buildinfo
```

## Assets

Upload exactly these files after successful build and checksum verification:

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

## Flash plan

After manual approval, flash without preserving settings:

```sh
sysupgrade -n openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
```

Then run setup and restore DB/history files if doing a clean reflash.
