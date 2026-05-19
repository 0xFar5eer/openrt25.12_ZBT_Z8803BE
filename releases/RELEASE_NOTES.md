# ZBT-Z8803BE OpenWrt main / kernel 6.18.31 release

[English](RELEASE_NOTES.md) | [中文](RELEASE_NOTES.zh-CN.md)

> **Community build.** Maintained by a single contributor; expect rough edges. Bug reports and pull requests are welcome.

Custom OpenWrt build for the **ZBTLink ZBT-Z8803BE** WiFi 7 router.

- **Release tag:** `v25.12.6-zbt8803be-main6.18`
- **OpenWrt base:** upstream `openwrt/openwrt` main HEAD `a7b5bb233f`
- **Kernel:** `6.18.31`
- **Build revision:** `r363-abb692387f`
- **Target:** `mediatek/filogic`
- **Default login:** `root` / `admin`

## What's new in this release

### Traffic accounting actually counts offloaded flows

- **wrtbwmon moved from `inet fw4` forward dispatch to `netdev wrtbwmon_acct` ingress + egress hooks at priority -300.** The new hooks run before fw4's flowtable, so software flow offload no longer bypasses per-device accounting. The previous build undercounted by 10x+ on offloaded LAN clients; this build closes the gap.
- **First-boot migration script `88-zbt-wrtbwmon-netdev-migrate` cleans up the legacy `inet fw4` chain set** and rewrites `NFT_TABLE` in the preserved `/etc/wrtbwmon.conf` so an upgrade from any older build wires itself to the new table automatically.
- **`/etc/wrtbwmon/` (the SQLite DB dir) is now registered in `/lib/upgrade/keep.d/wrtbwmon`** so the per-device traffic history survives sysupgrade without manual `/etc/sysupgrade.conf` edits on each router.
- **Three live-device bug fixes from the first reflash test** (see `fix(wrtbwmon): unbreak the netdev refactor on the live device` in the changelog): BusyBox `tr` does not parse `[:alnum:]` so chain names collided on `ap-mldN` devices, `sqlite_init` had inverted success/failure branches that left the init script permanently inactive, and the migration script now rewrites the preserved `NFT_TABLE` value before the new code touches nftables.

### Rebased onto upstream `openwrt/openwrt` main

- **Source rebased onto upstream OpenWrt main HEAD `a7b5bb233f`** (kernel 6.18.31), replacing the previous snapshot base.
- **Replay tooling: `.buildenv/replay-customizations.sh`** now lifts the ZBT-Z8803BE patch set onto any upstream snapshot deterministically. It seeds `./version`, drops a per-tree Docker volume in `.buildenv/local.env`, and audits for drift on every run.
- **Docker base pinned by manifest digest** in `.buildenv/Dockerfile` (`ubuntu:24.04@sha256:c4a8d5503dfb...`) so the build host does not silently follow Docker Hub re-tags.

### Carried forward from v25.12.5

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

- `./.buildenv/build.sh config` completed and wrote `.config` (config + feeds buildinfos stamped).
- Generated `.config` selects `CONFIG_TARGET_mediatek_filogic_DEVICE_zbtlink_zbt-z8803be=y`, `CONFIG_LINUX_6_18=y`, and `CONFIG_PACKAGE_kmod-nft-netdev=y`.
- Full rebuild completed (`r363-abb692387f`) and artifacts were extracted to `output/mediatek/filogic`.
- Staged release assets pass `sha256sum -c sha256sums --ignore-missing`.
- Final manifest includes the custom app layer (luci-app-zbt-{about,health,modem-events,speedtest,temperature,wifi-clients}, luci-app-mlo, luci-app-wrtbwmon, qosmate + luci-app-qosmate, autocore, cpufreq, luci-theme-argon + luci-app-argon-config), plus the modem stack (qmodem + luci-app-qmodem-{monitor,next}, kmod-usb-serial-{option,qualcomm,wwan}) and the USB tethering stack (kmod-usb-net-ipheth, usbmuxd, libimobiledevice, libimobiledevice-utils, libusbmuxd-utils).
- Sysupgrade squashfs contains the branded MOTD banner, the ImmortalWrt APK signing key, AdGuardHome + LuCI app APKs staged under `/usr/share/zbt/apk/`, all 26 ZBT uci-default scripts (incl. `88-zbt-wrtbwmon-netdev-migrate`), all hotplug glue, and the 12 `/usr/sbin/zbt-*` helpers.
- Flash-tested on `3fl.lan`: after `sysupgrade` the netdev table `wrtbwmon_acct` came up with 22 ingress+egress chains across `ap-mld{0,1,2}`, `lan{0,1,2}`, and `phy0.{0,1}-apN`. Per-device counters were observed incrementing under live traffic and the preserved `traffic.db` (2.5M, 6 devices today) survived the reflash intact.

## Checksums

```text
5132da1cdd420bb0b3b0891406be2b830d0518435ff9dbfb767454176c9bda85 *config.buildinfo
ae37cfd49e2d7a9287a4efc424822e56abecfd427ce380655489a9614227f12e *feeds.buildinfo
73bd990b5d28d3b41c2a810614315e30e3dc1d67ad2df5f199639166603d6686 *openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
f8dff652e42cba5dcfd6dcc33ca5541c00ec6a81b44bdbe8383c928396d9c5d2 *openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
8dec48f3335c89261da766ebd3ac93b39f7bcd85ba8c6bee9b8b76b72cc94fac *openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
05ac68fd62126cfe75fb4d8280382f7a5bec4cc1d6df5979b6d8a4b4c5d02d98 *version.buildinfo
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

For an in-place upgrade that preserves UCI config and per-device traffic history:

```sh
scp openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin root@<router>:/tmp/
ssh root@<router> 'sysupgrade -v /tmp/openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin'
```

`/etc/wrtbwmon/` and `/etc/wrtbwmon.conf` are auto-preserved by `/lib/upgrade/keep.d/wrtbwmon` shipped with this build; older builds need `/etc/wrtbwmon` and `/etc/wifihistory` added to `/etc/sysupgrade.conf` before flashing.

For a clean reset (no settings carried over):

```sh
sysupgrade -n openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
```
