# ZBT-Z8803BE OpenWrt 25.12.2 / Linux 6.12.74

Release `v25.12.019` is a community firmware build for ZBTLink ZBT-Z8803BE.

## Highlights
- Uses OpenWrt `25.12.2` (`r32858-16347e93b6`) and Linux `6.12.74`.
- Adds **Network → WiFi 7 MLO** in LuCI. MLO remains opt-in: factory wireless defaults stay as separate band-specific SSIDs until configured through the page.
- Includes GNU `timeout` at `/usr/bin/timeout` for bounded shell commands.
- Makes board-managed QModem recovery slot-aware: a Quectel modem detected at USB `4-1` uses 5G1 / `4_1`, while a modem detected at USB `4-2` uses 5G2 / `4_2`. The matching QModem profile, network interfaces, and WAN firewall membership are maintained without altering the peer slot.
- Keeps 5G1 as the default-powered slot and 5G2 opt-in through its GPIO switch. Wired WAN and SFP routes remain preferred over cellular through lower metrics.
- Preserves the prior Quectel RNDIS separation: only the QModem profile belonging to an RNDIS modem is disabled.

## Validation
- `make defconfig` retained `luci-app-mlo`, `wpad-openssl`, and `coreutils-timeout`.
- Full Docker firmware build completed successfully.
- Modified shell scripts passed `sh -n`; `tests/check-zbt-firmware.sh` and `git diff --check` passed.
- Generated image checksums passed `sha256sum -c sha256sums --ignore-missing`.
- The image manifest contains `luci-app-mlo`, `wpad-openssl`, and `coreutils-timeout`.
- Extracted SquashFS contains `/usr/bin/timeout`, the MLO LuCI menu, ACL, and `mlo/main.js` view.
- Hardware MLO association/multi-link traffic and physical 5G2/modem 2/SIM2 connectivity have **not** been tested by the maintainer. Do not treat build or static validation as hardware confirmation.

## Artifacts
- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin`
  - SHA-256: `296339130bcfd945567e38018f9ea7557595e4b04a705dc0a760865ba8f2ce43`
- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin`
  - SHA-256: `3f9bc4acfdb50e2f1a2b4695ab1710e7df5756040830decbc1707b3b8993a242`
- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest`
  - SHA-256: `e8001906fb4fa60cc71636e2bd6d3c1f01a29bec0e5afa5773cd1b18b7c616a7`
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
