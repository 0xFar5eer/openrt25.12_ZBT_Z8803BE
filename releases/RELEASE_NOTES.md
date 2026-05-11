# ZBT-Z8803BE OpenWrt v25.12.2-6-zbt8803be fan/temperature maintenance release

[English](RELEASE_NOTES.md) | [中文](RELEASE_NOTES.zh-CN.md)

> **Community build.** Maintained by a single contributor; expect rough edges. Bug reports and pull requests are welcome.

Custom OpenWrt build for the **ZBTLink ZBT-Z8803BE** WiFi 7 router.

- **Release tag:** `v25.12.2-6-zbt8803be`
- **OpenWrt base:** official `v25.12.2` / `r32802-f505120278`
- **Kernel:** `6.12.74`
- **Target:** `mediatek/filogic`
- **Default login:** `root` / `admin`

## What's new since `v25.12.2-5-zbt8803be`

### Fan and thermal policy

- **Quieter fan curve.** Replaced the userspace raw cubic PWM policy with discrete `pwm-fan` cooling states that match the DTS `cooling-levels = <0 80 112 144 176 216 255>`.
- **Hysteresis to prevent fan hunting.** Fan state now steps up at 55/65/70/75/80/85 C and steps down only below 48/58/66/72/76/80 C, avoiding rapid back-and-forth speed changes near thresholds.
- **Kernel thermal fail-safe.** Added an `active-max` CPU thermal trip at 85 C that maps to fan cooling level 6, so the kernel can force full fan speed even if userspace sampling/cron is not running.
- **Less aggressive CPU thermal trips.** CPU thermal trips are now aligned with the quieter policy: silent 45 C, low 55 C, high 75 C, max 85 C, with the critical 100 C trip unchanged.
- **Stale PWM recovery.** If `cur_state` already equals the target state but the exposed `pwm1` value is stale, the logger re-applies the thermal cooling state instead of writing raw PWM directly.

### Temperature telemetry / LuCI

- **Tmpfs-only telemetry.** Temperature history now writes to `/var/log/zbt-temperature/readings.csv` instead of `/etc/zbt-temperature/readings.csv`, avoiding persistent flash writes.
- **Breaking cleanup.** Legacy `/etc/zbt-temperature` migration/fallback and old 4-column CSV compatibility were removed intentionally.
- **LuCI data path fixed.** The Temperature page and rpcd ACL now read `/var/log/zbt-temperature/readings.csv`, and the frontend expects the current 5-column CSV format: epoch, group, name, value, unit.

## Validation

- Firmware rebuilt from commit `f58ee50c35` and extracted to `output/mediatek/filogic`.
- Staged release assets passed `sha256sum -c sha256sums --ignore-missing`.
- `zbt-temperature-log` passed `sh -n`.
- Temperature LuCI JavaScript passed `node --check`.
- Temperature rpcd ACL passed JSON validation.
- Source tree passed `git diff --check` before release documentation updates.
- Embedded firmware review and final code review gates passed before rebuild.
- Live router validation before rebuild showed stable fan behavior around cooling state 2 / PWM 112 with no bouncing, and LuCI/ubus could read the tmpfs telemetry file.

## Checksums

```text
373420c401352f4890c4480de24d333174f8decdae5d3631d58e91fc0ffeed0b  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
77cb8e7a2c7840170d35bfbdf9669d2e6caa7397ea43295899bd57f6d294ff8f  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
2d9410ca9a1d15617fe715256e67a0d5e2a365a2ff1f132f9bfcbc6d0c7dbdb8  openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
b9847815647e18df517aea99f33681a179f1110077ea44acf8569856e5a14066  sha256sums
0d1ac3f38d93e39e61e064f4f14062918333ba99a5e8fe1ac7c8c805101623d2  config.buildinfo
ae37cfd49e2d7a9287a4efc424822e56abecfd427ce380655489a9614227f12e  feeds.buildinfo
05f6cea7ac9e5c3d2d73225400b4dc3cf51eb8002f54cf6d05e5934c1805c60c  version.buildinfo
```

## Assets

Upload exactly these files:

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

## Flash

Existing OpenWrt, preserving settings:

```sh
sysupgrade openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
```

Clean reset:

```sh
sysupgrade -n openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
```
