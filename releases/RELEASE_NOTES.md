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
- **Temperature page TypeError fix.** Avoids calling `.format()` on translated strings, fixing `_(...).format is not a function` on the LuCI Temperature page.

### Crash and reboot forensics

- **Persistent crash log directory.** Added `zbt-crash-forensics`, storing diagnostic data in `/etc/zbt-crash-logs/` so it survives reboots and reflashes.
- **Kernel pstore archiving.** On boot, `/sys/fs/pstore/*` is copied into timestamped `/etc/zbt-crash-logs/pstore-<epoch>/` directories and old archives are pruned to the latest 10.
- **Boot classification.** `boot-events.log` records first, clean, and unclean boots using a clean-shutdown marker plus kernel `boot_id`, avoiding fake boot events during service restarts.
- **Rolling health snapshots.** A one-minute cron overwrites `last-snapshot.txt` and keeps `prev-snapshot.txt`, capturing uptime, load, memory, top processes, thermal/hwmon/fan data, network counters, dmesg tail, and logread tail.
- **Backup integration.** App-history backup/restore now preserves `/etc/zbt-crash-logs/` alongside the existing app history files.

## Validation

- Firmware rebuilt from commit `7495da369d` and extracted to `output/mediatek/filogic`.
- Staged release assets passed `sha256sum -c sha256sums --ignore-missing`.
- `zbt-temperature-log` passed `sh -n`.
- `zbt-crash-forensics`, `zbt_crash_forensics`, and `49-zbt-crash-forensics` passed `sh -n`.
- Temperature LuCI JavaScript passed `node --check`.
- Temperature rpcd ACL passed JSON validation.
- Engineering code review workflow passed before rebuild; no blockers found.
- Source tree passed `git diff --check` before release documentation updates.
- Embedded firmware review and final code review gates passed before rebuild.
- Live router validation before rebuild showed stable fan behavior around cooling state 2 / PWM 112 with no bouncing, LuCI/ubus could read the tmpfs telemetry file, and a simulated reboot (stop service + wipe tmpfs + start) successfully restored the persistent snapshot back into tmpfs and resumed sampling.
- Live router crash-forensics smoke test showed service enabled, one cron entry installed, pstore archived, snapshots written, and repeated service restarts did not append duplicate boot events.

## Checksums

```text
bd3f1b79c9010256b0880fdbefd41723ff7ccf884bc2b8e5c805c57c212a4dbe  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
63fe6289ced18386d9ed8425eaebf9d3858e8246a671386edc3f0fcc056549f3  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
5ed76d939ebe947531818bd82fa2138407b086f05dd8028b07414cc3fa28b05b  openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
0edfdf33440118bd2623d4731c56c37b90a74b301ff753ad939e240c9273cd88  sha256sums
19a0a0bc2e43e95a242f16dc77f6645a1b58d48348c4e8d247cf8273daaabdc2  config.buildinfo
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
