# ZBT-Z8803BE OpenWrt 25.12.2 stable port

[English](RELEASE_NOTES.md) | [中文](RELEASE_NOTES.zh-CN.md)

> **Community build.** Maintained by a single contributor; expect rough edges. Bug reports and pull requests are welcome.

Custom OpenWrt build for the **ZBTLink ZBT-Z8803BE** WiFi 7 router.

- **Release tag:** `v25.12.2-1-zbt8803be`
- **OpenWrt base:** official `v25.12.2` / `r32802-f505120278`
- **ZBT source commit:** `af51d54e00`
- **Kernel:** `6.12.74`
- **Target:** `mediatek/filogic`
- **Default login:** `root` / `admin`

## What's new

- **Rebased to official OpenWrt `v25.12.2`.** The branch is now a clean stable-tag base with the ZBT-Z8803BE board support and firmware customizations ported on top. The build uses the stable `6.12.74` kernel from OpenWrt 25.12.2.
- **Ported ZBT-Z8803BE board support.** Includes DTS/image profile, board LED/network/GPIO switch setup, NAND upgrade support, base-files overlays, modem LED services, QModem defaults, WAN/WWAN metric defaults, APK feed defaults, LuCI defaults, and ZBT shell/banner defaults.
- **Integrated the built-in ZBT temperature monitor and fan policy.** The firmware ships `luci-app-zbt-temperature`, `/usr/sbin/zbt-temperature-log`, cron-backed tmpfs history, CPU/WiFi/modem/fan sampling, and the userspace fan governor from the previous build work.
- **Added the built-in ZBT modem event history.** The firmware ships `luci-app-zbt-modem-events`, `/usr/sbin/zbt-modem-events`, cron-backed tmpfs event history, USB/netifd/watchdog/QModem hooks, explicit `wwan0` internet probe state, and a LuCI **Services → Modem Events** page with 7-day event cards, recovery counters, and downtime estimated only from down/recovered pairs.
- **Added max-temperature avoid-limit overlays to the temperature charts.** Different sensor families now get different limit lines: SDR/mmWave modem sensors at 75°C, modem system sensors at 80°C, modem CPU/DSP/PHY sensors at 85°C, WiFi sensors at 85°C, and system CPU/SoC sensors at 90°C. Tooltips and the summary table show limit/headroom per sensor.
- **Fixed QModem soft reboot.** Manual LuCI soft reboot, QModem shutdown soft reboot, and the ZBT modem watchdog now route through `/usr/sbin/zbt-modem-soft-reboot`, which tries `sms_tool`, `sms_tool_q`, `tom_modem`, and QModem's AT helper with real success/failure reporting. A board-guarded uci-default overlays the patched QModem scripts on first boot/sysupgrade.
- **Hardened no-SIM modem monitoring.** QModem monitor and the ZBT modem reboot guard now query `AT+CPIN?` and skip modem reboot actions when the modem reports no SIM inserted, preventing unnecessary USB/modem reset loops on deployments without a SIM card.
- **Added QModem monitor action cooldown.** The patched monitor now skips reboot actions for the first 5 minutes after router boot and for 5 minutes after each monitor-triggered modem action, preventing immediate post-boot modem resets and repeated restart loops during carrier attach.
- **Hardened QModem connectivity checks.** Firmware defaults now use direct-IP HTTP/204 probing at `http://142.250.23.94/generate_204`, a 30 second monitor interval, and a 10 failure threshold. The monitor curl path also has `--max-time 15`, so transient DNS/carrier hiccups are less likely to trigger unnecessary modem actions.
- **Adjusted default WiFi channel plan for regulatory-safe separation.** Default channels are now 2.4 GHz ch11/EHT20, 5 GHz ch149/EHT80, and 6 GHz ch37/EHT160. For multi-AP deployments in the PH lower-6 GHz range, EHT160 enables three separated PSC blocks such as ch5, ch37, and ch69.
- **Removed firmware-side WiFi power/channel clamps for PH.** First boot keeps `country=PH`, sets `cell_density=0`, and clears any `txpower`, `min_tx_power`, `channels`, or `scan_list` values so `wireless-regdb` and the driver expose the full PH-allowed channel set and automatic regulatory maximum transmit power.
- **Smoothed PWM fan policy.** The board fan cooling table now exposes 7 levels `<0 80 112 144 176 216 255>`, and the temperature logger drives them from the highest system/WiFi/modem temperature so 100% fan is reserved for hotter conditions. On the older 3-state runtime, the same governor now drops from 100% back to medium around the mid-50°C range instead of holding full speed below 60°C.
- **Bumped feeds to latest compatible heads.** OpenWrt packages/LuCI/routing/video feeds are pinned to current compatible heads, while telephony remains at the stable 25.12 pin. ImmortalWrt overlay feeds and FUjr/QModem are also refreshed. Unused recursive Kconfig LuCI apps from the overlay are pruned by the build harness after feed install.
- **Ported vendored `autocore` and `cpufreq`.** These keep the selected LuCI monitoring/governor packages buildable on the official 25.12.2 base without depending on the old setup-script tree.

