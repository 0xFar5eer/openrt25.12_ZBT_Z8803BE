# ZBT-Z8803BE OpenWrt r34167

[English](RELEASE_NOTES.md) | [中文](RELEASE_NOTES.zh-CN.md)

> **Community build.** Maintained by a single contributor; expect rough edges. Bug reports and pull requests are very welcome.

Custom OpenWrt build for the **ZBTLink ZBT-Z8803BE** WiFi 7 router.

- **Build:** `r34167+2-cfb4b100d1`
- **Kernel:** `6.12.74`
- **Target:** `mediatek/filogic`
- **Default login:** `root` / `admin`

## What's new

- **Added: cellular link self-heals when the carrier silently drops the PDP context.** Wires `qmodem_monitor` out of the box on every modem-device section: 15 s curl probe to `http://www.gstatic.com/generate_204` (the same captive-portal probe Android uses, always allowed past Smart / Globe PH carrier filtering), threshold 4 (≈60–80 s detection window), `monitor_action=run_scripts` dispatching to a new `/usr/sbin/zbt-modem-reboot-guard`. The guard issues `AT+CFUN=1,1` (3GPP soft reset, ~30 s re-attach) only when both gates pass: (a) router uptime ≥ 5 min so cold-boot dial sequences complete first, and (b) no other reboot fired in the last 5 min so a flapping carrier can't pile back-to-back resets. Both grace windows are tunable via `/etc/config/qmodem` main-section options `zbt_reboot_boot_grace` and `zbt_reboot_lockout`. Why curl, not ping: Smart / Globe PH blackhole ICMP from cellular IPs to most public space (including their own gateway and `1.1.1.1` / `8.8.8.8`); only `9.9.9.9` is reliable for ICMP and not stable enough to bet a watchdog on. HTTP/204 to gstatic exercises the full stack USB → modem firmware → RAN → GGSN → internet → DNS → TCP → HTTP, so when it fails the data path really is broken. Why no kernel-level fix: the carrier-side blackhole leaves the modem in a `registered + L1 + L2 + IP assigned + L3 dead` state that is invisible to `qmi_wwan` and netifd — only an end-to-end probe can see it. New files: `etc/uci-defaults/45-zbt-qmodem-monitor-enable`, `usr/sbin/zbt-modem-reboot-guard`.
- **Fixed: qmodem_monitor's curl / ping probes ran via the wrong WAN on multi-uplink builds.** The upstream FUjr/QModem feed's `update_netcfg()` had three independent bugs in `NET_DEV` resolution: (1) treated the literal dash `-` (qmodem's "no alias" placeholder) as a real alias and looked up `network.-.ifname` which never exists; (2) only read the legacy `option ifname`, missing modern netifd's canonical `option device` written for new wwan interfaces (21.02+); (3) had no fallback from alias-name (a human-readable display name such as `modem1`) to modem-id (e.g. `4_1`, the actual UCI section name qmodem maintains). Together these dropped `NET_DEV` to empty in every fresh deployment shape — `curl` then ran without `--interface` and probed via the system default route, often the OTHER WAN on a multi-uplink router (e.g. `br-wan` on a tether-failover deployment when `wwan0` was the monitored modem). Any flakiness on that other path then triggered chronic false-positive reboots against a healthy modem every ~6 minutes. The patched copy of `modem_monitor.sh` ships as a base-files overlay at `/usr/lib/zbt/qmodem-modem_monitor.sh` and is copied into `/usr/share/qmodem/modem_monitor.sh` by the new `46-zbt-qmodem-monitor-patch` uci-default on every boot when the live file differs (idempotent via `cmp`). Survives package upgrades and re-runs after sysupgrade. Belt-and-suspenders: `30-zbt-z8803be-wan-failover` now also mirrors `device` → `ifname` on `network.4_1` for any pre-r34167 firmware that hasn't yet picked up the patched monitor.
- **Fixed: youtubeUnblock DPI bypass killed cellular WWAN traffic when enabled.** The userspace daemon's fragmented TLS ClientHello is silently dropped by the on-board 5G modem path — the carrier's middlebox sees malformed TCP and resets the flow, while the S23 USB tether on `br-wan` re-NATs in its baseband so DPI bypass works there. Reworked `99a-zbt-youtubeunblock-disable` to: (a) pin `all_domains=0` and pre-seed `sni_domains` with `binance.com`, `bnbstatic.com`, `binance.org` (the only DPI hijack observed on Smart / Globe PH; YouTube / Google / Cloudflare flow without interference); (b) replace the package's auto-loaded nft template with a `br-wan`-scoped version (`oifname != "br-wan" return` short-circuits non-tether egress out of the chain so `wwan0` is never enqueued). Service still ships disabled; behaviour for fresh flashes that don't opt in is unchanged. Operators that re-enable it now get bypass on the tether path without breaking modem dial.
- **Fixed: cellular WWAN double-NATted out of the box, breaking inbound port forwards and PMTUD.** qmodem's stock `donot_nat=0` default makes the Quectel firmware run `AT+QCFG="nat",1` on every dial, so the modem internally NATs `wwan0` traffic behind a fake `192.168.225.x/24` IP. fw4's wan-zone masquerade then NATs a *second* time, with three knock-on effects: (a) port forwards punched on the OpenWrt side never reach the WAN because the modem's hidden NAT table doesn't know about them; (b) PMTUD breaks because upstream `ICMP frag-needed` lands on the modem's NAT instead of fw4; (c) `quectel-CM-M`'s IP-attach handler reports the fake `192.168.225.x` to netifd as the WAN address. `35-zbt-qmodem-dns-suppress` now also asserts `qmodem.<sec>.donot_nat=1` on every modem-device section + the 4_1 pre-seed, so `modem_dial.sh` sends `AT+QCFG="nat",0`, the modem stops NATting, and the carrier-assigned (CGNAT) IP surfaces directly on `wwan0`. Verified across `feeds/qmodem` source (`modem_dial.sh:153`/`:776`, `network_config.js:342`).
- **Documented: firmware now ships an explicit auto-APN contract for the cellular qmodem section.** Header comment on `35-zbt-qmodem-dns-suppress` was rewritten to enumerate what we set (do_not_add_dns=1, donot_nat=1) and what we deliberately leave at qmodem's default (apn unset, force_set_apn=0, pdp_type=ipv4v6, pre_dial_at_cmds unset). On PH carriers (Smart, Globe), letting `quectel-CM-M` auto-detect the carrier-blessed APN is the only configuration that gets through QMI-WDS PDN setup; forcing any client-side APN was observed to trigger `QMUXError=0xe` (`PDN_REQUEST_REJECTED`) loops with the Quectel RM551E firmware. Setup scripts may still override at runtime if a specific deployment needs it, but the firmware-shipped default is now auto-everything.
- **Fixed: DNS broken on fresh `sysupgrade -n` while raw-IP routing still worked.** The previous DNS-neutral default in r34158 let `udhcpc` on `wan` write operator-pushed DNS into `/tmp/resolv.conf.d/resolv.conf.auto` BEFORE uci-defaults could intervene. dnsmasq then forwarded queries in round-robin to operator DNS alongside any seeded fallback. On Globe / Smart / Smart Bro PH a transient operator-DNS NXDOMAIN burst made the router boot with intermittent name resolution: `ping 1.0.0.1` worked, `ping cloudflare.com` and `apk update` failed. Reworked the firmware DNS contract end-to-end so a fresh flash now resolves out-of-the-box on any uplink:
  - `90-zbt-z8803be-dns-cache` sets `noresolv=1` (dnsmasq ignores `resolv.conf.auto` entirely) and pins `option server` to `1.1.1.1` / `1.0.0.1` / `8.8.8.8` / `8.8.4.4`. Deterministic public DNS regardless of which uplink came up first.
  - `35-zbt-qmodem-dns-suppress` (new) seeds `qmodem.4_1.do_not_add_dns=1` so the qmodem dial path adds `-D` to `quectel-CM-M`, which stops it from rewriting `/etc/resolv.conf` on every redial. Idempotent across qmodem's first-detect path (uses `modem-device` section type so qmodem's IF branch in `modem_scan.sh:473` preserves our flag).
  - `30-zbt-z8803be-wan-failover` keeps `peerdns=0` on `wan` / `4_1` and seeds `system.zbt_wwan_dns.enabled='0'` so the operator-DNS-capture hotplug ships disabled by default.
  - Setup scripts that prefer operator DNS, AdGuardHome, Pi-hole or any other resolver chain can replace the seeded server list (last-write-wins) - see the `DOWNSTREAM OVERRIDE` block in `90-zbt-z8803be-dns-cache`.
