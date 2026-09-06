# ZBT-Z8803BE OpenWrt 25.12.2 / Linux 6.12.74

Release `v25.12.021` is a community firmware build for ZBTLink ZBT-Z8803BE.

**Assets refreshed in place (2026-09-06).** The two firmware binaries under this tag were replaced with rebuilds of the same release: the first pass covered the additional fixes in sections 3–5 below, and a second pass corrected the upgrade migration described in section 3, whose section-matching guard was a silent no-op. If you downloaded `v25.12.021` on this date, re-verify the SHA-256 digests in Artifacts. The package manifest and the feed tarball are byte-identical to the originals — the package set did not change.

## Highlights

This release fixes the cellular "connects, then dies seconds later" pattern reported in **issue #9** (T-Mobile US, Quectel RM551E-GL). Two independent firmware bugs were responsible, plus one aggravator.

### 1. The dialer was being restarted on every hotplug event

A leftover renumbered hotplug script (`30-zbt-qmodem-autoenable`) shipped **alongside** its replacement `40-zbt-qmodem-autoenable`. Every USB `add` event — which fires once per device *and* per interface/netdev the modem exposes — ran the old script, which unconditionally restarted `qmodem_network`. Each restart stops the dial, hangs up the PDP context and dials again. Logs showed the resulting loop: `Stop Dial and Hang` → `Start Dial Now`, and `udhcpc` releasing a lease seconds after obtaining it.

- Both scripts are now reconciled into one idempotent handler: a USB `add` only restarts the dialer when the profile was actually disabled.
- The watchdog (`zbt_qmodem_watchdog`) had a self-trigger feedback loop: its procd reload trigger watched `qmodem`/`network`/`firewall` — the very configs the loop commits — so it respawned itself and reset its boot fast-phase indefinitely. The trigger is removed; re-asserts are rate-limited per section and skipped while the link is healthy.
- The dormant WWAN stubs asserted `proto='none'` while QModem itself derives `proto='dhcp'` for a Quectel dialing QMI and rewrites any mismatch, then re-runs `ifup` (bouncing udhcpc off a live lease). The stubs now assert what QModem would write, so the rewrite never happens. The cellular metric is pinned through `qmodem.<sec>.metric`, the value QModem actually copies into the network config at dial time.
- Five more stale renumbered duplicates were removed (`00-`/`10-zbt-qmi-rawip`, `10-zbt-modem-led` with the wrong LED name `5g1`, `30-zbt-status-led`, `30-zbt-wwan-dns`, `29-zbt-modem-factory-reset`); `tests/check-zbt-firmware.sh` now guards against each of them shipping again.

### 2. T-Mobile kills the session because the modem still NATs (TTL 63)

This is the part specific to the "works for ~2 seconds, then everything dies" symptom.

The firmware asks the modem to be a transparent IP pipe (`donot_nat=1`). But in **QMI mode that request is never sent**: the AT command `AT+QCFG="nat",0` is only issued on the NCM/ECM dial path. The QMI dialer (`quectel-CM-M`) never touches modem NAT, so an RM551E-GL dialed in QMI keeps routing inside itself and hands the router an address from its own embedded DHCP server — `192.0.0.2/27` from `192.0.0.1`, not a T-Mobile address.

That costs one extra TTL decrement: forwarded traffic leaves the router at 64 (or 63 untouched) and reaches T-Mobile at **63**. US postpaid tethering policing treats "not 64" as tethering and tears the data session down a couple of seconds after attach. SMS and the initial attach still work, which matches the report exactly. A `ping` run *on the router* also dies with the session, because the kill is carrier-side, not a NAT/firewall problem on the router.

The opt-in TTL plugin (`luci-app-qmodem-ttlfw4`, **Modem → QModem → TTL**) rewrites the TTL on egress, and `ttl=65` compensates for the modem's own NAT. The seeded default of `64` is the correct value whenever the modem is a transparent IP pipe — the normal case: a carrier-assigned address on `wwan0` (including CGNAT `10.x`) means the carrier sees exactly `64`. `65` is only needed when the module still NATs, whose signatures are module-assigned addresses (`192.0.0.x`, `192.168.225.x`, `10.168.x`). Note for testers: the plugin's rule matches `iifname "br-lan"` and the firmware's permanent rule matches `oifname "wwan0"`; neither affects pings run from the router itself, so testing TTL by re-pinging on the router proves nothing — test from a **LAN client**.

New in this release, the firmware figures the right value out by itself:

- `/usr/sbin/zbt-modem-nat-probe` (fired by a new `iface` hotplug on every cellular `ifup`) looks at the address the dialer obtained: `192.0.0.x` / `192.168.225.x` / `10.168.x` → the modem is NATing → it raises `qmodem_ttl.main.ttl` to **65**; a carrier-assigned address → leaves **64**.
- It never enables the plugin for you, never restarts it while disabled, and if you hand-edit `ttl`, it permanently disables its own writes (`zbt_auto_ttl=0`) and leaves your value alone.
- The permanent TTL-64 nft rule (`/etc/nftables.d/99-tether-ttl.nft`, seeded by `36-zbt-z8803be-wan-speed-mode`) is now written only when absent, so an operator's hand-edited value — e.g. a deliberate 65 — survives a reflash instead of being reset to 64 on every boot.
- Optional manual check of the definitive answer: `sms_tool_q -d /dev/ttyUSB3 at 'AT+QCFG="nat"'` (`1` = modem NAT on → 65; `0` = transparent → 64). You can turn modem NAT off entirely with `AT+QCFG="nat",0` and then `64` is correct — but note it can reset on some module power cycles.

### 3. The first modem slot lost power seconds into every boot (new in the refreshed assets)

The device tree powers the 5G1 M.2 slot on at cold boot (`gpio-export,output = <1>`), but the firmware's board config seeded the matching `gpio_switch` user-space toggle with a default of `0`. The kernel drove the pin high at probe time and the modem enumerated — then a few seconds into every boot `gpio_switch` (start order 94) wrote that `0` over the pin, cutting module power after enumeration. That was the recurring "modem gone after reboot" report. Neither recovery path could help: the auto-enable hotplug only fires on USB events, and the watchdog only acts on slots whose USB device path still exists — which the freshly powered-down slot no longer has.

- `board.d/03_gpio_switches` now seeds `5g1=1`, `5g2=0` and `sim1=1` (SIM1 routed through the mux), matching the DTS and the real at-boot hardware state.
- An upgrade keeps the stale `value=0` config, so `99-zbt-z8803be-qmodem-autostart` runs a one-shot migration during first boot, before `S94gpio_switch` runs: a persisted `0` is raised to `1` and a `zbt_gpio_default` marker is recorded. From then on the firmware never touches the toggle again — an operator who deliberately powers 5G1 off keeps that choice.
- Second refresh fix: the first pass of this migration located the section by its human label (`name`, "Power 5G1 modem slot") instead of its ID, so the comparison never matched and the migration silently did nothing on upgraded systems — the exact symptom a flash of the first refresh showed (modem unpowered after upgrade). It now matches the section ID or `gpio_pin`, and the marker/value writes no longer embed shell quotes (uci stores the text after `=` verbatim).

### 4. WAN failover defaults no longer stomp operator configs (new in the refreshed assets)

Earlier builds deleted and recreated `network.wan` / `wan6` / `wan_sfp` / `wan_sfp6` on every boot and force-appended every uplink to the stock `wan` firewall zone, wiping operator customisations (static WAN addresses, a disabled `wan6`, custom port-to-zone layouts).

`32-zbt-z8803be-wan-failover` is now create-if-missing:

- Only the exact stock shape (one `wan` section spanning `eth1 eth2`) is split into per-port sections so each gets its own route metric (SFP `9`, RJ45 WAN `10`, cellular `200`).
- Missing sections are created with the contract defaults; existing sections only get `metric` / `peerdns` / `defaultroute` filled when the option is unset.
- Firewall zone membership is added only for sections the script itself created, and for the WWAN stubs (`4_1` / `4_1v6`) only when no zone claims them.
- The deterministic DNS policy is unchanged: `peerdns=0` on wired uplinks, and the operator-DNS capture hotplug still ships disabled (`system.zbt_wwan_dns.enabled=0`).

### 5. Twenty stale uci-defaults removed (new in the refreshed assets)

An audit of `etc/uci-defaults/` found twenty scripts that were duplicates of renumbered replacements, configured packages this build no longer ships, or enabled features this build deliberately defaults off. All are deleted, and `tests/check-zbt-firmware.sh` now carries an `absent` guard for each so none of them can ship again: `10-zbt-apk-feeds`, `15-zbt-modem-factory-reset-flag`, `30-zbt-z8803be-wan-failover`, `32-zbt-z8803be-wan-speed-mode`, `35-zbt-qmodem-dns-suppress`, `38-zbt-throughput-tuning`, `40-zbt-qmodem-watchdog-enable`, `44-zbt-qmodem-watchdog-disable`, `45-zbt-qmodem-monitor-enable`, `46-zbt-qmodem-monitor-patch`, `47-zbt-persistent-app-stats`, `47-zbt-qmodem-soft-reboot-patch`, `50-zbt-sms-tool-compat`, `60-zbt-leds-cleanup`, `70-zbt-z8803be-wifi`, `76-zbt-z8803be-admin-password`, `80-zbt-z8803be-dns-cache`, `84-zbt-luci-js-compat`, `99-zbt-z8803be-services`, `99a-zbt-youtubeunblock-disable`.

