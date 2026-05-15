# Architecture

This repository is an OpenWrt 25.12.2 firmware tree customized for the ZBTLink ZBT-Z8803BE WiFi 7 router. It keeps the normal OpenWrt source layout and layers board support, first-boot defaults, package selections, and local LuCI applications on top of the upstream build system.

## High-level layout

| Path | Role |
|------|------|
| `target/linux/mediatek/` | MediaTek Filogic target support, image profiles, device tree, and board-specific base-files overlays. |
| `target/linux/mediatek/dts/mt7988a-zbtlink-zbt-z8803be.dts` | Device tree for the ZBT-Z8803BE hardware. |
| `target/linux/mediatek/image/filogic.mk` | Image profile for `zbtlink_zbt-z8803be`. |
| `target/linux/mediatek/filogic/base-files/` | Files installed into the router rootfs for first-boot defaults, hotplug hooks, init scripts, modem helpers, shell defaults, and banner content. |
| `.buildenv/` | Docker-based host build wrapper and seed configuration for reproducible local builds. |
| `.buildenv/zbt8803be.config` | Seed config merged into `.config` before `make defconfig`. |
| `package/luci-app-zbt-about/` | Local LuCI page for build/about information. |
| `package/luci-app-zbt-temperature/` | Local LuCI temperature, modem sensor, and fan telemetry app. |
| `package/luci-app-zbt-modem-events/` | Local LuCI modem event history and health sampling app. |
| `package/luci-app-mlo/` | Local LuCI page for WiFi 7 Multi-Link Operation configuration. |
| `feeds.conf.default` | Pinned package feeds used by the build. |
| `releases/` | Markdown release notes and release-staging metadata. Firmware binaries in this directory are intentionally gitignored. |

## Build architecture

The project uses the normal OpenWrt `make` graph, with a Docker wrapper to keep heavy build artifacts on a Linux Docker volume. The wrapper in `.buildenv/build.sh` provides the lifecycle:

1. `init` builds the Docker image, creates the Docker volume, and links heavy directories such as `build_dir`, `staging_dir`, `dl`, `tmp`, and `bin` into that volume.
2. `feeds` updates and installs feeds, then removes selected unused ImmortalWrt LuCI overlay packages that can introduce recursive Kconfig problems.
3. `config` merges `.buildenv/zbt8803be.config` into `.config` and runs `make defconfig`.
4. `download` runs OpenWrt source downloads.
5. `build` runs the full OpenWrt build.
6. `extract` copies built images from `bin/targets` into `output/`.

The generated image path used by the README is:

```text
output/mediatek/filogic/openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
```

## Image profile

The ZBT-Z8803BE image profile is defined in `target/linux/mediatek/image/filogic.mk` as `Device/zbtlink_zbt-z8803be`.

Key profile facts:

- Device vendor: `Zbtlink`
- Device model: `ZBT-Z8803BE`
- DTS: `mt7988a-zbtlink-zbt-z8803be`
- DTS directory: `../dts`
- Supported compatibility: `zbtlink,zbt-z8803be,mt7988a-nand`
- Image output: `sysupgrade.bin`
- Base device packages include SFP, PWM fan, USB 3.0, MT7996 firmware, MT7988 2.5G PHY firmware, and MT7988 wireless offload firmware.

## Hardware model

The device tree declares the board as:

```text
model = "Zbtlink Z8803BE"
compatible = "zbtlink,zbt-z8803be", "zbtlink,zbt-z8803be,mt7988a-nand", "mediatek,mt7988a"
```

Important modeled hardware includes:

- Reset and WPS GPIO keys.
- Status, WAN, power, `5g1`, and `5g2` LEDs.
- GPIO exports for modem slot power and SIM mux control.
- SFP cage connected through `i2c2`.
- PWM fan with seven cooling levels: `0 80 112 144 176 216 255`.
- GPIO watchdog.
- SPI-NAND flash with fixed partitions and a UBI firmware volume.

The board network defaults map three LAN ports and two WAN-side interfaces:

```text
LAN: lan0 lan1 lan2
WAN: eth1 eth2
```

## First-boot defaults

Board defaults live under `target/linux/mediatek/filogic/base-files/etc/uci-defaults/`. They are board-guarded for `zbtlink,zbt-z8803be` and `zbtlink,zbt-z8803be,mt7988a-nand`.

Important defaults include:

