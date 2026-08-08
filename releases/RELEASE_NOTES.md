# ZBT-Z8803BE OpenWrt 25.12.2 / Linux 6.12.74

Release `v25.12.018` is a community firmware build for ZBTLink ZBT-Z8803BE.

## Highlights
- Uses OpenWrt `25.12.2` (`r32858-16347e93b6`) and Linux `6.12.74`.
- Fixes first-boot Wi-Fi activation: the enabled factory wireless configuration is reloaded after UCI defaults, so users no longer need to run `wifi up` manually after a clean flash.
- Corrects Quectel USB/RNDIS management: the DHCP cellular uplink is now configured from the net-device event after `usb0` exists, rather than from an earlier USB event.
- Suppresses QModem’s `wwan0`/QMI recovery lifecycle only while a Quectel `rndis_host` device is active, preventing it from repeatedly restarting the absent `wwan0` profile.
- Keeps RNDIS separate from QModem's QMI/MBIM lifecycle and preserves metric `200` for cellular; SFP WAN (metric `9`) and RJ45 WAN (metric `10`) remain preferred.
- Powers 5G1 at boot and retains QModem management for QMI/MBIM modem compositions.

## Validation
- `make defconfig` and a full Docker firmware build completed successfully.
- Modified shell scripts passed `sh -n`; source changes passed `git diff --check`.
- Generated image checksums passed `sha256sum -c sha256sums --ignore-missing`.
- The image manifest contains `kmod-usb-net-rndis`, `qmodem`, `qmodem_monitor`, and `wpad-openssl`.
- Hardware smoke testing after installation remains required for the first-boot Wi-Fi correction and, specifically, the Quectel RNDIS/QModem suppression behavior. This corrected build has not been tested on the maintainer’s router.

## Artifacts
- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin`
  - SHA-256: `49b5e74fb7e46d23641dcf7386bc8b2a134b591a3e07d2b58edd04d051e0726b`
- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin`
  - SHA-256: `1d53ebdcbca8e8cacdaee518277d1a9ce1d45632c06c8bfc2c65393427be4c19`
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
