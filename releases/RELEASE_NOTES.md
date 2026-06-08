# v25.12.016

ZBT-Z8803BE community build rebased on current OpenWrt main.

## Highlights

- Adds the default wired-WAN behavior requested in GitHub issue #7.
- Keeps `eth1` as the RJ45 WAN path and `eth2` as the SFP WAN path.
- Brings up both wired uplinks automatically at first boot with matching IPv4 and IPv6 defaults.
- Prefers SFP by route metric when both wired uplinks are connected, while keeping RJ45 as fallback.
- Keeps `wan_sfp` and `wan_sfp6` in the firewall `wan` zone by default.
- Preserves the existing deterministic DNS policy and high-metric cellular fallback behavior.

## Build info

- OpenWrt revision: `r34764-819875e2d1`
- Kernel: `6.18.34`
- Target: `mediatek/filogic`
- Device: `zbtlink_zbt-z8803be`

## Artifacts

- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin`
- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin`
- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest`
- `config.buildinfo`
- `feeds.buildinfo`
- `version.buildinfo`
- `sha256sums`

## Checks

- Shell syntax check passed for `target/linux/mediatek/filogic/base-files`.
- Full Docker build completed and generated sysupgrade + initramfs images.
- Added explicit first-boot metrics for `wan` / `wan6` and `wan_sfp` / `wan_sfp6`.
- Ensured `wan6` and `wan_sfp6` are created even if missing in existing configs.
- Added verification guidance for dual-uplink first-boot behavior.
- Manifest confirms kernel package `6.18.34`.

## Issue reference

- GitHub issue #7: SFP as WAN default/failover behavior.