| File | Purpose |
|------|---------|
| `20-zbt-apk-feeds` | Seeds APK feed configuration. |
| `28-zbt-qmodem-slots` | Seeds modem-slot defaults. |
| `32-zbt-z8803be-wan-failover` | Sets WAN/WWAN metrics, binds `wwan0` to netifd stubs, and keeps cellular in the `wan` firewall zone. |
| `40-zbt-qmodem-dns-suppress` | Suppresses QModem DNS injection. |
| `44-zbt-qmodem-watchdog-disable` | Disables the ZBT QModem watchdog path by default. |
| `48-zbt-qmodem-monitor-defaults` | Seeds hardened QModem monitor defaults while keeping monitoring disabled by default. |
| `72-zbt-z8803be-wifi` | Seeds WiFi SSIDs, WPA3 defaults, PH country code, and channel plan. |
| `76-zbt-z8803be-admin-password` | Seeds the default admin password. |
| `80-zbt-z8803be-dns-cache` | Pins dnsmasq to deterministic public DNS and larger cache. |
| `86-zbt-adguardhome-defaults` | Installs embedded AdGuardHome APKs and configures AdGuardHome plus dnsmasq. |
| `88-zbt-z8803be-services` | Enables board services. |
| `96-zbt-z8803be-luci-defaults` | Seeds LuCI defaults. |

## WiFi architecture

The firmware uses the stock OpenWrt wireless stack plus board-specific defaults in `72-zbt-z8803be-wifi`.

Factory defaults:

| Band | Channel | Width | SSID pattern |
|------|---------|-------|--------------|
| 2.4 GHz | `11` | `EHT20` | `WIFI7-<MAC6>` |
| 5 GHz | `149` | `EHT80` | `WIFI7-5G-<MAC6>` |
| 6 GHz | `37` | `EHT160` | `WIFI7-6G-<MAC6>` |

All radios are pinned to country `PH`, set `cell_density=0`, and clear firmware-side `txpower`, `min_tx_power`, `channels`, and `scan_list` clamps so the kernel regulatory database and driver define the usable channel/power set.

The default wireless interfaces are WPA3-SAE with PMF required. MLO is intentionally off at factory defaults; the `luci-app-mlo` package lets users opt into MLO from LuCI.

## Modem and failover architecture

The firmware is designed around primary wired WAN with dormant cellular stubs on the `wwan0` data path.

Key pieces:

- `.buildenv/zbt8803be.config` selects QMI, MBIM, NCM, MHI, USB serial, QModem Next, QModem monitor, and helper tools.
- `32-zbt-z8803be-wan-failover` sets `network.wan.metric=10` and `network.4_1.metric=200` so wired WAN is the only default route at first boot.
- `32-zbt-z8803be-wan-failover` creates dormant `4_1` and `4_1v6` netifd `proto=none` stubs bound to `wwan0` so firewall4 can bind cellular to the WAN masquerade zone if it is explicitly enabled later.
- `48-zbt-qmodem-monitor-defaults` configures QModem monitor with a direct HTTP/204 probe at `http://142.250.23.94/generate_204`, interval `10`, threshold `6`, and monitor cooldown `300`, while leaving `monitor_enabled=0`.
- `usr/sbin/zbt-modem-reboot-guard` gates monitor-triggered soft reboots with boot grace, lockout, AT-port resolution, and no-SIM checks.
- `usr/sbin/zbt-modem-soft-reboot` centralizes modem soft-reboot execution for QModem, monitor, and manual paths.

## DNS architecture

DNS defaults are deterministic and avoid operator-pushed resolver races:

- `32-zbt-z8803be-wan-failover` sets `peerdns=0` on wired and cellular interfaces.
- `40-zbt-qmodem-dns-suppress` prevents QModem from adding operator DNS.
- `80-zbt-z8803be-dns-cache` sets dnsmasq `noresolv=1`, cache size `10000`, and fixed public forwarders as a deterministic fallback.
- `86-zbt-adguardhome-defaults` installs the embedded AdGuardHome APKs from `/usr/share/zbt/apk/`, writes the default DoH/filter configuration, and rewires dnsmasq to forward LAN DNS through `127.0.0.1#5454`.

Post-flash setup scripts or local deployments can still replace the dnsmasq server list later.

## Local LuCI apps

Local packages extend LuCI without changing the core OpenWrt web stack:

| Package | Purpose |
|---------|---------|
| `luci-app-zbt-about` | Displays build and project information. |
| `luci-app-zbt-temperature` | Logs and charts system, WiFi, modem, and fan telemetry from tmpfs. |
| `luci-app-zbt-modem-events` | Records modem health transitions, USB/netifd events, monitor state, and explicit internet probe results. |
| `luci-app-mlo` | Provides WiFi 7 MLO configuration controls. |

The temperature and modem-events apps use tmpfs-backed history under `/var/log` to avoid flash wear.

## Feed architecture

`feeds.conf.default` pins upstream OpenWrt package, LuCI, routing, telephony, and video feeds. It also adds selected ImmortalWrt overlay feeds, FUjr/QModem, and Waujito/youtubeUnblock.

OpenWrt 25.12.2 feeds stay first and take precedence. The overlay feeds supply packages that are not available in the upstream base or are intentionally vendored for this build.

## Release architecture

Release metadata is maintained in Markdown under `releases/`:

- `releases/README.md` documents the local staging process and current checksums.
- `releases/RELEASE_NOTES.md` is the English GitHub release body.
- `releases/RELEASE_NOTES.zh-CN.md` is the Chinese release-notes asset.

Firmware binaries, buildinfo files, and checksums in `releases/` are ignored by git except Markdown documentation.
