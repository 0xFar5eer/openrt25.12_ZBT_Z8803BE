# ZBT-Z8803BE OpenWrt 25.12.2 stable port

[English](RELEASE_NOTES.md) | [中文](RELEASE_NOTES.zh-CN.md)

> **Community build.** Maintained by a single contributor; expect rough edges. Bug reports and pull requests are welcome.

Custom OpenWrt build for the **ZBTLink ZBT-Z8803BE** WiFi 7 router.

- **Release tag:** `v25.12.2-1-zbt8803be`
- **OpenWrt base:** official `v25.12.2` / `r32802-f505120278`
- **ZBT source commit:** `a591de1c5c`
- **Kernel:** `6.12.74`
- **Target:** `mediatek/filogic`
- **Default login:** `root` / `admin`

## What's new

- **Rebased to official OpenWrt `v25.12.2`.** The branch is now a clean stable-tag base with the ZBT-Z8803BE board support and firmware customizations ported on top. The build uses the stable `6.12.74` kernel from OpenWrt 25.12.2.
- **Ported ZBT-Z8803BE board support.** Includes DTS/image profile, board LED/network/GPIO switch setup, NAND upgrade support, base-files overlays, modem LED services, QModem defaults, WAN/WWAN metric defaults, APK feed defaults, LuCI defaults, and ZBT shell/banner defaults.
- **Integrated the built-in ZBT temperature monitor and fan policy.** The firmware ships `luci-app-zbt-temperature`, `/usr/sbin/zbt-temperature-log`, cron-backed tmpfs history, CPU/WiFi/modem/fan sampling, and the userspace fan governor from the previous build work.
- **Added max-temperature avoid-limit overlays to the temperature charts.** Different sensor families now get different limit lines: SDR/mmWave modem sensors at 75°C, modem system sensors at 80°C, modem CPU/DSP/PHY sensors at 85°C, WiFi sensors at 85°C, and system CPU/SoC sensors at 90°C. Tooltips and the summary table show limit/headroom per sensor.
- **Fixed QModem soft reboot.** Manual LuCI soft reboot, QModem shutdown soft reboot, and the ZBT modem watchdog now route through `/usr/sbin/zbt-modem-soft-reboot`, which tries `sms_tool`, `sms_tool_q`, `tom_modem`, and QModem's AT helper with real success/failure reporting. A board-guarded uci-default overlays the patched QModem scripts on first boot/sysupgrade.
- **Hardened no-SIM modem monitoring.** QModem monitor and the ZBT modem reboot guard now query `AT+CPIN?` and skip modem reboot actions when the modem reports no SIM inserted, preventing unnecessary USB/modem reset loops on deployments without a SIM card.
- **Bumped feeds to latest compatible heads.** OpenWrt packages/LuCI/routing/video feeds are pinned to current compatible heads, while telephony remains at the stable 25.12 pin. ImmortalWrt overlay feeds and FUjr/QModem are also refreshed. Unused recursive Kconfig LuCI apps from the overlay are pruned by the build harness after feed install.
- **Ported vendored `autocore` and `cpufreq`.** These keep the selected LuCI monitoring/governor packages buildable on the official 25.12.2 base without depending on the old setup-script tree.

## Validation

- `node --check` passed for the custom LuCI JavaScript views.
- Shell syntax checks passed for ZBT base-files scripts, init scripts, hotplug scripts, uci-defaults, and package scripts.
- LuCI menu/ACL JSON files passed `python3 -m json.tool`.
- `./.buildenv/build.sh feeds` and `./.buildenv/build.sh config` completed with selected ZBT packages present.
- Full `./.buildenv/build.sh build` completed successfully.
- Extracted output has `stale_apks=0` and no stale testing-kernel package references in the final target package output.
- Live router runtime patch verification was performed for the temperature UI and QModem soft-reboot path; only a harmless `AT` command was sent for AT-port/tool validation.

## Checksums

```text
d65a5e08ee5942da455f8077e5a2cdce2a9fffd22ef2666ac5635c6ed02a26e4  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
60e13475c91d75b3fe794dda58082db9b81abae8a6aa914a6d25f4fc1cd28d1b  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
2e88ffecfc99b0720f3664ec1cd4306e47bc39b925d64a12d812a4e052ab757c  openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
9ff2ae72b3a2ce65654563efffadaa1f932c27a560ac553a0c753225f3015063  sha256sums
```

## Included

- Mainline OpenWrt 25.12.2 base, no MediaTek vendor feed required.
- WiFi 7 tri-band with EHT320 and MLO support.
- LuCI HTTPS, Argon dark theme/config, package manager, **System → About this build**, MLO app, and ZBT temperature monitor.
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
