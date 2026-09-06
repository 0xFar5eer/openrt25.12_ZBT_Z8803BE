# ZBT-Z8803BE OpenWrt 25.12.2 / Linux 6.12.74

Release `v25.12.020` is a community firmware build for ZBTLink ZBT-Z8803BE.

## Highlights
- Uses OpenWrt `25.12.2` (`r32858-16347e93b6`) and Linux `6.12.74`.
- Adds the kernel modules requested in issue #12, built as loadable kmods:
  - `kmod-tcp-bbr` — BBR congestion control
  - `kmod-bonding` — link aggregation
  - `kmod-tls` — kernel TLS, pulled in as a bonding dependency
- No modem, wireless, or LuCI behavior changed relative to `v25.12.019`.
- Ships `packages-aarch64_cortex-a53.tar.gz` alongside the image: the complete package feed built from this exact configuration, so on-device `apk` can install from a matching local source instead of a mismatched snapshot feed.

## Validation
- `make defconfig` retained `kmod-tcp-bbr`, `kmod-bonding`, and `kmod-tls`.
- Full Docker firmware build completed successfully.
- The image manifest lists all three at version `6.12.74-r1`.
- Generated image checksums passed `sha256sum -c sha256sums --ignore-missing`.
- `tests/check-zbt-firmware.sh` and `git diff --check` passed.
- The published `sha256sums` covers the firmware artifacts only; the packages tarball digest is published separately in this note.
- Loading the three modules on hardware has **not** been exercised by the maintainer. Do not treat build or static validation as hardware confirmation.

## Artifacts
- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin`
  - SHA-256: `b79322f99dc47c41432523ce89bf875d3a482f39831c4965ffa4e5d5dfe4dfbd`
- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin`
  - SHA-256: `2095f444768ef7e3da12275d2bd9292ce1c2c58e56ece5d3e2a3b5cbf0067e6d`
- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest`
  - SHA-256: `072b12265a71173feaf1e5f8d2003973f77c4dfa6ecfb508c84674ff75aea843`
- `packages-aarch64_cortex-a53.tar.gz`
  - SHA-256: `69e1a0cb8d3b76819820682485a9570dda65e96862271c329b12793bd1ed2784`
- `sha256sums`, `config.buildinfo`, `feeds.buildinfo`, and `version.buildinfo`

## Upgrade
To preserve configuration:

    sysupgrade -v openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin

For a clean configuration:

    sysupgrade -n openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin

## Donate
Optional donations help support maintenance and testing:

- **ERC20 / BEP20 — USDT, USDC, ETH, BNB:** `0xd1122130ad6e9ab948212087a90797e3129bfc1c`
- **TRC20 — TRX, USDT:** `TTcT5m4BriHKyNrB4KYyLMK4ZGn54Nk6z2`
- **BTC:** `12N34ZYeiwxKEcM5FSnkgnHwxhW6pE3r4m`
- **LTC:** `LLNtEGeZ5C6QnSY6BU1MYAZjh8MJpF6zsK`
