# ZBT-Z8803BE OpenWrt v25.12.2-7-zbt8803be speedtest maintenance release

[English](RELEASE_NOTES.md) | [中文](RELEASE_NOTES.zh-CN.md)

> **Community build.** Maintained by a single contributor; expect rough edges. Bug reports and pull requests are welcome.

Custom OpenWrt build for the **ZBTLink ZBT-Z8803BE** WiFi 7 router.

- **Release tag:** `v25.12.2-7-zbt8803be`
- **OpenWrt base:** official `v25.12.2` / `r32802-f505120278`
- **Kernel:** `6.12.74`
- **Target:** `mediatek/filogic`
- **Default login:** `root` / `admin`

## What's new since `v25.12.2-6-zbt8803be`

### Speedtest LuCI app

- **Speedtest.net-only backend.** The Speedtest page no longer exposes backend selection and now uses the Speedtest.net backend exclusively.
- **Pinned international presets.** Added curated Speedtest.net server presets for PH, KH, SG, MY, US, DE, NL, FR, and TH, including fixed server IDs and legacy alias handling.
- **More reliable preset execution.** Pinned presets skip location-biased XML discovery, validate configured HTTP/HTTPS URLs before test traffic, and normalize saved country codes.
- **Persistent app config.** The LuCI page loads `/etc/config/zbt-speedtest` through `/usr/sbin/zbt-speedtest-json --config` and saves selected country, preset, transfer sizes, and connection count after a run.
- **Persistent result history.** Completed tests are stored in `/etc/zbt-speedtest/history.json` with timestamp, country, preset, server, download/upload Mbps, ping, byte counts, and duration. History is capped at 100 entries and uses a file lock to avoid lost concurrent appends.
- **History UI in LuCI.** The Speedtest page now renders previous tests in a table and refreshes it after each run.
- **LuCI compatibility fixes.** Removed JavaScript `.format()` calls and fixed nested table-row rendering that could show `[object HTMLTableRowElement]`.
- **ACL and backup coverage.** rpcd ACLs allow the app to read/write the history DB, and app-history backup/restore preserves `/etc/zbt-speedtest/history.json`.

## Validation

- Firmware rebuilt from commit `58a983ad76` and extracted to `output/mediatek/filogic`.
- Corrected build config with `CONFIG_PACKAGE_luci-app-zbt-speedtest=y`; final manifest includes `luci-app-zbt-speedtest - 26.133.41786~58a983a`.
- Staged release assets passed `sha256sum -c sha256sums --ignore-missing`.
- `zbt-speedtest-json` passed Python syntax validation.
- Speedtest LuCI JavaScript passed `node --check`.
- Speedtest rpcd ACL passed JSON validation.
- Engineering code review workflow passed; fixes included locked history appends and active-config preset labels in history entries.
- Local and router temp-file history checks passed for append, custom preset label resolution, and clear-history behavior.
- Live router hotfix was deployed to `3fl.lan`, LuCI caches were cleared, `rpcd`/`uhttpd` restarted, and `/usr/sbin/zbt-speedtest-json --history` returned the persisted SG Singtel history entry.

## Checksums

```text
a3c35330d09649e56e4ad29b9d6dcbabe3ac3983989e35e54a7d6f3fb3889d7a  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
4f9c90aebc44ddd9aa6c2594a4d55ad2fa7855492c2381946902dc4f126e6c90  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
c755428ec8874006d1572f2b0a457ae61092d1907119ac01ea5e9c46ad443e4d  openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
22cd03fcfd73f645c0be48165b4449e5768fef147908db51dcb8a25db88b98a5  sha256sums
43a7d0d006229a8c60a42915e59c7220623778508f18387be37dc8d79ea15777  config.buildinfo
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