- **Added: factory-reset modem on first flash to clear stale PDP / APN state.** New `15-zbt-modem-factory-reset-flag` writes a one-shot marker on fresh sysupgrade; `hotplug.d/usb/29-zbt-modem-factory-reset` fires on first USB detection, waits up to 20 s for the AT port, resets the PDP context to auto-APN, persists settings, and reboots the modem with `AT+CFUN=1,1`. Mitigates the carrier-lockup case where a modem flashed during a transient operator outage stays stuck on a half-attached PDP context indefinitely.
- **Hardened: qmodem watchdog ifup recovery.** Refactored `usr/sbin/zbt-qmodem-watchdog-loop` into a standalone procd-managed loop with by-name firewall-zone resolution (was @zone[1], drifts when LuCI inserts other zones), reassertion of `network.4_1` proto=none stub on netifd state desync, and an `ifup 4_1` retry path with `network reload` on failure. Watchdog now self-heals from the post-flash `wwan0 carrier=1 but no IP` state without manual intervention.
- **Fixed: cellular failover dead after a fresh `sysupgrade -n`.** FUjr/QModem creates the `qmodem.4_1` UCI section with `state='disabled'` on first USB-modem detection, so `qmodem_network` never starts `quectel-CM-M` and `wwan0` never gets an IP. Previous firmware masked this by preserving config across upgrades; clean wipes show the bug. `hotplug.d/usb/30-zbt-qmodem-autoenable` fires on Quectel modem detection (idVendor=2c7c), waits for the qmodem section to appear, flips `state=enabled`, re-asserts `network.4_1` / `4_1v6` proto=none stubs (fw4 needs them to bind `wwan0` to the wan zone for masquerade), restarts `qmodem_network`. WWAN now dials on first boot. (Coordinates with the new factory-reset hotplug above via marker file to avoid races.)

