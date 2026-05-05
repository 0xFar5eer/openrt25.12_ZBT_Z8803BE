# ZBT-Z8803BE OpenWrt 25.12.2 stable port

[English](RELEASE_NOTES.md) | [中文](RELEASE_NOTES.zh-CN.md)

> **Community build.** Maintained by a single contributor; expect rough edges. Bug reports and pull requests are welcome.

Custom OpenWrt build for the **ZBTLink ZBT-Z8803BE** WiFi 7 router.

- **Release tag:** `v25.12.2-2-zbt8803be`
- **OpenWrt base:** official `v25.12.2` / `r32802-f505120278`
- **Kernel:** `6.12.74`
- **Target:** `mediatek/filogic`
- **Default login:** `root` / `admin`
- **In-firmware summary:** **About** (`/cgi-bin/luci/admin/about`) is the canonical feature/package/fix summary; this release note keeps the same categories and adds validation, checksums, and flash steps.

## What's new

- **Rebased to official OpenWrt `v25.12.2`.** The branch is now a clean stable-tag base with the ZBT-Z8803BE board support and firmware customizations ported on top. The build uses the stable `6.12.74` kernel from OpenWrt 25.12.2.
- **Ported ZBT-Z8803BE board support.** Includes DTS/image profile, board LED/network/GPIO switch setup, NAND upgrade support, base-files overlays, modem LED services, QModem defaults, WAN/WWAN metric defaults, APK feed defaults, LuCI defaults, and ZBT shell/banner defaults.
- **Integrated the built-in ZBT temperature monitor and fan policy.** The firmware ships `luci-app-zbt-temperature`, `/usr/sbin/zbt-temperature-log`, cron-backed tmpfs history, CPU/WiFi/modem/fan sampling, and the userspace fan governor from the previous build work.
- **Added the built-in ZBT Health page.** The firmware ships `luci-app-zbt-health`, `/usr/sbin/zbt-health-json`, a read-only LuCI **Services → Health** page, and a late-loading Services menu override for quick router health, overlay/storage, RAM, conntrack, uptime, and write-hotspot checks.
- **Reordered the LuCI Services menu.** Services now prioritizes Health, WiFi Clients, WiFi Client History, Traffic Statistics, System Statistics, Temperature, Modem Events, youtubeUnblock, and AdGuard Home. WiFi Client History and System Statistics are direct Services views, not aliases that redirect back to Status/Statistics.
- **Moved QoSmate in the Services menu.** QoSmate now sits after Modem Events so observability and modem recovery pages stay grouped before tuning/traffic-shaping tools.
- **Expanded the top-level About page.** The firmware now documents release identity, OpenWrt base, feature groups, fixes vs stock/vendor firmware, included package families, support links, and credits from inside LuCI.
- **Unified custom LuCI app styling.** About, Health, Temperature, Modem Events, WiFi Clients, Traffic Statistics, and MLO now share the ZBT theme CSS for consistent cards, tables, buttons, filter controls, and About credits spacing.
- **Improved Traffic Statistics UI polish.** Date filters and table action buttons now use the shared ZBT theme instead of legacy blue/purple button styles, and table row/action alignment is normalized.
- **Added BusyBox-compatible deployment safety.** Firmware includes a small `/usr/bin/install` compatibility shim, setup scripts avoid GNU `install` assumptions by using `cp`/`chmod`, and `git`/`git-http` are selected for runtime/developer convenience.
- **Removed the redundant System About alias.** The only About entry is now the top-level **About** page at `/admin/about`.
- **Added the built-in ZBT modem event history.** The firmware ships `luci-app-zbt-modem-events`, `/usr/sbin/zbt-modem-events`, cron-backed tmpfs event history, USB/netifd/watchdog/QModem hooks, explicit `wwan0` internet probe state, and a LuCI **Services → Modem Events** page with 7-day event cards, recovery counters, and downtime estimated only from down/recovered pairs.
- **Reduced Modem Events startup noise.** Modem Events now records router restarts as downtime boundaries, suppresses low-level startup health noise during the grace period, and focuses the UI on internet down/recovered/OK, monitor actions, router restarts, and modem reboot events.
- **Added max-temperature avoid-limit overlays to the temperature charts.** Different sensor families now get different limit lines: SDR/mmWave modem sensors at 75°C, modem system sensors at 80°C, modem CPU/DSP/PHY sensors at 85°C, WiFi sensors at 85°C, and system CPU/SoC sensors at 90°C. Tooltips and the summary table show limit/headroom per sensor.
- **Fixed QModem soft reboot.** Manual LuCI soft reboot, QModem shutdown soft reboot, and the ZBT modem watchdog now route through `/usr/sbin/zbt-modem-soft-reboot`, which tries `sms_tool`, `sms_tool_q`, `tom_modem`, and QModem's AT helper with real success/failure reporting. A board-guarded uci-default overlays the patched QModem scripts on first boot/sysupgrade.
- **Hardened no-SIM modem monitoring.** QModem monitor and the ZBT modem reboot guard now query `AT+CPIN?` and skip modem reboot actions when the modem reports no SIM inserted, preventing unnecessary USB/modem reset loops on deployments without a SIM card.
- **Added QModem monitor action cooldown.** The patched monitor now skips reboot actions for the first 5 minutes after router boot and for 5 minutes after each monitor-triggered modem action, preventing immediate post-boot modem resets and repeated restart loops during carrier attach.
- **Hardened QModem connectivity checks.** Firmware defaults now use direct-IP HTTP/204 probing at `http://142.250.23.94/generate_204`, a 30 second monitor interval, and a 10 failure threshold. The monitor curl path also has `--max-time 15`, so transient DNS/carrier hiccups are less likely to trigger unnecessary modem actions.
- **Adjusted default WiFi channel plan for regulatory-safe separation.** Default channels are now 2.4 GHz ch11/EHT20, 5 GHz ch149/EHT80, and 6 GHz ch37/EHT160. For multi-AP deployments in the PH lower-6 GHz range, EHT160 enables three separated PSC blocks such as ch5, ch37, and ch69.
- **Removed firmware-side WiFi power/channel clamps for PH.** First boot keeps `country=PH`, sets `cell_density=0`, and clears any `txpower`, `min_tx_power`, `channels`, or `scan_list` values so `wireless-regdb` and the driver expose the full PH-allowed channel set and automatic regulatory maximum transmit power.
- **Improved Traffic Statistics defaults and empty-state UX.** Domain tracking now defaults to enabled in setup while the database path, 90-day retention, daily cleanup, 90-day inactive-device cleanup, 604800-second domain cache TTL, Auto DNS backend, and Info log level are preselected. Device/domain views now warn when monitoring/domain tracking is disabled, tables are not initialized, or no data exists yet.
- **Fixed domain table visibility.** Top Domains and Device Domains no longer hide sub-1 KiB rows, so any recorded domain traffic can be inspected.
- **Fixed WiFi Clients recursive iframe rendering.** The LuCI app now renders the generated WiFi Clients HTML directly with isolated styling and polling instead of embedding it inside an iframe.
- **Smoothed PWM fan policy.** The board fan cooling table now exposes 7 levels `<0 80 112 144 176 216 255>`, and the temperature logger drives them from the highest system/WiFi/modem temperature so 100% fan is reserved for hotter conditions. On the older 3-state runtime, the same governor now drops from 100% back to medium around the mid-50°C range instead of holding full speed below 60°C.
- **Bumped feeds to latest compatible heads.** OpenWrt packages/LuCI/routing/video feeds are pinned to current compatible heads, while telephony remains at the stable 25.12 pin. ImmortalWrt overlay feeds and FUjr/QModem are also refreshed. Unused recursive Kconfig LuCI apps from the overlay are pruned by the build harness after feed install.
- **Ported vendored `autocore` and `cpufreq`.** These keep the selected LuCI monitoring/governor packages buildable on the official 25.12.2 base without depending on the old setup-script tree.

