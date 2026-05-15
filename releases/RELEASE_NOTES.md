# ZBT-Z8803BE OpenWrt main / kernel 6.18 release candidate

[English](RELEASE_NOTES.md) | [中文](RELEASE_NOTES.zh-CN.md)

> **Community build.** Maintained by a single contributor; expect rough edges. Bug reports and pull requests are welcome.

Custom OpenWrt build for the **ZBTLink ZBT-Z8803BE** WiFi 7 router.

- **Release tag:** `v25.12.4-zbt8803be-main6.18`
- **OpenWrt base:** current OpenWrt `main` / `r303+1-d841179375`
- **Kernel:** `6.18.28`
- **Target:** `mediatek/filogic`
- **Default login:** `root` / `admin`

## What's new

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
- Full rebuild completed and artifacts were extracted to `output/mediatek/filogic`.
- Staged release assets passed `sha256sum -c sha256sums --ignore-missing`.
- Sysupgrade squashfs contains `86-zbt-adguardhome-defaults`, `84-zbt-luci-js-compat`, and the embedded AdGuardHome APKs under `/usr/share/zbt/apk/`.
- Final manifest includes the custom app layer listed above, including MLO, QoSmate, autocore, cpufreq, wrtbwmon, and the ZBT LuCI apps.
- Live LuCI compat3 behavior was verified on 3FL before rebuild; the rebuilt image content was verified locally before publishing.

## Checksums

```text
291d52d106f823bb129b0d007b3f7a3fa79bafaac41cdee3e42044aab5efeb36 *config.buildinfo
ae37cfd49e2d7a9287a4efc424822e56abecfd427ce380655489a9614227f12e *feeds.buildinfo
c65dd17640567042ab4349124571df6448362caaf35472644e0e299d7dccf9b7 *openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
dd571dfe6d82d003c9bb73947c93a7d588494c2019e8aca755146871029ec2fb *openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
2ae4f56dd79908e5ee37bc98e006bcba66e74a21c4d53b0196f8388cf05c57dc *openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
f814ce4b83e191a6148421107142da56b42a1771f191c79f86d2ca3b8918a688 *version.buildinfo
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

Then run setup and restore DB/history files before publishing the release.
