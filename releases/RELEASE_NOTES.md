# ZBT-Z8803BE OpenWrt 25.12.2 / Linux 6.12.74

Release `v25.12.018` is a community firmware build for ZBTLink ZBT-Z8803BE.

## Highlights
- Uses OpenWrt `25.12.2` (`r32858-16347e93b6`) and Linux `6.12.74`.
- Fixes first-boot Wi-Fi activation: the enabled factory wireless configuration is reloaded after UCI defaults, so users no longer need to run `wifi up` manually after a clean flash.
- Adds Quectel USB/RNDIS support: RNDIS compositions receive a dedicated DHCP cellular uplink with metric `200` and WAN firewall membership.
- Keeps RNDIS separate from QModem's QMI/MBIM lifecycle, preventing a valid `usb0` DHCP modem from being treated as an unsupported QMI device.
- Keeps SFP WAN (metric `9`) and RJ45 WAN (metric `10`) preferred over cellular fallback.
- Powers 5G1 at boot and retains QModem management for QMI/MBIM modem compositions.

## Validation
- `make defconfig` and a full Docker firmware build completed successfully.
- Modified shell scripts passed `sh -n`; source changes passed `git diff --check`.
- Generated image checksums passed `sha256sum -c sha256sums --ignore-missing`.
- The image manifest contains `kmod-usb-net-rndis`, `qmodem`, `qmodem_monitor`, and `wpad-openssl`.
- Hardware smoke testing after installation remains required for first-boot Wi-Fi and RNDIS modem behavior.

## Artifacts
- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin`
  - SHA-256: `64e791598268bbf5b29141bc0a7bac17479b7b189a2d6dc565992f6a0db2d0de`
- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin`
  - SHA-256: `070e89ab5415ae67c319c8b245b2c9f69d2894615f1e3e0fce67201e77725c31`
- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest`
  - SHA-256: `6875eae6712978d9487f8dfcfc6b978854d1e618e7eebc4412ea554f6fc8e63c`
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