### 6. Misc

- The `zbt-modem-led` "LED sysfs node /sys/class/leds/5g1 missing — stale DTS?" log spam is gone (stale duplicate handler removed; the real node is `blue:mobile-1`/`blue:mobile-2`).
- Manifest: 280 packages, image unchanged at ~20.7 MB. The only new packages are `luci-app-qmodem-ttlfw4` and its zh-CN translation.

## Validation

- Full Docker firmware rebuild completed successfully; `sha256sum -c sha256sums --ignore-missing` passes for all refreshed artifacts.
- The staged rootfs was inspected in the build volume: all twenty removed scripts absent, the renumbered replacements present (`32-`/`36-`/`40-`/`48-`/`54-`/`56-`/`64-`/`68-`/`72-`/`80-`/`82-`/`86-`/`90-`/`99-`), `board.d/03_gpio_switches` seeds the `5g1` default `1`, and the gpio migration is present in `99-zbt-z8803be-qmodem-autostart`.
- `tests/check-zbt-firmware.sh` — expanded this cycle with stale-file guards plus GPIO/failover/nft invariants — and `git diff --check` pass.
- The NAT-probe's apply paths were exercised with shimmed `uci`/`ip` state (modem NAT → 65, carrier `10.x` address → stays 64, hand-edited ttl → auto-writes disabled, debounce, missing plugin package → skip). The probe and watchdog scripts carry comment-only changes in this refresh; their behavior is unchanged.
- **Hardware-validated on a physical Z8803BE (2026-09-06):** the first refresh was flashed with configuration preserved; the upgrade kept the stale persisted `gpio_switch` `5g1` `value=0` and reproduced the unpowered-modem symptom, which is what exposed the migration no-op above. The corrected migration script was run against that board config: it matched the section by ID, migrated `value=0` to `1` and recorded a clean `zbt_gpio_default=1` marker (traced with `sh -x`). The modem re-enumerated, and after a radio re-attach (`AT+CFUN=0/1` — the carrier's MME was still holding the pre-cut session and rejected data calls with `call_end_reason_verbose 210`) the cellular uplink, DNS and LAN forwarding were restored end to end, with the rewritten WAN-failover zone layout intact.
- The issue #9 fixes validated for the original v25.12.021 build carry over unchanged; issue #9 reporters on older releases can still apply the two-command manual fix above (`enable=1`, `ttl=65`, restart `qmodem_ttl`) without flashing.

## Artifacts

- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin`
  - SHA-256: `fdcdb15b96ab305444491d9cfd6e076c5317a7dfc09cc28842b4bb0d5e2fd927`
- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin`
  - SHA-256: `16eac0891ea46f5611ba96efd7a81bd579e7a2402d1325603497eab65f927c51`
- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be.manifest`
  - SHA-256: `4a4cf6dbc0688f858a092ea0a0d7a79e3d27ce5cb840888df927bbea37e52a5f`
- `packages-aarch64_cortex-a53.tar.gz`
  - SHA-256: `ad0a299a4249c5ed426979b0b0d070be0ef7f7bb738067895c60893e37938172`
- `sha256sums`, `config.buildinfo`, `feeds.buildinfo`, and `version.buildinfo`

## Upgrade
To preserve configuration:

    sysupgrade -v openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin

For a clean configuration:

    sysupgrade -n openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin

After upgrading, if you had enabled the TTL plugin manually with `ttl=64`, leave the value alone — the probe only raises it to 65 if it is still at the seeded 64 or the last value it wrote itself.

Upgrading with configuration kept: on the first boot after the upgrade, the one-shot migration raises a persisted `gpio_switch` `5g1` value of `0` to `1` (the default the hardware should always have had). If you deliberately switched the first modem slot off in LuCI, switch it off again after that first boot — from then on the firmware never touches the toggle.

## Donate
Optional donations help support maintenance and testing:

- **ERC20 / BEP20 — USDT, USDC, ETH, BNB:** `0xd1122130ad6e9ab948212087a90797e3129bfc1c`
- **TRC20 — TRX, USDT:** `TTcT5m4BriHKyNrB4KYyLMK4ZGn54Nk6z2`
- **BTC:** `12N34ZYeiwxKEcM5FSnkgnHwxhW6pE3r4m`
- **LTC:** `LLNtEGeZ5C6QnSY6BU1MYAZjh8MJpF6zsK`