## Validation

- `node --check` passed for the custom LuCI JavaScript views.
- Three engineering code-review rounds were run against the touched LuCI/theme/docs/setup files, with follow-up artifact and rootfs verification after rebuild.
- Shell syntax checks passed for ZBT base-files scripts, init scripts, hotplug scripts, uci-defaults, and package scripts.
- LuCI menu/ACL JSON files passed `python3 -m json.tool`.
- `./.buildenv/build.sh feeds` and `./.buildenv/build.sh config` completed with selected ZBT packages present.
- Full `./.buildenv/build.sh build` completed successfully.
- Rebuilt sysupgrade rootfs was streamed from squashfs and verified to contain the QModem monitor cooldown code, direct-IP `30s/10×` monitor defaults, curl `--max-time 15`, `qmodem.main.zbt_monitor_cooldown=300`, the updated EHT160 WiFi channel defaults, PH no-clamp WiFi defaults, `luci-app-zbt-health`, `luci-app-zbt-modem-events`, About release tag `v25.12.2-2-zbt8803be`, shared ZBT theme CSS, Traffic Statistics theme overrides, executable `/usr/bin/install` shim, `git`/`git-http`, and WiFi Clients CGI redirect.
- Release manifest, checksums, and buildinfo have no stale testing-kernel package references.
- Live router runtime patch verification was performed for the Modem Events UI, temperature UI, and QModem soft-reboot path; only a harmless `AT` command was sent for AT-port/tool validation.

