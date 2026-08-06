# ZBT-Z8803BE OpenWrt 25.12.2 / Linux 6.12.74

Release `v25.12.017` is a validated community firmware build for ZBTLink ZBT-Z8803BE.

## Highlights
- Uses OpenWrt `25.12.2` (`r32858-16347e93b6`) and Linux `6.12.74`.
- Configures SFP WAN (metric `9`), RJ45 WAN (metric `10`), and ready-SIM cellular fallback (metric `200`).
- Powers 5G1 at boot, enables automatic QModem discovery and dialing, and persistently enables the ZBT QModem watchdog to repair late modem state rewrites.
- Includes Argon, QModem Next, modem events, SMS tooling, and the local ZBT About, Health, Temperature, and Modem Events LuCI applications.
- Uses deterministic DNS and excludes USB/iPhone tethering defaults.

## Validation
- `make defconfig` and a full Docker firmware build completed successfully.
- First-boot and watchdog scripts passed `sh -n`; source changes passed `git diff --check`.
- A clean `sysupgrade -n` was tested on ZBT-Z8803BE with no corrective router commands.
- After first boot, 5G1 was on, QModem slot `4_1` was enabled, the watchdog was enabled and running, WWAN received an IPv4 address, and `ping -I wwan0 1.1.1.1` completed with 0% packet loss.

## Artifacts
- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin`
- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin`
- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest`
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
