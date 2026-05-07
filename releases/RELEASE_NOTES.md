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

## Validation

- Custom shell scripts passed `sh -n`.
- Custom LuCI JavaScript views passed `node --check`.
- LuCI ACL JSON passed `python3 -m json.tool`.
- Live router `3fl.lan` was updated and verified with persistent stores populated under `/etc/zbt-temperature`, `/etc/zbt-modem-events`, and `/etc/wifihistory`.
- Firmware was rebuilt from this release branch and extracted to `output/mediatek/filogic`.

## Checksums

```text
89d694ebe0b464819dc4721ccdecb63038915cb6db2d3eb15f5f21eb47448bf8  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
248d1ddb8add40dda9a5c17a6532011a6bccf87f48707d0cc3418e713dbbde07  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
d1657eba3df03621517132b396c5a0bcdbc44d86fe3c0c91f3743140e8108dee  openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
eb487134bd9dd7986d475f46c55fc6928faf070e5a86bb2436261151730e4cc3  sha256sums
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
