# v25.12.15-zbt8803be-main6.18

ZBT-Z8803BE community build rebased on current OpenWrt main.

## Highlights

- Rebased downstream ZBT-Z8803BE customization branch onto OpenWrt `main` at `c82f2724f5`.
- Updated kernel from `6.18.33` to `6.18.34`.
- Verified the ZBT-Z8803BE NAND layout before flashing:
  - UBI volumes are `kernel`, `rootfs`, and `rootfs_data`.
  - Existing ZBT sysupgrade path keeps writing FIT/kernel payload to `kernel`.
- Validated by sysupgrade on ZBT-Z8803BE with settings preserved.
- Added `platform.sh` to replay-customizations allowlist so board-specific upgrade logic is preserved on future upstream replays.
- Preserved post-v12 customizations and local WDS client identity fix.

## Build info

- OpenWrt revision: `r34651-08fc94e13c`
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
- Sysupgrade tar contains `CONTROL`, `kernel`, and `root` entries.
- Preserving-settings sysupgrade completed successfully on ZBT-Z8803BE.
- Post-flash checks passed: kernel/revision, UBI layout, LAN route/DNS, radios, LuCI/SSH/rpcd, installed package versions.
- Manifest confirms kernel package `6.18.34`.

## Important flash note

Live pre-flash audit confirmed the working NAND layout uses UBI volumes `kernel`, `rootfs`, and `rootfs_data`. This release preserves that sysupgrade layout and has been validated with settings preserved.
