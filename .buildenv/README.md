# `.buildenv/` - Docker build harness (macOS host)

Target device: **ZBTLink ZBT-Z8803BE** (MediaTek MT7988A / Filogic 880 NAND)
Config symbol: `CONFIG_TARGET_mediatek_filogic_DEVICE_zbtlink_zbt-z8803be`
(board_name `zbtlink,zbt-z8803be`; the older `...,mt7988a-nand` form
from main-1 is still listed in `SUPPORTED_DEVICES` for upgrade compat).

## Files

- `Dockerfile` - Ubuntu 24.04 arm64 native, OpenWrt deps, `builder` user
- `build.sh` - wrapper driving image, volume, and build commands
- `zbt8803be.config` - minimal seed `.config` for this device

## One-shot flow

```sh
./.buildenv/build.sh init      # build image + create volume + link dirs
cp .buildenv/zbt8803be.config .config
./.buildenv/build.sh feeds     # clones upstream OpenWrt feeds + ImmortalWrt
                               # overlay + FUjr/QModem feed (all pinned to
                               # SHAs in feeds.conf.default)
./.buildenv/build.sh config
./.buildenv/build.sh download
./.buildenv/build.sh build
./.buildenv/build.sh extract   # firmware -> ./output/
```

## External package sources

No git submodules. Everything comes from either (a) our own code
in-tree (`package/luci-app-mlo/`, `package/emortal/`) or (b) pinned
feeds in `feeds.conf.default`:

| feed                   | source                                    | used for                          |
|------------------------|-------------------------------------------|-----------------------------------|
| `packages`             | git.openwrt.org/feed/packages             | upstream OpenWrt stock packages   |
| `luci`                 | git.openwrt.org/project/luci              | upstream LuCI + core LuCI apps    |
| `routing` / `telephony`/`video` | openwrt stock                    | rarely-used upstream feeds        |
| `iwrt_packages`        | github.com/immortalwrt/packages (SHA-pinned) | AGH + a few utilities not upstream|
| `iwrt_luci`            | github.com/immortalwrt/luci (SHA-pinned)  | luci-theme-argon, luci-app-wifihistory, luci-app-diskman, luci-app-autoreboot, optional LuCI overlays |
| `qmodem`               | github.com/FUjr/QModem (SHA-pinned)       | Quectel/Fibocom/SimCom modem management LuCI UI + drivers |

Vendored in-tree (copied, not submodules, GPL-2.0-only):

- `package/emortal/autocore/` - live CPU / memory / temperature
  widgets on the LuCI Status -> Overview page. Source: ImmortalWrt
  master @ 2026-04-24.
- `package/emortal/cpufreq/` - CPU governor switcher + UCI init.
  Source: ImmortalWrt master @ 2026-04-24.

Bumping a feed to a newer SHA: edit `feeds.conf.default`, replace
the `^<sha>` suffix after the repo URL, commit. Next `build.sh feeds`
will re-clone at the new pin.

## Why symlink build dirs onto a Docker volume?

macOS APFS is case-insensitive. OpenWrt extracts kernel/package tarballs
with case-conflicting filenames into `build_dir/` - would clobber silently
on APFS. Volume = ext4 inside Linux VM -> case-sensitive + fast I/O.

Symlinked dirs:
- `build_dir/` - kernel + package build trees
- `staging_dir/` - cross-toolchain + sysroot
- `dl/` - downloaded source tarballs
- `tmp/` - build scratch
- `bin/` - final firmware output

Source tree (`package/`, `target/`, `scripts/`, ...) lives on host - no
case-conflicts there. Lets you browse/edit with native macOS tools.

## Firmware output

After `extract`, look in `./output/mediatek/filogic/` for:
- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin`
  (flashable image)
- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin`
  (RAM-only FIT for TFTP / U-Boot recovery)
- `...manifest`, `sha256sums`, `config.buildinfo`,
  `version.buildinfo`, `feeds.buildinfo`
  (reproducibility metadata)
