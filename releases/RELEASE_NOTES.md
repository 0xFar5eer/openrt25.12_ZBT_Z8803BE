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

- **Tmpfs working file, persistent snapshot.** Temperature history is sampled into `/var/log/zbt-temperature/readings.csv` (tmpfs) and snapshotted atomically to `/etc/zbt-temperature/readings.csv` (overlay/flash). On boot the snapshot is restored back into tmpfs, so history now survives unexpected reboots.
- **Low flash wear.** Snapshot interval defaults to `ZBT_TEMPERATURE_PERSIST_INTERVAL=900` seconds (~96 writes/day) using `cp` + `sync` + `mv` for atomicity.
- **Clean shutdown flushes.** The `zbt_temperature` init script flushes the working file on `stop`, so a normal reboot loses no samples; only an abrupt crash can lose up to the last interval.
- **Breaking cleanup retained.** Legacy 4-column CSV compatibility remains removed; the frontend still expects the current 5-column format: `epoch, group, name, value, unit`.
- **LuCI data path unchanged.** The Temperature page and rpcd ACL continue to read `/var/log/zbt-temperature/readings.csv`.

## Validation

- Firmware rebuilt from commit `8f88058c57` and extracted to `output/mediatek/filogic`.
- Staged release assets passed `sha256sum -c sha256sums --ignore-missing`.
- `zbt-temperature-log` passed `sh -n`.
- Temperature LuCI JavaScript passed `node --check`.
- Temperature rpcd ACL passed JSON validation.
- Source tree passed `git diff --check` before release documentation updates.
- Embedded firmware review and final code review gates passed before rebuild.
- Live router validation before rebuild showed stable fan behavior around cooling state 2 / PWM 112 with no bouncing, LuCI/ubus could read the tmpfs telemetry file, and a simulated reboot (stop service + wipe tmpfs + start) successfully restored the persistent snapshot back into tmpfs and resumed sampling.

## Checksums

```text
9fe17ce6cbbaa0a48ff4290560217678d02211649c37888268307c766f321472  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
d0c4be4b9ccd100cab43d47be4d8147645f6aa08544dcc5285085724d7af26fb  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
eb0b6a8c1bb75620a0c27c8e4a659227f061e327dd19a4c53e878c3edc3d47a4  openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
37a90d25ba0f475ddfa479a5e7825c92bd9161c320acff5812ee442e0261d37d  sha256sums
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
