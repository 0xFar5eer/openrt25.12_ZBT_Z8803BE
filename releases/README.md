# Release staging
Local staging folder for validated **ZBTLink ZBT-Z8803BE** firmware builds.

- **Current tag:** `v25.12.020`
- **OpenWrt revision:** `r32858-16347e93b6`
- **OpenWrt release / kernel:** `25.12.2` / `6.12.74`
- **Target:** `mediatek/filogic`
- **Build output:** `output/mediatek/filogic`

Firmware binaries are intentionally Git-ignored. Attach only the current files below to the GitHub release.

## Assets to publish
- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin`
- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin`
- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest`
- `sha256sums`
- `config.buildinfo`
- `feeds.buildinfo`
- `version.buildinfo`
- `packages-aarch64_cortex-a53.tar.gz`
- `RELEASE_NOTES.md`
- `RELEASE_NOTES.zh-CN.md`

The generated `sha256sums` covers the firmware artifacts only. Publish the package feed tarball digest in the release notes.

See `RELEASE_NOTES.md` for tested behavior and upgrade instructions.