## Checksums

```text
c1f49dbeca4a6e171aaeadae1b4a3978fb6453efed4e7942651be9cd41ab96f6  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin
c10faa3a101b24f81ab81ec1d59121918568771fdb1a42b47bb18f9747feffd2  openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin
bdd8a1214f2f410d7212f9ffe975db6bde0c4cd35984b4171306698c51bc6a20  openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest
```

## Included

- Mainline OpenWrt base, no MediaTek vendor feed.
- WiFi 7 tri-band with EHT320 and MLO support.
- PH WiFi regulatory patch for full local 6 GHz testing.
- LuCI HTTPS, Argon dark theme, Chinese translations, **System → About this build** page with releases URL and contact info.
- QModem Next JS UI with SMS, Monitor, AT Debug, and SIM Switch.
- QMI/MBIM/NCM/MHI/USB modem stack with `sms_tool_q`.
- Firmware-enabled modem LED services and state poller.
- Slot 1 modem power on by default; slot 2 off by default.
- First-boot WAN failover defaults seed WAN metric `10` and WWAN/QModem metric `20`.
- youtubeUnblock + LuCI app for SNI-fragmentation DPI bypass (disabled by default; defaults override fragments **all** SNIs when toggled on).
- WireGuard, SQM/CAKE, DDNS, Samba, Diskman, statistics, autocore.
- DNS cache bump, APK feeds, shell banner/color prompt/tools.
- Diagnostic CLI toolkit pre-installed: `nohup`, `timeout`, `stdbuf`, `dig`, `host`, `lsof`, `strace`, `watch`, `screen`, `socat`, `arping`, plus `htop`, `nano`, `mtr`, `tcpdump`, `ethtool`, `iperf3`, `curl`, `ip-full`.

## Verified

Validated:

- WAN internet OK
- WWAN failover works when the WAN link drops
- failover metrics persist correctly after reboot
- WiFi/MLO active
- QModem Next and SIM Switch OK
- modem LED services active

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

## Notes

- SFP+ is included but not physically verified here.
- Hardware NAT/offload is not enabled.
- The PH regulatory patch is for private/local testing. Use responsibly.
- **Attended Sysupgrade is intentionally not included.** This build ships from GitHub Releases (not `downloads.openwrt.org`), so the buildbot-driven Attended Sysupgrade flow would either error out or offer a generic mainline SNAPSHOT image without our package set. Upgrade by downloading the new `squashfs-sysupgrade.bin` from this releases page and flashing it via **LuCI -> System -> Backup/Flash firmware** or `sysupgrade <file>` over SSH.

## Support / contact

- **Issues / PRs:** https://github.com/0xFar5eer/openwrt25.12_ZBT_Z8803BE/issues
- **Telegram:** https://t.me/Far5eer

The same info is also shown in the SSH banner on every login and at **LuCI -> System -> About this build**.

## Credits

- [@pttuan](https://github.com/pttuan) — upstream OpenWrt board port via [openwrt#23053](https://github.com/openwrt/openwrt/pull/23053).
- [FUjr/QModem](https://github.com/FUjr/QModem) — QModem Next UI + built-in SIM Switch.
- [OneB1t/Z8803BE-research](https://github.com/OneB1t/Z8803BE-research) — vendor firmware research.
- [OpenWrt mainline](https://openwrt.org) and [ImmortalWrt](https://github.com/immortalwrt) — base distribution and overlays.