## Validation

- `node --check` passed for the custom LuCI JavaScript views.
- Shell syntax checks passed for ZBT base-files scripts, init scripts, hotplug scripts, uci-defaults, and package scripts.
- LuCI menu/ACL JSON files passed `python3 -m json.tool`.
- `./.buildenv/build.sh feeds` and `./.buildenv/build.sh config` completed with selected ZBT packages present.
- Full `./.buildenv/build.sh build` completed successfully.
- Rebuilt sysupgrade rootfs was streamed from squashfs and verified to contain the QModem monitor cooldown code, direct-IP `30s/10×` monitor defaults, curl `--max-time 15`, `qmodem.main.zbt_monitor_cooldown=300`, the updated EHT160 WiFi channel defaults, the PH no-clamp WiFi defaults, and the baked `luci-app-zbt-modem-events` package files/service symlinks.
- Release manifest, checksums, and buildinfo have no stale testing-kernel package references.
- Live router runtime patch verification was performed for the Modem Events UI, temperature UI, and QModem soft-reboot path; only a harmless `AT` command was sent for AT-port/tool validation.

## Checksums

```text
7920ca111cd83f09b84613ff204237887dd6e801175f8ea37421b9783ea1760b  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
8574017bbdfd41ab4f52eec40645dab95e3dc9502056e7dd1197f85a242b9e83  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
f41ebb5fa5de5e6b2d890b482f2c9e0cf8e65dbe1423521eb265f319c806c0d0  openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
ee41d729ac47cc419880e2347792eb5c42fbb201485431a9d7e284d69bc83f80  sha256sums
```

## Included

- Mainline OpenWrt 25.12.2 base, no MediaTek vendor feed required.
- WiFi 7 tri-band with MLO support and EHT320 capability; defaults use EHT160 on 6 GHz for safer multi-AP separation.
- LuCI HTTPS, Argon dark theme/config, package manager, **System → About this build**, MLO app, ZBT temperature monitor, and ZBT modem event history.
- QModem Next JS UI with SMS, Monitor, AT Debug, SIM Switch, watchdog defaults, and robust soft reboot.
- QMI/MBIM/NCM/MHI/USB modem stack with `sms_tool_q`, `tom_modem`, and `quectel-CM-5G-M`.
- Firmware-enabled modem LED services and state poller.
- First-boot WAN failover defaults: WAN metric `10`, WWAN/QModem metric `20`.
- youtubeUnblock + LuCI app for SNI-fragmentation DPI bypass, disabled by default and scoped by firmware defaults.
- WireGuard, SQM/CAKE, DDNS, Samba, Diskman, statistics, autocore, cpufreq, WiFi history, and diagnostic CLI tools.

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