## Checksums

```text
45dfdda0204eb549a1dc127c3ef3ef2ef4c0be1ea3a048fca6925937641e5281  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
ccc242c1a7fb3ab4b2864f7b87654a7d1576aeec90791f5c72ed9b5b95ed7970  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
f2f4454deafb186712bf11a153dbb43694f0d6bd3d5c215313d670acff300df1  openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
c4898a1a2760b72c6eab640c5bfba9b08c5cf239571212b2011e815be4fa1db0  sha256sums
```

## Included

- **Platform / board support:** Mainline OpenWrt 25.12.2 base, ZBT-Z8803BE board support, NAND sysupgrade profile, WiFi 7 tri-band/MLO defaults, modem LED services, and WAN/WWAN failover defaults.
- **LuCI / observability:** HTTPS LuCI, Argon dark theme/config, package manager, shared ZBT custom app theme, top-level About, MLO app, ZBT Health, ZBT temperature monitor, ZBT modem event history, WiFi Clients, WiFi history, System Statistics, and curated Services ordering.
- **Traffic, DNS, and QoS:** wrtbwmon Traffic Statistics with device/domain tracking, AdGuard Home integration, bounded query/statistics defaults, youtubeUnblock, and QoSmate as the primary QoS/tinkering UI.
- **Modem and WAN resilience:** QModem Next JS UI, QMI/MBIM/NCM/MHI/USB modem stack, `sms_tool_q`, `tom_modem`, `quectel-CM-5G-M`, no-SIM guard, direct-IP monitor probe, cooldowns, and robust soft reboot.
- **Storage and LAN services:** WireGuard, DDNS, Samba, Diskman, statistics, autocore, cpufreq, diagnostics, `git`, `git-http`, BusyBox-compatible `install`, and CLI utilities.

## Flash

Existing OpenWrt:

```sh
sysupgrade openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
```

Clean reset:

```sh
sysupgrade -n openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
```

Recovery install:

1. Hold **Reset** while powering on.
2. Open `http://192.168.1.1`.
3. Upload the `squashfs-sysupgrade.bin` image.
4. Wait for reboot, then log in as `root` / `admin`.
