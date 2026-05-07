# ZBT-Z8803BE OpenWrt v25.12.2-3-zbt8803be maintenance release

[English](RELEASE_NOTES.md) | [中文](RELEASE_NOTES.zh-CN.md)

> **Community build.** Maintained by a single contributor; expect rough edges. Bug reports and pull requests are welcome.

Custom OpenWrt build for the **ZBTLink ZBT-Z8803BE** WiFi 7 router.

- **Release tag:** `v25.12.2-3-zbt8803be`
- **OpenWrt base:** official `v25.12.2` / `r32802-f505120278`
- **Kernel:** `6.12.74`
- **Target:** `mediatek/filogic`
- **Default login:** `root` / `admin`

## What's new since `v25.12.2-2-zbt8803be`

- **Persistent app stats after reboot.** Temperature history, Modem Events, and WiFi Client History now store bounded data under `/etc/...` instead of volatile `/var`/`/tmp` paths.
- **Rotation instead of clearing.** Temperature and Modem Events keep 7 days; WiFi Client History prunes entries older than 90 days.
- **Safe migration.** Current `/var/log/zbt-*` and `/var/lib/wifihistory` data is copied into the new persistent stores on first run.
- **QModem hard reboot recovery.** Internet monitoring runs every 10 seconds and triggers the guarded GPIO modem power-cycle path after 6 consecutive failures.
- **QModem manual reboot cooldown.** Manual soft/hard modem restarts now pause monitor-triggered reboot actions for 10 minutes while the cellular link comes back.
- **Lower wrtbwmon CPU load.** NFT table work is cached, guarded, and throttled; disabling wrtbwmon removes cron jobs and stops active workers.

## Validation

- Custom shell scripts passed `sh -n`.
- Custom LuCI JavaScript views passed `node --check`.
- LuCI ACL JSON passed `python3 -m json.tool`.
- Live router `3fl.lan` was updated and verified with persistent stores populated under `/etc/zbt-temperature`, `/etc/zbt-modem-events`, and `/etc/wifihistory`.
- Live router `3fl.lan` verified qmodem manual cooldown, guarded reboot skip, and wrtbwmon `nft -f -` reduction.
- Firmware was rebuilt from this release branch and extracted to `output/mediatek/filogic`.

## Checksums

```text
9dd4c08b461bd0cc00687fcaf02bfbcf03ce177011d6eb5c99f83ec78e605ea3  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
52be5036bb72275a996247bb956ab5910d65da2e1b86f441cdba7c8a82538037  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
d1657eba3df03621517132b396c5a0bcdbc44d86fe3c0c91f3743140e8108dee  openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
bcd424a53c0d140eaa40c15833bb37017606dc4df10c9816ced33f296ce8e382  sha256sums
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

Existing OpenWrt:

```sh
sysupgrade openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
```

Clean reset:

```sh
sysupgrade -n openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
```
