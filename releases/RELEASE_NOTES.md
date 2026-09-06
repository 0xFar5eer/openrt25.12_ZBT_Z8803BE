# ZBT-Z8803BE OpenWrt 25.12.2 / Linux 6.12.74

Release `v25.12.021` is a community firmware build for ZBTLink ZBT-Z8803BE.

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

The opt-in TTL plugin (`luci-app-qmodem-ttlfw4`, **Modem → QModem → TTL**) rewrites the TTL on egress, and `ttl=65` compensates for the modem's own NAT. Note for testers: a rule matching `iifname "br-lan"` never affects pings run from the router itself, so testing TTL by re-pinging on the router proves nothing — test from a **LAN client**.

New in this release, the firmware figures the right value out by itself:

- `/usr/sbin/zbt-modem-nat-probe` (fired by a new `iface` hotplug on every cellular `ifup`) looks at the address the dialer obtained: `192.0.0.x` / `192.168.225.x` → the modem is NATing → it raises `qmodem_ttl.main.ttl` to **65**; a carrier-assigned address → leaves **64**.
- It never enables the plugin for you, never restarts it while disabled, and if you hand-edit `ttl`, it permanently disables its own writes (`zbt_auto_ttl=0`) and leaves your value alone.
- Optional manual check of the definitive answer: `sms_tool_q -d /dev/ttyUSB3 at 'AT+QCFG="nat"'` (`1` = modem NAT on → 65; `0` = transparent → 64). You can turn modem NAT off entirely with `AT+QCFG="nat",0` and then `64` is correct — but note it can reset on some module power cycles.

### 3. Misc

- The `zbt-modem-led` "LED sysfs node /sys/class/leds/5g1 missing — stale DTS?" log spam is gone (stale duplicate handler removed; the real node is `blue:mobile-1`/`blue:mobile-2`).
- Manifest: 280 packages, image unchanged at ~20.7 MB. The only new packages are `luci-app-qmodem-ttlfw4` and its zh-CN translation.

## Validation

- Full Docker firmware build completed successfully.
- `sha256sum -c sha256sums --ignore-missing` passes for all artifacts.
- The built rootfs was inspected directly: new probe/hotplug present and executable, all six stale duplicates absent, `proto='dhcp'` seeded, no `procd_add_reload_trigger` in the shipped watchdog init.
- The NAT-probe's apply paths were exercised with shimmed `uci`/`ip` state (modem NAT → 65, carrier `10.x` address → stays 64, hand-edited ttl → auto-writes disabled, debounce, missing plugin package → skip).
- `tests/check-zbt-firmware.sh` and `git diff --check` pass.
- **Not yet hardware-tested:** none of this has been confirmed on a Z8803BE with a T-Mobile SIM. Issue #9 reporters: the fastest check on **v25.12.020** without flashing is the two-command manual fix in the section above (`enable=1`, `ttl=65`, restart `qmodem_ttl`).

## Artifacts

- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be-squashfs-sysupgrade.bin`
  - SHA-256: `0b4c093807e7ab6fb34c23f0b766689c12d7f2ca212655643681468b66dab9cd`
- `openwrt-mediatek-filogic-zbtlink_zbt-z8803be-initramfs-kernel.bin`
  - SHA-256: `6254dffe2a51a7d86efde993528466142187598645ecf660f9463b7d89c85b64`
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

## Donate
Optional donations help support maintenance and testing:

- **ERC20 / BEP20 — USDT, USDC, ETH, BNB:** `0xd1122130ad6e9ab948212087a90797e3129bfc1c`
- **TRC20 — TRX, USDT:** `TTcT5m4BriHKyNrB4KYyLMK4ZGn54Nk6z2`
- **BTC:** `12N34ZYeiwxKEcM5FSnkgnHwxhW6pE3r4m`
- **LTC:** `LLNtEGeZ5C6QnSY6BU1MYAZjh8MJpF6zsK`
